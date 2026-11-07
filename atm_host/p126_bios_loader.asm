; =========================================================================
; PROJECT126 — selected SYSBIOS loader
;
; Selection is made in the ATM catalogue. TR-DOS access is restored using
; the same pre-video mapping as initial startup; the chosen 8 KiB .C file is
; staged in page 0, then sent as ABI 1.0 IMAGE BEGIN/FRAGMENT/FINISH frames.
; NeoGS installs the fragment into physical SYSBIOS page 10h.
; =========================================================================

P126_BIOS_FILE_SIZE       EQU #2000
P126_BIOS_SECTOR_COUNT    EQU 32
P126_BIOS_SECTOR_SIZE     EQU #0100
P126_BIOS_FRAME           EQU #C000
P126_BIOS_FRAGMENT_DATA   EQU #C01C

; Called by the catalogue after Enter has been pressed and released.
; OUT: carry clear after NeoGS has acknowledged all three IMAGE operations.
p126_bios_load_selected::
        ; Match the Project125 BIOS loader entry contract explicitly.
        di
        ld      (p126_bios_saved_sp),sp
        ld      sp,#BFFF
        ld      hl,p126_bios_log_load_begin
        call    p126_catalog_log
        xor     a
        ld      (p126_bios_error),a
        ld      (p126_bios_disk_mode_active),a

        ; Resolve the selected visible catalogue index to its TR-DOS entry.
        ld      a,(p126_catalog_selected)
        call    p126_catalog_find_index
        jp      c,p126_bios_bad_selection
        ; Preserve the selected directory-entry pointer across logging.
        ; p126_catalog_log uses HL for its message pointer.
        push    hl
        ld      hl,p126_bios_log_selection_resolved
        call    p126_catalog_log
        pop     hl
        push    hl
        ld      de,#5CDD
        ld      bc,8
        ldir
        pop     hl
        ld      de,8
        add     hl,de
        ld      a,(hl)
        cp      'C'
        jp      nz,p126_bios_bad_file_type
        ld      hl,p126_bios_log_file_type_ok
        call    p126_catalog_log
        ; Emit the exact selected 8.3 name into the diagnostic stream.
        call    p126_bios_log_selected_filename

        ; Enter the same legacy mapping used before ATM video initialization.
        ; Disk reads must not run with the alternate ATM window mapping active.
        ld      hl,p126_bios_log_trdos_map_begin
        call    p126_catalog_log
        call    p126_bios_enter_trdos_mode
        ld      hl,p126_bios_log_trdos_map_done
        call    p126_catalog_log
        ld      a,1
        ld      (p126_bios_disk_mode_active),a

        ; Project125 TR-DOS ROM file-open ABI: C=0Ah finds the exact 8.3 name,
        ; C=08h returns the full descriptor in the standard system variables.
        ld      a,'C'
        ld      (#5CE5),a
        ld      a,9
        ld      (#5D06),a
        ld      hl,p126_bios_log_open_call
        call    p126_catalog_log
        ; Capture the exact TR-DOS boundary state before entering the ROM.
        ; This is a read-only diagnostic port of Project125's proven trace.
        call    p126_bios_trace_search_state
        ld      c,10
        call    #3D13
        ld      hl,p126_bios_log_open_return
        call    p126_catalog_log
        ld      a,c
        cp      #FF
        jp      z,p126_bios_file_not_found
        push    af
        xor     a
        ld      (#5D0F),a
        ld      (#5D10),a
        pop     af
        ld      hl,p126_bios_log_descriptor_call
        call    p126_catalog_log
        ld      c,8
        call    #3D13
        ld      hl,p126_bios_log_descriptor_return
        call    p126_catalog_log
        ld      a,(#5D0F)
        ld      b,a
        ld      a,(#5D10)
        or      b
        jp      nz,p126_bios_bad_descriptor
        ld      hl,p126_bios_log_file_open
        call    p126_catalog_log

        ; All selectable BIOS files must be exactly 8192 bytes / 32 sectors.
        ld      hl,(#5CE8)
        ld      de,P126_BIOS_FILE_SIZE
        or      a
        sbc     hl,de
        jp      nz,p126_bios_bad_size
        ld      a,(#5CEA)
        cp      P126_BIOS_SECTOR_COUNT
        jp      nz,p126_bios_bad_size
        ld      (p126_bios_sectors_left),a
        ld      hl,p126_bios_log_size_ok
        call    p126_catalog_log
        ld      hl,p126_bios_log_read_begin
        call    p126_catalog_log
        ld      a,(#5CEB)
        cp      16
        jp      nc,p126_bios_bad_descriptor
        ld      (p126_bios_sector),a
        ld      a,(#5CEC)
        ld      (p126_bios_track),a
        ld      hl,P126_BIOS_FRAGMENT_DATA
        ld      (p126_bios_buffer_ptr),hl

.p126_bios_read_loop:
        ld      a,(p126_bios_sectors_left)
        or      a
        jr      z,.p126_bios_read_done
        call    p126_bios_read_next_sector
        jp      c,p126_bios_sector_error
        jr      .p126_bios_read_loop

.p126_bios_read_done:
        ld      hl,p126_bios_log_read_done
        call    p126_catalog_log
        ; Return to the ATM video mapping before any DMA/IPC transaction.
        call    p126_bios_restore_atm_video
        xor     a
        ld      (p126_bios_disk_mode_active),a
        ld      hl,p126_bios_log_video_restored
        call    p126_catalog_log

        ; IMAGE_BEGIN payload:
        ; message-id=0001h, image-kind=SYSBIOS, reserved=00h, size=2000h.
        ld      a,1
        ld      (P126_BIOS_FRAME+18),a
        xor     a
        ld      (P126_BIOS_FRAME+19),a
        ld      (P126_BIOS_FRAME+20),a
        ld      (P126_BIOS_FRAME+21),a
        ld      (P126_BIOS_FRAME+22),a
        ld      a,#20
        ld      (P126_BIOS_FRAME+23),a
        xor     a
        ld      (p126_bios_frame_flags),a
        ld      hl,p126_bios_log_image_begin_tx
        call    p126_catalog_log
        ld      bc,6
        ld      de,1
        xor     a
        call    p126_bios_send_frame
        jp      c,p126_bios_transport_error
        ld      hl,p126_bios_log_image_begin_ok
        call    p126_catalog_log

        ; IMAGE_FRAGMENT payload begins with the ABI 1.0 ten-byte extension:
        ; message-id=1, index=0, count=1, total logical data length=8192.
        ld      a,1
        ld      (P126_BIOS_FRAME+18),a
        xor     a
        ld      (P126_BIOS_FRAME+19),a
        ld      (P126_BIOS_FRAME+20),a
        ld      (P126_BIOS_FRAME+21),a
        ld      a,1
        ld      (P126_BIOS_FRAME+22),a
        xor     a
        ld      (P126_BIOS_FRAME+23),a
        ld      (P126_BIOS_FRAME+24),a
        ld      a,#20
        ld      (P126_BIOS_FRAME+25),a
        xor     a
        ld      (P126_BIOS_FRAME+26),a
        ld      (P126_BIOS_FRAME+27),a
        ld      a,P126_FLAG_FRAGMENT
        ld      (p126_bios_frame_flags),a
        ld      hl,p126_bios_log_image_fragment_tx
        call    p126_catalog_log
        ld      bc,#200A
        ld      de,2
        ld      a,P126_OP_IMAGE_FRAGMENT
        call    p126_bios_send_frame
        jp      c,p126_bios_transport_error
        ld      hl,p126_bios_log_image_fragment_ok
        call    p126_catalog_log

        ; IMAGE_FINISH payload carries the same message ID.
        ld      a,1
        ld      (P126_BIOS_FRAME+18),a
        xor     a
        ld      (P126_BIOS_FRAME+19),a
        xor     a
        ld      (p126_bios_frame_flags),a
        ld      hl,p126_bios_log_image_finish_tx
        call    p126_catalog_log
        ld      bc,2
        ld      de,3
        ld      a,P126_OP_IMAGE_FINISH
        call    p126_bios_send_frame
        jp      c,p126_bios_transport_error
        ld      hl,p126_bios_log_image_finish_ok
        call    p126_catalog_log

        xor     a
        ld      (p126_bios_error),a
        ld      hl,(p126_bios_saved_sp)
        ld      sp,hl
        or      a
        ret



; Read-only snapshot immediately before TR-DOS C=#0A.
; Dumps BANKM, extension, file-name length, live SP, ROM signature at #3D13,
; and the exact eight-byte name. Preserves all Z80 registers.
p126_bios_trace_search_state:
        push    af
        push    bc
        push    de
        push    hl
        call    p126_host_log_prefix
        ld      bc,#00EF
        ld      hl,p126_bios_trace_state_prefix
.p126_bios_trace_state_text:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,.p126_bios_trace_state_values
        out     (c),a
        jr      .p126_bios_trace_state_text
.p126_bios_trace_state_values:
        ld      a,(#5C3B)
        call    p126_host_debug_hex_byte
        ld      a,' '
        out     (c),a
        ld      a,(#5CE5)
        call    p126_host_debug_hex_byte
        ld      a,' '
        out     (c),a
        ld      a,(#5D06)
        call    p126_host_debug_hex_byte
        ld      a,' '
        out     (c),a
        ld      hl,0
        add     hl,sp
        ld      a,h
        call    p126_host_debug_hex_byte
        ld      a,l
        call    p126_host_debug_hex_byte
        ld      a,' '
        out     (c),a
        ld      hl,#3D13
        ld      b,8
.p126_bios_trace_rom_loop:
        ld      a,(hl)
        call    p126_host_debug_hex_byte
        inc     hl
        ld      a,' '
        out     (c),a
        djnz    .p126_bios_trace_rom_loop
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a

        call    p126_host_log_prefix
        ld      bc,#00EF
        ld      hl,p126_bios_trace_name_prefix
.p126_bios_trace_name_text:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,.p126_bios_trace_name_value
        out     (c),a
        jr      .p126_bios_trace_name_text
.p126_bios_trace_name_value:
        ld      hl,#5CDD
        ld      b,8
.p126_bios_trace_name_loop:
        ld      a,(hl)
        inc     hl
        out     (c),a
        djnz    .p126_bios_trace_name_loop
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Log the selected TR-DOS 8.3 filename as one timestamped line.
; The directory name is already copied to #5CDD and type C was validated.
p126_bios_log_selected_filename:
        push    af
        push    bc
        push    de
        push    hl
        call    p126_host_log_prefix
        ld      bc,#00EF
        ld      hl,p126_bios_log_filename_prefix
.p126_bios_log_filename_prefix_loop:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,.p126_bios_log_filename_name
        out     (c),a
        jr      .p126_bios_log_filename_prefix_loop
.p126_bios_log_filename_name:
        ld      hl,#5CDD
        ld      b,8
.p126_bios_log_filename_name_loop:
        ld      a,(hl)
        inc     hl
        out     (c),a
        djnz    .p126_bios_log_filename_name_loop
        ld      a,'.'
        out     (c),a
        ld      a,'C'
        out     (c),a
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Build and send one ABI 1.0 IMAGE request.
; IN: A=operation, BC=payload length, DE=sequence, flags in variable.
p126_bios_send_frame:
        ld      (p126_bios_operation),a
        ld      (p126_bios_payload_length),bc
        ld      (p126_bios_sequence),de
        ld      hl,P126_BIOS_FRAME
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
        ld      a,P126_SERVICE_IMAGE
        ld      (hl),a
        inc     hl
        ld      a,(p126_bios_operation)
        ld      (hl),a
        inc     hl
        ld      a,(p126_bios_frame_flags)
        ld      (hl),a
        inc     hl
        ld      hl,(p126_bios_sequence)
        ld      (P126_BIOS_FRAME+10),hl
        ld      hl,(p126_bios_payload_length)
        ld      (P126_BIOS_FRAME+12),hl
        xor     a
        ld      (P126_BIOS_FRAME+14),a
        ld      (P126_BIOS_FRAME+15),a

        ; CRC-16/CCITT-FALSE over header[0..15] and the complete payload.
        ld      hl,#FFFF
        ld      de,P126_BIOS_FRAME
        ld      b,16
.p126_bios_crc_header:
        ld      a,(de)
        inc     de
        call    p126_ipc_crc16_update
        djnz    .p126_bios_crc_header
        ld      bc,(p126_bios_payload_length)
.p126_bios_crc_payload:
        ld      a,b
        or      c
        jr      z,.p126_bios_crc_done
        ld      a,(de)
        inc     de
        call    p126_ipc_crc16_update
        dec     bc
        jr      .p126_bios_crc_payload
.p126_bios_crc_done:
        ld      (P126_BIOS_FRAME+16),hl
        ld      hl,P126_BIOS_FRAME
        ld      bc,(p126_bios_payload_length)
        ld      de,P126_IPC_HEADER_SIZE
        add     hl,de
        ld      b,h
        ld      c,l
        ld      hl,P126_BIOS_FRAME
        jp      p126_ipc_dma_send_frame

; Read one sector using the proven Project125 TR-DOS C=5/B=1 ABI.
; Cursor advances only after the ROM call reports success.
p126_bios_read_next_sector:
        ld      a,(p126_bios_track)
        ld      d,a
        ld      a,(p126_bios_sector)
        ld      e,a
        ld      hl,(p126_bios_buffer_ptr)
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
        jr      nz,.p126_bios_read_failed

        ld      hl,(p126_bios_buffer_ptr)
        ld      de,P126_BIOS_SECTOR_SIZE
        add     hl,de
        ld      (p126_bios_buffer_ptr),hl
        ld      a,(p126_bios_sector)
        inc     a
        cp      16
        jr      c,.p126_bios_same_track
        xor     a
        ld      (p126_bios_sector),a
        ld      a,(p126_bios_track)
        inc     a
        ld      (p126_bios_track),a
        jr      .p126_bios_cursor_done
.p126_bios_same_track:
        ld      (p126_bios_sector),a
.p126_bios_cursor_done:
        ld      a,(p126_bios_sectors_left)
        dec     a
        ld      (p126_bios_sectors_left),a
        or      a
        ret
.p126_bios_read_failed:
        scf
        ret

; Restore the exact pre-video TR-DOS mapping used by initial startup.
p126_bios_enter_trdos_mode:
        ; ATM video initialization has already enabled permanent DOSEN
        ; through the #3D2F trampoline and selected auto-TR-DOS ROM mapping
        ; with #3FF7=#BF. Preserve that state while enabling ROM2 for the
        ; Project125-compatible TR-DOS calls.
        ;
        ; IMPORTANT: keep BANKM D3 unchanged. D3 selects the alternate
        ; video pages used by the active ATM high-resolution display. Writing
        ; #10 here would silently switch back to the standard screen pages
        ; while the console continues using pages 7/3.
        ; Do not reset #EFF7 or repeat the #0177 trampoline: either can undo
        ; the DOSEN state established by p126_atm_video_init.
        ld      a,(#5C3B)
        or      #10
        ld      bc,#7FFD
        out     (c),a
        ld      (#5C3B),a

        ; Reassert the WIN0 automatic TR-DOS selector without changing the
        ; current video-page selection or permanent DOSEN state.
        ld      a,#BF
        ld      bc,#3FF7
        out     (c),a
        ret

; Rebuild the ATM 80x25 display mapping after TR-DOS I/O is complete.
p126_bios_restore_atm_video:
        call    p126_atm_video_init
        ret

p126_bios_bad_selection:
        ld      a,1
        jp      p126_bios_fail
p126_bios_bad_file_type:
        ld      a,2
        jp      p126_bios_fail
p126_bios_file_not_found:
        ld      a,3
        jp      p126_bios_fail
p126_bios_bad_descriptor:
        ld      a,4
        jp      p126_bios_fail
p126_bios_bad_size:
        ld      a,5
        jp      p126_bios_fail
p126_bios_sector_error:
        ld      a,6
        jp      p126_bios_fail
p126_bios_transport_error:
        ld      a,7
p126_bios_fail:
        ld      (p126_bios_error),a
        ld      a,(p126_bios_disk_mode_active)
        or      a
        jr      z,.p126_bios_fail_restore_stack
        call    p126_bios_restore_atm_video
        xor     a
        ld      (p126_bios_disk_mode_active),a
.p126_bios_fail_restore_stack:
        ld      hl,(p126_bios_saved_sp)
        ld      sp,hl
        ld      a,(p126_bios_error)
        cp      1
        ld      hl,p126_bios_log_bad_selection
        jr      z,.p126_bios_log_failure
        cp      2
        ld      hl,p126_bios_log_bad_type
        jr      z,.p126_bios_log_failure
        cp      3
        ld      hl,p126_bios_log_not_found
        jr      z,.p126_bios_log_failure
        cp      4
        ld      hl,p126_bios_log_bad_descriptor
        jr      z,.p126_bios_log_failure
        cp      5
        ld      hl,p126_bios_log_bad_size
        jr      z,.p126_bios_log_failure
        cp      6
        ld      hl,p126_bios_log_sector_error
        jr      z,.p126_bios_log_failure
        ld      hl,p126_bios_log_transport_error
.p126_bios_log_failure:
        call    p126_catalog_log
        ld      a,(p126_bios_error)
        scf
        ret

p126_bios_saved_sp:        dw 0
p126_bios_buffer_ptr:      dw P126_BIOS_FRAGMENT_DATA
p126_bios_sectors_left:    db 0
p126_bios_track:           db 0
p126_bios_sector:          db 0
p126_bios_error:           db 0
p126_bios_disk_mode_active: db 0
p126_bios_operation:       db 0
p126_bios_frame_flags:     db 0
p126_bios_payload_length:  dw 0
p126_bios_sequence:        dw 0

; ATM-side progress markers for the selected BIOS load transaction.
p126_bios_log_load_begin:       db "[CAT] BIOS LOAD BEGIN",13,10,0
p126_bios_log_selection_resolved: db "[CAT] BIOS SELECTION RESOLVED",13,10,0
p126_bios_log_filename_prefix:   db "[CAT] BIOS FILE SELECTED: ",0
p126_bios_trace_state_prefix:   db "[CAT] TRDOS C=0A STATE BANKM/EXT/LEN/SP/ROM=",0
p126_bios_trace_name_prefix:    db "[CAT] TRDOS C=0A NAME=",0
p126_bios_log_file_type_ok:      db "[CAT] BIOS FILE TYPE C OK",13,10,0
p126_bios_log_trdos_map_begin:   db "[CAT] TRDOS MAP SWITCH BEGIN",13,10,0
p126_bios_log_trdos_map_done:    db "[CAT] TRDOS MAP SWITCH DONE",13,10,0
p126_bios_log_open_call:         db "[CAT] TRDOS OPEN C=0A CALL",13,10,0
p126_bios_log_open_return:       db "[CAT] TRDOS OPEN C=0A RETURN",13,10,0
p126_bios_log_descriptor_call:   db "[CAT] TRDOS DESCRIPTOR C=08 CALL",13,10,0
p126_bios_log_descriptor_return: db "[CAT] TRDOS DESCRIPTOR C=08 RETURN",13,10,0
p126_bios_log_file_open:        db "[CAT] BIOS FILE OPEN OK",13,10,0
p126_bios_log_size_ok:          db "[CAT] BIOS FILE SIZE OK",13,10,0
p126_bios_log_read_begin:       db "[CAT] BIOS READ BEGIN",13,10,0
p126_bios_log_read_done:        db "[CAT] BIOS READ COMPLETE",13,10,0
p126_bios_log_video_restored:   db "[CAT] BIOS ATM VIDEO RESTORED",13,10,0
p126_bios_log_image_begin_tx:   db "[CAT] IMAGE BEGIN TX",13,10,0
p126_bios_log_image_begin_ok:   db "[CAT] IMAGE BEGIN HANDLER COMPLETE",13,10,0
p126_bios_log_image_fragment_tx: db "[CAT] IMAGE FRAGMENT TX",13,10,0
p126_bios_log_image_fragment_ok: db "[CAT] IMAGE FRAGMENT HANDLER COMPLETE",13,10,0
p126_bios_log_image_finish_tx:  db "[CAT] IMAGE FINISH TX",13,10,0
p126_bios_log_image_finish_ok:  db "[CAT] IMAGE FINISH HANDLER COMPLETE",13,10,0
p126_bios_log_bad_selection:    db "[CAT] BIOS ERROR: BAD SELECTION",13,10,0
p126_bios_log_bad_type:         db "[CAT] BIOS ERROR: FILE TYPE",13,10,0
p126_bios_log_not_found:        db "[CAT] BIOS ERROR: FILE NOT FOUND",13,10,0
p126_bios_log_bad_descriptor:   db "[CAT] BIOS ERROR: DESCRIPTOR",13,10,0
p126_bios_log_bad_size:         db "[CAT] BIOS ERROR: SIZE/SECTORS",13,10,0
p126_bios_log_sector_error:     db "[CAT] BIOS ERROR: SECTOR READ",13,10,0
p126_bios_log_transport_error:  db "[CAT] BIOS ERROR: IPC/DMA",13,10,0

