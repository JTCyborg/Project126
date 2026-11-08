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
        ; Separate payload transfer from the final resident-ready handshake.
        ld      a,'B'
        ld      (p126_neogs_startup_stage),a
        ; As in Project125, receive the resident-ready ACK only after every
        ; payload byte has completed its DBIT-consumed handshake.
        call    p126_neogs_receive_byte
        ret     c
        cp      P126_NGS_ACK_DONE
        jp      nz,p126_neogs_transport_error

        ; Separate the final ACK from manifest file I/O/validation.
        ld      a,'M'
        ld      (p126_neogs_startup_stage),a
        ; Load and validate the versioned module directory before installing
        ; any overlay. It is the build-produced source of size/CRC/page metadata.
        call    p126_neogs_load_manifest
        ret     c

        ; The resident now owns GSCOM and is polling the ABI 1.0 DMA endpoint.
        ; Iterate the module descriptors instead of maintaining four separate
        ; startup call sites. Each descriptor is cross-checked with X86MODS.M.
        ld      hl,p126_neogs_module_table
        ld      b,6
.p126_neogs_module_loop:
        ld      a,(hl)                 ; module ID
        ld      (p126_neogs_manifest_module_id),a
        inc     hl
        ld      a,(hl)                 ; IMAGE kind
        ld      (p126_neogs_overlay_kind),a
        inc     hl
        ld      a,(hl)                 ; physical overlay page
        ld      (p126_neogs_overlay_page),a
        inc     hl
        ld      e,(hl)                 ; maximum size
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      (p126_neogs_overlay_max_size),de
        ld      e,(hl)                 ; TR-DOS filename pointer
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)                 ; preserve startup diagnostic stage
        ld      (p126_neogs_startup_stage),a
        inc     hl
        push    hl                     ; next descriptor
        ex      de,hl
        ld      a,(p126_neogs_overlay_kind)
        ld      de,(p126_neogs_overlay_max_size)
        push    bc                     ; loader/IPC routines may use B
        call    p126_neogs_load_fixed_overlay
        pop     bc
        pop     hl
        ret     c
        djnz    .p126_neogs_module_loop

.p126_neogs_startup_done:
        ld      a,'0'
        ld      (p126_neogs_startup_stage),a
        xor     a
        ret

; -------------------------------------------------------------------------
; Version-1 X86MODS.M loader and validator.
; Layout: 7-byte header followed by six 8-byte records:
; id, physical page, flags, reserved, size16, CRC16/CCITT-FALSE.
; -------------------------------------------------------------------------
p126_neogs_load_manifest:
        ; Lowercase sub-stages identify the manifest open and validation path.
        ld      a,'m'
        ld      (p126_neogs_startup_stage),a
        xor     a
        ld      (p126_neogs_manifest_valid),a
        ld      hl,p126_neogs_manifest_name
        ; X86MODS uses the TR-DOS CODE extension (C), like the overlays.
        ld      a,'C'
        ld      (p126_neogs_file_extension),a
        call    p126_neogs_open_file
        ret     c
        ; V remains active only while checking the exact 55-byte file size.
        ld      a,'V'
        ld      (p126_neogs_startup_stage),a
        ld      hl,(p126_neogs_file_length)
        ld      de,55
        or      a
        sbc     hl,de
        jp      nz,.manifest_bad
        ld      hl,#C000
        ld      de,p126_neogs_manifest
        ld      bc,55
        ldir

        ld      hl,p126_neogs_manifest
        ld      a,'a'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      'P'
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'b'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      '1'
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'c'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      '2'
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'d'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      '6'
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'e'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      1
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'f'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      6
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'g'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      8
        jp      nz,.manifest_bad

        ld      hl,p126_neogs_manifest+7
        ld      b,6
        ld      c,1
        ld      d,6
