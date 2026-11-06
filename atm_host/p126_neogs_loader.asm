; =========================================================================
; PROJECT126 — ATM host NeoGS bootstrap/firmware loader
; Runs before ATM video paging is enabled. TR-DOS sector reads use the same
; C=5/B=1 ABI already validated by p126_catalog_read_disk.
; =========================================================================
P126_NGS_GSCOM EQU #BB
P126_NGS_GSSTAT EQU #BB
P126_NGS_GSDAT EQU #B3
P126_NGS_GSCTR EQU #33
P126_NGS_CBIT EQU 0
P126_NGS_DBIT EQU 7
P126_NGS_CMD_RAM EQU #20
P126_NGS_CMD_JUMP EQU #13
P126_NGS_CMD_RECV EQU #14
P126_NGS_ACK_READY EQU #A1
P126_NGS_ACK_LENGTH EQU #A3
P126_NGS_ACK_DONE EQU #A2
P126_NGS_TIMEOUT EQU #FFFF

; Called after directory preload and before ATM video initialization.
; Carry clear means the resident image sent its A2h ready acknowledgement.
p126_neogs_startup::
        ld      hl,p126_neogs_boot_name
        call    p126_neogs_open_file
        ret     c
        ld      hl,(p126_neogs_file_length)
        ld      a,h
        or      a
        jp      nz,p126_neogs_boot_file_bad
        ld      a,l
        or      a
        jp      z,p126_neogs_boot_file_bad

        ; Reset NeoGS into the stock GS105a ROM before #20/#14/#13.
        ld      a,#80
        out     (P126_NGS_GSCTR),a
        ld      bc,#FFFF
.p126_neogs_reset_delay:
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_neogs_reset_delay

        ld      a,P126_NGS_CMD_RAM
        call    p126_neogs_send_command
        ret     c
        call    p126_neogs_receive_byte
        ret     c
        ld      (p126_neogs_ram_size),a
        call    p126_neogs_receive_byte
        ret     c
        ld      (p126_neogs_ram_size+1),a
        call    p126_neogs_receive_byte
        ret     c
        ld      (p126_neogs_ram_size+2),a
        ld      a,(p126_neogs_ram_size+2)
        cp      #40
        jp      c,p126_neogs_ram_bad

        ; GS105a #14 receives P126BOOT at logical 4000h.
        ld      hl,0
        ld      de,(p126_neogs_file_length)
        or      a
        sbc     hl,de
        ld      (p126_neogs_block_length),hl
        ld      a,l
        call    p126_neogs_send_argument
        ret     c
        ld      a,P126_NGS_CMD_RECV
        call    p126_neogs_send_command
        ret     c
        ld      a,(p126_neogs_block_length+1)
        call    p126_neogs_send_byte
        ret     c
        xor     a
        call    p126_neogs_send_byte
        ret     c
        ld      a,#40
        call    p126_neogs_send_byte
        ret     c
        ld      hl,#C000
        ld      de,(p126_neogs_file_length)
.p126_neogs_boot_stream:
        ld      a,d
        or      e
        jr      z,.p126_neogs_boot_loaded
        ld      a,(hl)
        call    p126_neogs_send_byte
        ret     c
        inc     hl
        dec     de
        jr      .p126_neogs_boot_stream
.p126_neogs_boot_loaded:
        ; Read the first resident-image sector before starting stage-0.
        ld      hl,p126_neogs_core_name
        call    p126_neogs_open_file
        ret     c
        ld      hl,(p126_neogs_file_length)
        ld      a,h
        cp      #40
        jr      c,.p126_neogs_core_size_low
        jp      nz,p126_neogs_core_file_bad
        ld      a,l
        or      a
        jp      nz,p126_neogs_core_file_bad
.p126_neogs_core_size_low:
        ld      a,h
        or      l
        jp      z,p126_neogs_core_file_bad
        ld      hl,(p126_neogs_file_length)
        ld      (p126_neogs_core_length),hl

        ; Enter stage-0 at 4000h; it publishes A1h when ready.
        xor     a
        call    p126_neogs_send_argument
        ret     c
        ld      a,P126_NGS_CMD_JUMP
        call    p126_neogs_send_command
        ret     c
        ld      a,#40
        call    p126_neogs_send_byte
        jr      nc,.p126_neogs_jump_tx_done
        in      a,(P126_NGS_GSSTAT)
        bit     P126_NGS_DBIT,a
        jp      z,p126_neogs_transport_error
        call    p126_neogs_receive_byte
        ret     c
        cp      P126_NGS_ACK_READY
        jp      nz,p126_neogs_transport_error
        jr      .p126_neogs_stage0_ready
.p126_neogs_jump_tx_done:
        call    p126_neogs_receive_byte
        ret     c
        cp      P126_NGS_ACK_READY
        jp      nz,p126_neogs_transport_error

