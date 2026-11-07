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
        ld      a,'1'
        ld      (p126_neogs_startup_stage),a
        ld      hl,p126_neogs_boot_name
        call    p126_neogs_open_file
        ret     c
        ld      a,'2'
        ld      (p126_neogs_startup_stage),a
        ; The build deliberately permits a full 256-byte ROM #14 block.
        ; Accept lengths 1..255 and exactly 256 (0100h); reject 0 and >256.
        ld      hl,(p126_neogs_file_length)
        ld      a,h
        or      a
        jr      z,.p126_neogs_boot_length_low
        cp      1
        jp      nz,p126_neogs_boot_file_bad
        ld      a,l
        or      a
        jp      nz,p126_neogs_boot_file_bad
        jr      .p126_neogs_boot_length_ok
.p126_neogs_boot_length_low:
        ld      a,l
        or      a
        jp      z,p126_neogs_boot_file_bad
.p126_neogs_boot_length_ok:

        ; Cold-restart the GS105a ROM only to enter its known bootstrap
        ; receive state. Do NOT query #20: its RAM-size report is not an
        ; authority for Project126 physical memory and must not gate startup.
        ld      a,'A'
        ld      (p126_neogs_startup_stage),a
        ld      a,#F4
        call    p126_neogs_send_command_long
        jp      c,p126_neogs_ram_bad



        ; GS105a #14 receives P126BOOT at logical 4000h.
        ld      a,'4'
        ld      (p126_neogs_startup_stage),a
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
        ld      a,'5'
        ld      (p126_neogs_startup_stage),a
        ld      hl,p126_neogs_core_name
        call    p126_neogs_open_file
        ret     c
        ld      a,'6'
        ld      (p126_neogs_startup_stage),a
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
        ld      a,'7'
        ld      (p126_neogs_startup_stage),a
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
        ld      a,'8'
        ld      (p126_neogs_startup_stage),a
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
        ld      a,'9'
        ld      (p126_neogs_startup_stage),a
        ld      hl,#C000
        ld      (p126_neogs_buffer_ptr),hl
        ld      hl,256
        ld      (p126_neogs_buffer_remaining),hl
        ld      de,(p126_neogs_core_length)
.p126_neogs_core_stream:
        ld      a,d
        or      e
        jr      z,.p126_neogs_core_stream_done

        ; Project125 V1 streaming order: refill only after the current
        ; 256-byte buffer is fully consumed, then send each byte and wait
        ; for DBIT consumption before advancing to the next byte.
        ld      hl,(p126_neogs_buffer_remaining)
        ld      a,h
        or      l
        jr      nz,.p126_neogs_core_buffer_ready
        push    de
        call    p126_neogs_read_next_sector
        pop     de
        jp      c,p126_neogs_transport_error
        ld      hl,#C000
        ld      (p126_neogs_buffer_ptr),hl
        ld      hl,256
        ld      (p126_neogs_buffer_remaining),hl
.p126_neogs_core_buffer_ready:
        ld      hl,(p126_neogs_buffer_ptr)
        ld      a,(hl)
        call    p126_neogs_send_byte
        jp      c,p126_neogs_transport_error
        inc     hl
        ld      (p126_neogs_buffer_ptr),hl
        ld      hl,(p126_neogs_buffer_remaining)
        dec     hl
        ld      (p126_neogs_buffer_remaining),hl
        dec     de
        jr      .p126_neogs_core_stream

.p126_neogs_core_stream_done:
        ; As in Project125, receive the resident-ready ACK only after every
        ; payload byte has completed its DBIT-consumed handshake.
        call    p126_neogs_receive_byte
        ret     c
        cp      P126_NGS_ACK_DONE
        jp      nz,p126_neogs_transport_error