.manifest_record_loop:
        ld      a,c
        ld      (p126_neogs_manifest_record_index),a
        ld      a,'h'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      c
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'i'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      d
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'j'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        cp      1
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'k'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        or      a
        jp      nz,.manifest_bad
        inc     hl
        ld      a,'l'
        ld      (p126_neogs_startup_stage),a
        ld      a,(hl)
        ld      e,a
        ld      (p126_neogs_manifest_record_size),a
        inc     hl
        ld      a,(hl)
        ld      (p126_neogs_manifest_record_size+1),a
        inc     hl
        ; OR is used only for the zero-size test and destroys A. Reload the
        ; original high byte before applying the 16 KiB per-module limit.
        or      e
        jr      z,.manifest_bad
        ld      a,'m'
        ld      (p126_neogs_startup_stage),a
        ld      a,(p126_neogs_manifest_record_size+1)
        cp      #40
        jr      c,.manifest_size_ok
        jp      nz,.manifest_bad
        ld      a,e
        or      a
        jp      nz,.manifest_bad
.manifest_size_ok:
        inc     hl
        inc     hl
        inc     c
        inc     d
        djnz    .manifest_record_loop
        ld      a,1
        ld      (p126_neogs_manifest_valid),a
        or      a
        ret
.manifest_bad:
        ld      a,10
        ld      (p126_neogs_startup_error),a
        scf
        ret

; Verify the just-staged overlay against its catalog record before IMAGE_BEGIN.
; IN: p126_neogs_overlay_kind and p126_neogs_overlay_size.
; OUT: carry clear on exact size+CRC match.
p126_neogs_verify_overlay_manifest:
        ld      a,(p126_neogs_manifest_valid)
        or      a
        jp      z,.manifest_verify_bad
        ld      a,(p126_neogs_overlay_kind)
        cp      P126_IMAGE_KIND_X86IO
        jr      nz,.manifest_verify_alu
        ld      a,1
        jr      .manifest_verify_id
.manifest_verify_alu:
        cp      P126_IMAGE_KIND_X86ALU
        jr      nz,.manifest_verify_dev
        ld      a,2
        jr      .manifest_verify_id
.manifest_verify_dev:
        cp      P126_IMAGE_KIND_X86DEV
        jr      nz,.manifest_verify_exec
        ld      a,3
        jr      .manifest_verify_id
.manifest_verify_exec:
        cp      P126_IMAGE_KIND_X86EXEC
        jr      nz,.manifest_verify_vga
        ld      a,4
        jr      .manifest_verify_id
.manifest_verify_vga:
        cp      P126_IMAGE_KIND_X86VGA
        jr      nz,.manifest_verify_vid
        ld      a,5
        jr      .manifest_verify_id
.manifest_verify_vid:
        cp      P126_IMAGE_KIND_X86VID
        jp      nz,.manifest_verify_bad
        ld      a,6
.manifest_verify_id:
        ; Descriptor ID and IMAGE kind must identify the same module.
        ld      b,a
        ld      a,(p126_neogs_manifest_module_id)
        cp      b
        jp      nz,.manifest_verify_bad
        ld      a,b
        dec     a
        add     a,a
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,p126_neogs_manifest+7
        add     hl,de
        ld      (p126_neogs_manifest_record_ptr),hl

        ; The build descriptor and manifest must agree on physical placement.
        inc     hl
        ld      a,(hl)
        ld      b,a
        ld      a,(p126_neogs_overlay_page)
        cp      b
        jp      nz,.manifest_verify_bad

        ; Exact size must agree with the directory record.
        inc     hl
        inc     hl
        inc     hl
        ld      de,(p126_neogs_overlay_size)
        ld      a,(hl)
        cp      e
        jr      nz,.manifest_verify_bad
        inc     hl
        ld      a,(hl)
        cp      d
        jr      nz,.manifest_verify_bad

        ; CRC the exact logical file bytes in the DMA frame staging area.
        ld      hl,#FFFF
        ld      de,#C01C
        ld      bc,(p126_neogs_overlay_size)