.p126_neogs_stage0_ready:
        ; Length exchange; A3h confirms the resident image size.
        ld      hl,(p126_neogs_core_length)
        ld      a,l
        call    p126_neogs_send_byte
        ret     c
        ld      a,h
        call    p126_neogs_send_byte
        jr      nc,.p126_neogs_length_sent
        in      a,(P126_NGS_GSSTAT)
        bit     P126_NGS_DBIT,a
        jp      z,p126_neogs_transport_error
        call    p126_neogs_receive_byte
        ret     c
        cp      P126_NGS_ACK_LENGTH
        jp      nz,p126_neogs_transport_error
        jr      .p126_neogs_stream_begin
.p126_neogs_length_sent:
        call    p126_neogs_receive_byte
        ret     c
        cp      P126_NGS_ACK_LENGTH
        jp      nz,p126_neogs_transport_error

.p126_neogs_stream_begin:
        ld      hl,#C000
        ld      (p126_neogs_buffer_ptr),hl
        ld      hl,256
        ld      (p126_neogs_buffer_remaining),hl
        ld      de,(p126_neogs_core_length)
.p126_neogs_core_stream:
        ld      a,d
        or      e
        jr      z,.p126_neogs_core_stream_done
        ld      hl,(p126_neogs_buffer_remaining)
        ld      a,h
        or      l
        jr      nz,.p126_neogs_core_buffer_ready
        push    de
        call    p126_neogs_read_next_sector
        pop     de
        ret     c
        ld      hl,#C000
        ld      (p126_neogs_buffer_ptr),hl
        ld      hl,256
        ld      (p126_neogs_buffer_remaining),hl
.p126_neogs_core_buffer_ready:
        ld      hl,(p126_neogs_buffer_ptr)
        ld      a,(hl)
        call    p126_neogs_send_byte
        jr      nc,.p126_neogs_core_byte_sent
        ; The resident can publish A2h immediately after consuming the final
        ; byte. In that case one byte remains in DE and DBIT is already set.
        ld      a,d
        or      a
        jp      nz,p126_neogs_transport_error
        ld      a,e
        cp      1
        jp      nz,p126_neogs_transport_error
        in      a,(P126_NGS_GSSTAT)
        bit     P126_NGS_DBIT,a
        jp      z,p126_neogs_transport_error
        call    p126_neogs_receive_byte
        ret     c
        cp      P126_NGS_ACK_DONE
        jp      nz,p126_neogs_transport_error
        jr      .p126_neogs_startup_done
.p126_neogs_core_byte_sent:
        inc     hl
        ld      (p126_neogs_buffer_ptr),hl
        ld      hl,(p126_neogs_buffer_remaining)
        dec     hl
        ld      (p126_neogs_buffer_remaining),hl
        dec     de
        jr      .p126_neogs_core_stream

.p126_neogs_core_stream_done:
        call    p126_neogs_receive_byte
        ret     c
        cp      P126_NGS_ACK_DONE
        jp      nz,p126_neogs_transport_error
.p126_neogs_startup_done:
        xor     a
        ret

p126_neogs_boot_file_bad:
        ld      a,1
        jr      p126_neogs_store_error
p126_neogs_core_file_bad:
        ld      a,2
        jr      p126_neogs_store_error
p126_neogs_ram_bad:
        ld      a,3
        jr      p126_neogs_store_error
p126_neogs_transport_error:
        ld      a,4
p126_neogs_store_error:
        ld      (p126_neogs_startup_error),a
        scf
        ret

; IN HL=exact 8-character filename. Directory was preloaded at C800h.
; OUT: carry clear, first sector at C000h, metadata initialized.
p126_neogs_open_file:
        ld      (p126_neogs_name_ptr),hl
        ld      ix,#C800
        ld      b,128
.p126_neogs_find_loop:
        push    ix
        push    bc
        ld      hl,(p126_neogs_name_ptr)
        ld      c,8
.p126_neogs_compare:
        ld      a,(hl)
        cp      (ix+0)
        jr      nz,.p126_neogs_find_miss
        inc     hl
        inc     ix
        dec     c
        jr      nz,.p126_neogs_compare
        ld      a,(ix+0)
        cp      'C'
        jr      z,.p126_neogs_find_hit
.p126_neogs_find_miss:
        pop     bc
        pop     ix
        ld      de,16
        add     ix,de
        djnz    .p126_neogs_find_loop
        scf
        ret
.p126_neogs_find_hit:
        pop     bc
        pop     de
        ld      a,(ix+3)
        ld      (p126_neogs_file_length),a
        ld      a,(ix+4)
        ld      (p126_neogs_file_length+1),a
        ld      a,(ix+5)
        ld      (p126_neogs_file_sectors_left),a
        ld      a,(ix+6)
        ld      (p126_neogs_file_sector),a
        ld      a,(ix+7)
        ld      (p126_neogs_file_track),a
        ld      a,(p126_neogs_file_sectors_left)
        or      a
        jr      nz,.p126_neogs_file_meta_ok
        scf
        ret