.p126_neogs_startup_done:
        ld      a,'0'
        ld      (p126_neogs_startup_stage),a
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
        ; Exact Project125 TR-DOS ROM file-open ABI:
        ; C=#0A searches the 8-character name + extension C at #5CDD,
        ; then C=#08 returns the full descriptor in #5CE8..#5CEC.
        ; Do not parse the preloaded catalogue entries ourselves.
        ld      (p126_neogs_name_ptr),hl
        ld      hl,(p126_neogs_name_ptr)
        ld      de,#5CDD
        ld      bc,8
        ldir
        ld      a,'C'
        ld      (#5CE5),a
        ld      a,9
        ld      (#5D06),a
        ld      c,10
        call    #3D13
        ld      a,c
        cp      #FF
        jp      z,.p126_neogs_file_not_found

        ; C=#0A returns the directory slot in A; C=#08 fetches its descriptor.
        push    af
        xor     a
        ld      (#5D0F),a
        ld      (#5D10),a
        pop     af
        ld      c,8
        call    #3D13
        ld      a,(#5D0F)
        ld      b,a
        ld      a,(#5D10)
        or      b
        jp      nz,.p126_neogs_bad_descriptor

        ; Match Project125: use exact file length and derive sector count
        ; from it, rather than trusting a potentially stale directory count.
        ld      hl,(#5CE8)
        ld      (p126_neogs_file_length),hl
        ld      a,h
        or      l
        jp      z,.p126_neogs_bad_length
        ld      de,#C010
        or      a
        sbc     hl,de
        jr      c,.p126_neogs_file_length_ok
        jp      nz,.p126_neogs_bad_length
.p126_neogs_file_length_ok:
        ld      hl,(p126_neogs_file_length)
        ld      de,255
        add     hl,de
        ld      a,h
        or      a
        jp      z,.p126_neogs_bad_descriptor
        ld      (p126_neogs_file_sectors_left),a

        ld      a,(#5CEB)
        cp      16
        jp      nc,.p126_neogs_bad_descriptor
        ld      (p126_neogs_file_sector),a
        ld      a,(#5CEC)
        ld      (p126_neogs_file_track),a

        ; Acquire only the first sector now; subsequent sectors are read
        ; on demand after the current 256-byte buffer has been consumed.
        call    p126_neogs_read_next_sector
        ret     c
        ld      hl,#C000
        ld      (p126_neogs_buffer_ptr),hl
        ld      hl,256
        ld      (p126_neogs_buffer_remaining),hl
        xor     a
        ret

.p126_neogs_file_not_found:
        ld      a,1
        jr      .p126_neogs_open_failed
.p126_neogs_bad_descriptor:
        ld      a,2
        jr      .p126_neogs_open_failed
.p126_neogs_bad_length:
        ld      a,3
        jr      .p126_neogs_open_failed
.p126_neogs_open_failed:
        ld      (p126_neogs_io_error),a
        scf
        ret

p126_neogs_read_next_sector:
        ; Direct Project125 sector reader: C=5, B=1, HL=#C000,
        ; DE=track/sector. Advance cursor only after successful ROM return.
        ld      a,(p126_neogs_file_sectors_left)
        or      a
        jr      nz,.p126_neogs_sector_available
        scf
        ret
.p126_neogs_sector_available:
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
        jr      nz,.p126_neogs_sector_io_error

        ld      a,(p126_neogs_file_sector)
        inc     a
        cp      16
        jr      c,.p126_neogs_sector_same_track
        xor     a
        ld      (p126_neogs_file_sector),a
        ld      a,(p126_neogs_file_track)
        inc     a
        ld      (p126_neogs_file_track),a
        jr      .p126_neogs_sector_cursor_advanced
.p126_neogs_sector_same_track:
        ld      (p126_neogs_file_sector),a
.p126_neogs_sector_cursor_advanced:
        ld      a,(p126_neogs_file_sectors_left)
        dec     a
        ld      (p126_neogs_file_sectors_left),a
        or      a
        ret
.p126_neogs_sector_io_error:
        ld      a,4
        ld      (p126_neogs_io_error),a
        scf
        ret

; ATM-side diagnostic for the three bytes returned by GS105a #20.
; Format: [time][ATM] [NGS ROM] RAM24=HH:MM:LL
; This is intentionally emitted by ATM: Project126's NeoGS bootstrap is not
; executing yet while the stock ROM handles the #20 probe.
p126_neogs_log_ram_size:
        push    af
        push    bc
        push    de
        push    hl
        call    p126_host_log_prefix
        ld      hl,p126_neogs_ram_log_text
        call    p126_neogs_log_text
        ld      a,(p126_neogs_ram_size+2)
        call    p126_neogs_log_hex_byte
        ld      a,':'
        ld      bc,#00EF
        out     (c),a
        ld      a,(p126_neogs_ram_size+1)
        call    p126_neogs_log_hex_byte
        ld      a,':'
        ld      bc,#00EF
        out     (c),a
        ld      a,(p126_neogs_ram_size)
        call    p126_neogs_log_hex_byte
        ld      a,13
        ld      bc,#00EF
        out     (c),a
        ld      a,10
        out     (c),a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

p126_neogs_log_text:
        push    bc
        ld      bc,#00EF
.p126_neogs_log_text_loop:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,.p126_neogs_log_text_done
        out     (c),a
        jr      .p126_neogs_log_text_loop
.p126_neogs_log_text_done:
        pop     bc
        ret

; IN A=byte; writes two uppercase hexadecimal digits to ATM #EF.
p126_neogs_log_hex_byte:
        push    bc
        ld      c,#EF
        ld      b,a
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    p126_neogs_log_hex_nibble
        ld      a,b
        and     #0F
        call    p126_neogs_log_hex_nibble
        pop     bc
        ret

p126_neogs_log_hex_nibble:
        cp      10
        jr      c,.p126_neogs_log_hex_digit
        add     'A'-10
        jr      .p126_neogs_log_hex_out
.p126_neogs_log_hex_digit:
        add     '0'
.p126_neogs_log_hex_out:
        out     (c),a
        ret

 ; Query the stock ROM for its 24-bit RAM size. Project126 requires 4 MiB.
p126_neogs_probe_rom_ram:
        ld      a,'C'                 ; C: send #20 and wait for CBIT
        ld      (p126_neogs_startup_stage),a
        ld      a,P126_NGS_CMD_RAM
        call    p126_neogs_send_command_long
        ret     c
        ld      a,'D'                 ; D: wait for/read RAM byte 0
        ld      (p126_neogs_startup_stage),a
        call    p126_neogs_receive_byte
        ret     c
        ld      (p126_neogs_ram_size),a
        ld      a,'E'                 ; E: wait for/read RAM byte 1
        ld      (p126_neogs_startup_stage),a
        call    p126_neogs_receive_byte
        ret     c
        ld      (p126_neogs_ram_size+1),a
        ld      a,'F'                 ; F: wait for/read RAM byte 2
        ld      (p126_neogs_startup_stage),a
        call    p126_neogs_receive_byte
        ret     c
        ld      (p126_neogs_ram_size+2),a
        ld      a,'G'                 ; G: validate reported 24-bit RAM size
        ld      (p126_neogs_startup_stage),a
        ; At this point the stock GS105a ROM still owns the NeoGS CPU.
        ; Capture the exact response on the ATM's independent #EF channel.
        call    p126_neogs_log_ram_size
        ld      a,(p126_neogs_ram_size+2)
        cp      #40
        jr      c,.p126_neogs_ram_probe_bad
        or      a
        ret
.p126_neogs_ram_probe_bad:
        scf
        ret

; Extended CBIT wait based on the known-working Project125 GS105a driver.
p126_neogs_send_command_long:
        ld      (p126_neogs_tx_byte),a
        ld      a,(p126_neogs_tx_byte)
        out     (P126_NGS_GSCOM),a
        push    de
        ld      d,16
.p126_neogs_command_long_outer:
        ld      bc,#FFFF
.p126_neogs_command_long_inner:
        in      a,(P126_NGS_GSSTAT)
        bit     P126_NGS_CBIT,a
        jr      z,.p126_neogs_command_long_done
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_neogs_command_long_inner
        dec     d
        jr      nz,.p126_neogs_command_long_outer
        pop     de
        scf
        ret
.p126_neogs_command_long_done:
        pop     de
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
        ; GS105a #13/#14 consume their first argument byte before command
        ; dispatch. The DBIT wait clobbers A with GSSTAT, so preserve the
        ; argument exactly as Project125's gs_boot_write_command_argument does.
        ld      (p126_neogs_tx_byte),a
        call    p126_neogs_wait_dbit_clear
        ret     c
        ld      a,(p126_neogs_tx_byte)
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
        ; Give the GS105a sender time to observe DBIT being cleared.
        push    af
        push    bc
        ld      bc,#0400
.p126_neogs_receive_turnaround:
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_neogs_receive_turnaround
        pop     bc
        pop     af
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
p126_neogs_ram_log_text: db "[NGS ROM] RAM24=",0
p126_neogs_file_sectors_left: db 0
p126_neogs_file_sector: db 0
p126_neogs_file_track: db 0
p126_neogs_io_error: db 0
p126_neogs_tx_byte: db 0
p126_neogs_startup_error: db 0
p126_neogs_startup_stage: db '0'


; Build and send one maximum-size ABI 1.0 diagnostics request.
; The complete 16 KiB host buffer occupies ATM RAM page 0 at C000-FFFF.
; Page 0 is restored by p126_atm_video_init and is otherwise the TR-DOS
; staging window. The reverse-DMA test reuses this same buffer after TX.
p126_neogs_dma_smoke_test::
        ; The ATM host TR-DOS file is packaged only through A800h. The
        ; C000h staging buffer is runtime RAM, not part of that file, so
        ; initialize every header byte explicitly on each test invocation.
        ld      hl,p126_neogs_dma_test_frame
        ld      a,'P'
        ld      (hl),a
        inc     hl
        ld      a,'1'
        ld      (hl),a
        inc     hl
        ld      a,'2'
        ld      (hl),a
        inc     hl
        ld      a,'6'
        ld      (hl),a
        inc     hl
        ld      a,P126_IPC_MAJOR
        ld      (hl),a
        inc     hl
        ld      a,P126_IPC_MINOR
        ld      (hl),a
        inc     hl
        ld      a,P126_MSG_REQUEST
        ld      (hl),a
        inc     hl
        ld      a,P126_SERVICE_DIAGNOSTICS
        ld      (hl),a
        inc     hl
        ld      a,P126_OP_DIAGNOSTIC
        ld      (hl),a
        inc     hl
        xor     a
        ld      (hl),a                 ; flags
        inc     hl
        ld      a,#02
        ld      (hl),a                 ; sequence low
        inc     hl
        xor     a
        ld      (hl),a                 ; sequence high
        inc     hl
        ld      a,#EE
        ld      (hl),a                 ; payload length low
        inc     hl
        ld      a,#3F
        ld      (hl),a                 ; payload length high
        inc     hl
        xor     a
        ld      (hl),a                 ; status low
        inc     hl
        ld      (hl),a                 ; status high
        inc     hl
        ld      (hl),a                 ; CRC low (filled below)
        inc     hl
        ld      (hl),a                 ; CRC high (filled below)

        ld      hl,p126_neogs_dma_test_frame+P126_IPC_HEADER_SIZE
        ld      bc,P126_IPC_MAX_PAYLOAD
        ld      e,0
.p126_neogs_dma_fill:
        ld      a,e
        ld      (hl),a
        inc     hl
        inc     e
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_neogs_dma_fill

        ; CRC-16/CCITT-FALSE over header[0..15] and all 16366 payload bytes.
        ld      hl,#FFFF
        ld      de,p126_neogs_dma_test_frame
        ld      b,16
.p126_neogs_dma_crc_header:
        ld      a,(de)
        inc     de
        call    p126_ipc_crc16_update
        djnz    .p126_neogs_dma_crc_header
        inc     de
        inc     de
        ld      bc,P126_IPC_MAX_PAYLOAD
.p126_neogs_dma_crc_payload:
        ld      a,(de)
        inc     de
        call    p126_ipc_crc16_update
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_neogs_dma_crc_payload
        ld      (p126_neogs_dma_test_frame+P126_IPC_OFF_CRC),hl
        ld      hl,p126_neogs_dma_test_frame
        ld      bc,P126_IPC_MAX_FRAME_SIZE
        jp      p126_ipc_dma_send_frame

p126_neogs_dma_test_frame EQU #C000
        ASSERT  p126_neogs_dma_test_frame + P126_IPC_MAX_FRAME_SIZE = #10000