.manifest_crc_loop:
        ld      a,b
        or      c
        jr      z,.manifest_crc_done
        ld      a,(de)
        call    p126_ipc_crc16_update
        inc     de
        dec     bc
        jr      .manifest_crc_loop
.manifest_crc_done:
        ld      (p126_neogs_manifest_crc_work),hl
        ld      hl,(p126_neogs_manifest_record_ptr)
        ld      de,6
        add     hl,de
        ld      de,(p126_neogs_manifest_crc_work)
        ld      a,(hl)
        cp      e
        jr      nz,.manifest_verify_bad
        inc     hl
        ld      a,(hl)
        cp      d
        jr      nz,.manifest_verify_bad
        or      a
        ret
.manifest_verify_bad:
        scf
        ret

; -------------------------------------------------------------------------
; Load fixed-origin X86IO/X86ALU overlays from TR-DOS through the shared
; ABI 1.0 fixed-profile IMAGE service.
;
; p126_neogs_open_file reads sector 0 to C000h and leaves the remaining
; sector cursor in the shared TR-DOS state. Move the first sector backwards
; into the IMAGE fragment data area at C01Ch (overlap-safe LDDR), then read
; subsequent sectors directly into the following 256-byte slots. This avoids
; a second staging buffer and preserves the 18-byte frame header.
; -------------------------------------------------------------------------
; Shared module loader. IN: HL=TR-DOS 8-byte name, A=IMAGE kind,
; DE=maximum accepted size. The manifest verifier binds the descriptor ID,
; exact file length and CRC before the DMA transaction is allowed to start.
p126_neogs_load_fixed_overlay:
        ld      (p126_neogs_overlay_kind),a
        ld      (p126_neogs_overlay_max_size),de
        call    p126_neogs_open_file
        jr      nc,.fixed_overlay_open
        ld      a,5
        jp      p126_neogs_store_error

.fixed_overlay_open:
        ld      hl,(p126_neogs_file_length)
        ld      a,h
        or      l
        jr      z,.fixed_overlay_bad_size
        ld      de,(p126_neogs_overlay_max_size)
        or      a
        sbc     hl,de
        jr      c,.fixed_overlay_size_ok
        jr      z,.fixed_overlay_size_ok
.fixed_overlay_bad_size:
        ld      a,6
        jp      p126_neogs_store_error

.fixed_overlay_size_ok:
        ld      hl,(p126_neogs_file_length)
        ld      (p126_neogs_overlay_size),hl

        ; The first sector is already in C000h. Copy min(file_size,256)
        ; bytes backwards to C01Ch so source/destination overlap is safe.
        ld      hl,(p126_neogs_file_length)
        ld      de,256
        or      a
        sbc     hl,de
        jr      c,.fixed_overlay_first_partial
        ld      bc,256
        jr      .fixed_overlay_first_copy
.fixed_overlay_first_partial:
        ld      bc,(p126_neogs_file_length)
.fixed_overlay_first_copy:
        ld      hl,#C000
        add     hl,bc
        dec     hl
        push    hl
        ld      hl,#C01C
        add     hl,bc
        dec     hl
        ex      de,hl
        pop     hl
        lddr

        ; Remaining sectors are read directly after the first 256-byte block.
        ld      hl,#C11C
        ld      (p126_neogs_overlay_data_ptr),hl
.fixed_overlay_sector_loop:
        ld      a,(p126_neogs_file_sectors_left)
        or      a
        jr      z,.fixed_overlay_data_ready
        call    p126_neogs_overlay_read_sector
        jr      nc,.fixed_overlay_sector_ok
        ld      a,7
        jp      p126_neogs_store_error
.fixed_overlay_sector_ok:
        ld      hl,(p126_neogs_overlay_data_ptr)
        ld      de,256
        add     hl,de
        ld      (p126_neogs_overlay_data_ptr),hl
        jr      .fixed_overlay_sector_loop