.p126_neogs_file_meta_ok:
        call    p126_neogs_read_next_sector
        ret     c
        ld      hl,#C000
        ld      (p126_neogs_buffer_ptr),hl
        ld      hl,256
        ld      (p126_neogs_buffer_remaining),hl
        xor     a
        ret

; Read one sector at the current TR-DOS cursor. Preserves all Z80 registers.
p126_neogs_read_next_sector:
        ld      a,(p126_neogs_file_sectors_left)
        or      a
        jr      nz,.p126_neogs_read_sector_ready
        scf
        ret
.p126_neogs_read_sector_ready:
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        exx
        push    bc
        push    de
        push    hl
        exx
        ex      af,af'
        push    af
        ex      af,af'
        ld      (p126_neogs_saved_sp),sp
        ld      sp,#BFFF

        ld      a,(p126_neogs_file_track)
        ld      d,a
        ld      a,(p126_neogs_file_sector)
        ld      e,a
        ld      hl,#C000
        ld      b,1
        ld      c,5
        xor     a
        ld      (#5D0F),a
        ld      (#5D10),a
        call    #3D13
        ld      a,(#5D0F)
        ld      b,a
        ld      a,(#5D10)
        or      b
        ld      (p126_neogs_io_error),a
        jr      nz,.p126_neogs_read_restore

        ld      a,(p126_neogs_file_sector)
        inc     a
        cp      16
        jr      c,.p126_neogs_sector_advanced
        xor     a
        ld      (p126_neogs_file_sector),a
        ld      a,(p126_neogs_file_track)
        inc     a
        ld      (p126_neogs_file_track),a
        jr      .p126_neogs_sector_count
.p126_neogs_sector_advanced:
        ld      (p126_neogs_file_sector),a
.p126_neogs_sector_count:
        ld      a,(p126_neogs_file_sectors_left)
        dec     a
        ld      (p126_neogs_file_sectors_left),a

.p126_neogs_read_restore:
        ld      sp,(p126_neogs_saved_sp)
        ex      af,af'
        pop     af
        ex      af,af'
        exx
        pop     hl
        pop     de
        pop     bc
        exx
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ld      a,(p126_neogs_io_error)
        or      a
        jr      z,.p126_neogs_read_ok
        scf
        ret
.p126_neogs_read_ok:
        or      a
        ret

; Stock GS105a command/data primitives. Application payloads do not use these.
p126_neogs_send_command:
        ld      (p126_neogs_tx_byte),a
        ld      a,(p126_neogs_tx_byte)
        out     (P126_NGS_GSCOM),a
        ld      bc,P126_NGS_TIMEOUT
.p126_neogs_command_wait:
        in      a,(P126_NGS_GSSTAT)
        bit     P126_NGS_CBIT,a
        jr      z,.p126_neogs_command_ok
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_neogs_command_wait
        scf
        ret
.p126_neogs_command_ok:
        or      a
        ret

p126_neogs_send_argument:
        call    p126_neogs_wait_dbit_clear
        ret     c
        out     (P126_NGS_GSDAT),a
        or      a
        ret

p126_neogs_send_byte:
        ld      (p126_neogs_tx_byte),a
        call    p126_neogs_wait_dbit_clear
        ret     c
        ld      a,(p126_neogs_tx_byte)
        out     (P126_NGS_GSDAT),a
        jp      p126_neogs_wait_dbit_clear

p126_neogs_receive_byte:
        call    p126_neogs_wait_dbit_set
        ret     c
        in      a,(P126_NGS_GSDAT)
        or      a
        ret

p126_neogs_wait_dbit_clear:
        ld      bc,P126_NGS_TIMEOUT
.p126_neogs_dbit_clear_loop:
        in      a,(P126_NGS_GSSTAT)
        bit     P126_NGS_DBIT,a
        jr      z,.p126_neogs_dbit_clear_ok
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_neogs_dbit_clear_loop
        scf
        ret
.p126_neogs_dbit_clear_ok:
        or      a
        ret

p126_neogs_wait_dbit_set:
        ld      bc,P126_NGS_TIMEOUT
.p126_neogs_dbit_set_loop:
        in      a,(P126_NGS_GSSTAT)
        bit     P126_NGS_DBIT,a
        jr      nz,.p126_neogs_dbit_set_ok
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_neogs_dbit_set_loop
        scf
        ret
.p126_neogs_dbit_set_ok:
        or      a
        ret

p126_neogs_boot_name: db "P126BOOT"
p126_neogs_core_name: db "X86CORE "
p126_neogs_name_ptr: dw 0
p126_neogs_file_length: dw 0
p126_neogs_core_length: dw 0
p126_neogs_block_length: dw 0
p126_neogs_buffer_ptr: dw #C000
p126_neogs_buffer_remaining: dw 0
p126_neogs_saved_sp: dw 0
p126_neogs_ram_size: db 0,0,0
p126_neogs_file_sectors_left: db 0
p126_neogs_file_sector: db 0
p126_neogs_file_track: db 0
p126_neogs_io_error: db 0
p126_neogs_tx_byte: db 0
p126_neogs_startup_error: db 0
