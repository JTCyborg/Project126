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
        ld      (p126_bios_saved_sp),sp
        ld      sp,#BFFF
        xor     a
        ld      (p126_bios_error),a
        ld      (p126_bios_disk_mode_active),a

        ; Resolve the selected visible catalogue index to its TR-DOS entry.
        ld      a,(p126_catalog_selected)
        call    p126_catalog_find_index
        jp      c,p126_bios_bad_selection
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

        ; Enter the same legacy mapping used before ATM video initialization.
        ; Disk reads must not run with the alternate ATM window mapping active.
        call    p126_bios_enter_trdos_mode
        ld      a,1
        ld      (p126_bios_disk_mode_active),a

        ; Project125 TR-DOS ROM file-open ABI: C=0Ah finds the exact 8.3 name,
        ; C=08h returns the full descriptor in the standard system variables.
        ld      a,'C'
        ld      (#5CE5),a
        ld      a,9
        ld      (#5D06),a
        ld      c,10
        call    #3D13
        ld      a,c
        cp      #FF
        jp      z,p126_bios_file_not_found
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
        jp      nz,p126_bios_bad_descriptor

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
        ; Return to the ATM video mapping before any DMA/IPC transaction.
        call    p126_bios_restore_atm_video
        xor     a
        ld      (p126_bios_disk_mode_active),a

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
        ld      bc,6
        ld      de,1
        xor     a
        call    p126_bios_send_frame
        jp      c,p126_bios_transport_error

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
        ld      bc,#200A
        ld      de,2
        ld      a,P126_OP_IMAGE_FRAGMENT
        call    p126_bios_send_frame
        jp      c,p126_bios_transport_error

        ; IMAGE_FINISH payload carries the same message ID.
        ld      a,1
        ld      (P126_BIOS_FRAME+18),a
        xor     a
        ld      (P126_BIOS_FRAME+19),a
        xor     a
        ld      (p126_bios_frame_flags),a
        ld      bc,2
        ld      de,3
        ld      a,P126_OP_IMAGE_FINISH
        call    p126_bios_send_frame
        jp      c,p126_bios_transport_error

        xor     a
        ld      (p126_bios_error),a
        ld      hl,(p126_bios_saved_sp)
        ld      sp,hl
        or      a
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
        xor     a
        ld      bc,#EFF7
        out     (c),a
        ld      a,#10
        ld      bc,#7FFD
        out     (c),a
        ld      (#5C3B),a
        xor     a
        ld      bc,#EFF7
        out     (c),a
        ret

; Rebuild the ATM 80x25 display mapping after TR-DOS I/O is complete.
p126_bios_restore_atm_video:
        call    p126_atm_video_init
        ret

p126_bios_bad_selection:
        ld      a,1
        jr      p126_bios_fail
p126_bios_bad_file_type:
        ld      a,2
        jr      p126_bios_fail
p126_bios_file_not_found:
        ld      a,3
        jr      p126_bios_fail
p126_bios_bad_descriptor:
        ld      a,4
        jr      p126_bios_fail
p126_bios_bad_size:
        ld      a,5
        jr      p126_bios_fail
p126_bios_sector_error:
        ld      a,6
        jr      p126_bios_fail
p126_bios_transport_error:
        ld      a,7
.p126_bios_fail:
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