.fixed_overlay_data_ready:
        ; IMAGE_BEGIN: id=1, kind, physical destination page, exact u16 byte length.
        ld      a,1
        ld      (#C012),a
        xor     a
        ld      (#C013),a
        ld      a,(p126_neogs_overlay_kind)
        ld      (#C014),a
        ld      a,(p126_neogs_overlay_page)
        ld      (#C015),a
        ld      hl,(p126_neogs_overlay_size)
        ld      (#C016),hl
        xor     a
        ld      (p126_bios_frame_flags),a
        call    p126_neogs_verify_overlay_manifest
        jr      nc,.fixed_overlay_manifest_ok
        ld      a,9
        jp      p126_neogs_store_error
.fixed_overlay_manifest_ok:
        ld      a,(p126_neogs_overlay_kind)
        cp      P126_IMAGE_KIND_X86IO
        jr      nz,.fixed_overlay_log_not_io
        ld      hl,p126_neogs_io_log_begin
        jr      .fixed_overlay_log_begin
.fixed_overlay_log_not_io:
        cp      P126_IMAGE_KIND_X86ALU
        jr      nz,.fixed_overlay_log_dev_begin
        ld      hl,p126_neogs_alu_log_begin
        jr      .fixed_overlay_log_begin
.fixed_overlay_log_dev_begin:
        cp      P126_IMAGE_KIND_X86DEV
        jr      nz,.fixed_overlay_log_exec_begin
        ld      hl,p126_neogs_dev_log_begin
        jr      .fixed_overlay_log_begin
.fixed_overlay_log_exec_begin:
        cp      P126_IMAGE_KIND_X86VID
        jr      nz,.fixed_overlay_log_vid_begin
        ld      hl,p126_neogs_vid_log_begin
        jr      .fixed_overlay_log_begin
.fixed_overlay_log_vid_begin:
        cp      P126_IMAGE_KIND_X86VGA
        jr      nz,.fixed_overlay_log_vga_begin
        ld      hl,p126_neogs_vga_log_begin
        jr      .fixed_overlay_log_begin
.fixed_overlay_log_vga_begin:
        ld      hl,p126_neogs_exec_log_begin
.fixed_overlay_log_begin:
        call    p126_neogs_log_text
        ld      bc,6
        ld      de,1
        xor     a
        call    p126_bios_send_frame
        jp      c,.fixed_overlay_transport_error

        ; One FRAGMENT: id=1, index=0, count=1, u32 total length.
        ld      a,1
        ld      (#C012),a
        xor     a
        ld      (#C013),a
        xor     a
        ld      (#C014),a
        ld      (#C015),a
        ld      a,1
        ld      (#C016),a
        xor     a
        ld      (#C017),a
        ld      hl,(p126_neogs_overlay_size)
        ld      (#C018),hl
        xor     a
        ld      (#C01A),a
        ld      (#C01B),a
        ld      hl,(p126_neogs_overlay_size)
        ld      de,P126_IPC_FRAGMENT_HEADER
        add     hl,de
        ld      b,h
        ld      c,l
        ld      a,P126_FLAG_FRAGMENT
        ld      (p126_bios_frame_flags),a
        ld      de,2
        ld      a,P126_OP_IMAGE_FRAGMENT
        call    p126_bios_send_frame
        jp      c,.fixed_overlay_transport_error

        ; IMAGE_FINISH is accepted only after target readback and gate checks.
        ld      a,1
        ld      (#C012),a
        xor     a
        ld      (#C013),a
        xor     a
        ld      (p126_bios_frame_flags),a
        ld      bc,2
        ld      de,3
        ld      a,P126_OP_IMAGE_FINISH
        call    p126_bios_send_frame
        jr      c,.fixed_overlay_transport_error

        ld      a,(p126_neogs_overlay_kind)
        cp      P126_IMAGE_KIND_X86IO
        jr      nz,.fixed_overlay_log_not_io_ready
        ld      hl,p126_neogs_io_log_ready
        jr      .fixed_overlay_log_ready
.fixed_overlay_log_not_io_ready:
        cp      P126_IMAGE_KIND_X86ALU
        jr      nz,.fixed_overlay_log_dev_ready
        ld      hl,p126_neogs_alu_log_ready
        jr      .fixed_overlay_log_ready
.fixed_overlay_log_dev_ready:
        cp      P126_IMAGE_KIND_X86DEV
        jr      nz,.fixed_overlay_log_exec_ready
        ld      hl,p126_neogs_dev_log_ready
        jr      .fixed_overlay_log_ready
.fixed_overlay_log_exec_ready:
        cp      P126_IMAGE_KIND_X86VID
        jr      nz,.fixed_overlay_log_vid_ready
        ld      hl,p126_neogs_vid_log_ready
        jr      .fixed_overlay_log_ready
.fixed_overlay_log_vid_ready:
        cp      P126_IMAGE_KIND_X86VGA
        jr      nz,.fixed_overlay_log_vga_ready
        ld      hl,p126_neogs_vga_log_ready
        jr      .fixed_overlay_log_ready
.fixed_overlay_log_vga_ready:
        ld      hl,p126_neogs_exec_log_ready
.fixed_overlay_log_ready:
        call    p126_neogs_log_text
        or      a
        ret

.fixed_overlay_transport_error:
        ld      a,8
        jp      p126_neogs_store_error

p126_neogs_overlay_read_sector:
        ld      a,(p126_neogs_file_sectors_left)
        or      a
        jr      nz,.overlay_sector_available
        scf
        ret
.overlay_sector_available:
        ld      a,(p126_neogs_file_track)
        ld      d,a
        ld      a,(p126_neogs_file_sector)
        ld      e,a
        ld      hl,(p126_neogs_overlay_data_ptr)
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
        jr      nz,.overlay_sector_failed

        ld      a,(p126_neogs_file_sector)
        inc     a
        cp      16
        jr      c,.overlay_sector_same_track
        xor     a
        ld      (p126_neogs_file_sector),a
        ld      a,(p126_neogs_file_track)
        inc     a
        ld      (p126_neogs_file_track),a
        jr      .overlay_sector_advance_done
.overlay_sector_same_track:
        ld      (p126_neogs_file_sector),a
.overlay_sector_advance_done:
        ld      a,(p126_neogs_file_sectors_left)
        dec     a
        ld      (p126_neogs_file_sectors_left),a
        or      a
        ret
.overlay_sector_failed:
        scf
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
        ld      a,(p126_neogs_file_extension)
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

; Send the current ATM video mode to NeoGS after the host has finished
; shadow-port setup. Descriptor v1 is: version, RG mode, width, height,
; pixel/layout format, flags, logical frame size (u16).
p126_neogs_send_video_mode::
        push    bc
        push    de
        push    hl
        ld      hl,#C000+P126_IPC_HEADER_SIZE
        ld      a,P126_VIDEO_DESC_VERSION
        ld      (hl),a
        inc     hl
        ld      a,(p126_atm_video_mode)
        ld      (hl),a
        inc     hl
        ld      a,P126_VIDEO_TEXT80_WIDTH
        ld      (hl),a
        inc     hl
        ld      a,P126_VIDEO_TEXT80_HEIGHT
        ld      (hl),a
        inc     hl
        ld      a,P126_VIDEO_FORMAT_TEXT80X25
        ld      (hl),a
        inc     hl
        xor     a
        ld      (hl),a
        inc     hl
        ld      hl,P126_VIDEO_TEXT80_FRAME_SIZE
        ld      (#C000+P126_IPC_HEADER_SIZE+6),hl
        xor     a
        ld      (p126_bios_frame_flags),a
        ld      a,P126_OP_VIDEO_MODE
        ld      bc,P126_VIDEO_MODE_DESC_SIZE
        ld      de,1
        call    p126_bios_send_video_frame
        pop     hl
        pop     de
        pop     bc
        ret

p126_neogs_boot_name: db "P126BOOT"
p126_neogs_core_name: db "X86CORE "
p126_neogs_io_name:   db "X86IO   "
p126_neogs_alu_name:  db "X86ALU  "
p126_neogs_dev_name:  db "X86DEV  "
p126_neogs_exec_name: db "X86EXEC "
p126_neogs_vga_name:  db "X86VGA  "
p126_neogs_vid_name:  db "X86VID  "
; Descriptor: module ID, IMAGE kind, physical page, max size (u16),
; filename pointer and diagnostic stage character.
p126_neogs_module_table:
        db      1,P126_IMAGE_KIND_X86IO,#04
        dw      P126_IMAGE_X86IO_MAX_SIZE,p126_neogs_io_name
        db      'I'
        db      2,P126_IMAGE_KIND_X86ALU,#05
        dw      P126_IMAGE_X86ALU_MAX_SIZE,p126_neogs_alu_name
        db      'A'
        db      3,P126_IMAGE_KIND_X86DEV,#06
        dw      P126_IMAGE_X86DEV_MAX_SIZE,p126_neogs_dev_name
        db      'D'
        db      4,P126_IMAGE_KIND_X86EXEC,#07
        dw      P126_IMAGE_X86EXEC_MAX_SIZE,p126_neogs_exec_name
        db      'X'
        db      5,P126_IMAGE_KIND_X86VGA,#08
        dw      P126_IMAGE_X86VGA_MAX_SIZE,p126_neogs_vga_name
        db      'V'
        db      6,P126_IMAGE_KIND_X86VID,#09
        dw      P126_IMAGE_X86VID_MAX_SIZE,p126_neogs_vid_name
        db      'C'
p126_neogs_manifest_name: db "X86MODS "
p126_neogs_file_extension: db 'C'
p126_neogs_manifest_valid: db 0
p126_neogs_manifest_module_id: db 0
p126_neogs_manifest_record_index: db 0
p126_neogs_manifest_record_size: dw 0
p126_neogs_manifest_record_ptr: dw 0
p126_neogs_manifest_crc_work: dw 0
p126_neogs_manifest: defs 55,0
p126_neogs_overlay_size: dw 0
p126_neogs_overlay_max_size: dw 0
p126_neogs_overlay_kind: db 0
p126_neogs_overlay_page: db 0
p126_neogs_overlay_data_ptr: dw #C11C
p126_neogs_io_log_begin: db "[NGS HOST] X86IO IMAGE BEGIN",13,10,0
p126_neogs_io_log_ready: db "[NGS HOST] X86IO IMAGE TX COMPLETE",13,10,0
p126_neogs_alu_log_begin: db "[NGS HOST] X86ALU IMAGE BEGIN",13,10,0
p126_neogs_alu_log_ready: db "[NGS HOST] X86ALU IMAGE TX COMPLETE",13,10,0
p126_neogs_dev_log_begin: db "[NGS HOST] X86DEV IMAGE BEGIN",13,10,0
p126_neogs_dev_log_ready: db "[NGS HOST] X86DEV IMAGE TX COMPLETE",13,10,0
p126_neogs_exec_log_begin: db "[NGS HOST] X86EXEC IMAGE BEGIN",13,10,0
p126_neogs_exec_log_ready: db "[NGS HOST] X86EXEC IMAGE TX COMPLETE",13,10,0
p126_neogs_vga_log_begin: db "[NGS HOST] X86VGA IMAGE BEGIN",13,10,0
p126_neogs_vga_log_ready: db "[NGS HOST] X86VGA IMAGE TX COMPLETE",13,10,0
p126_neogs_vid_log_begin: db "[NGS HOST] X86VID IMAGE BEGIN",13,10,0
p126_neogs_vid_log_ready: db "[NGS HOST] X86VID IMAGE TX COMPLETE",13,10,0
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
