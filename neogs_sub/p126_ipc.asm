; =========================================================================
; PROJECT126 — NeoGS-side CRC primitive for unified DMA/IPC ABI 1.0
; This module implements the ABI 1.0 frame codec and the NeoGS DMA receive endpoint.
; =========================================================================

        INCLUDE "shared/p126_ipc_protocol.inc"

; CRC-16/CCITT-FALSE byte update.
; IN : HL=current CRC, A=next byte.
; OUT: HL=updated CRC. BC preserved.
p126_ngs_ipc_crc16_update::
        push    bc
        xor     h
        ld      h, a
        ld      b, 8
.p126_ngs_crc_bit:
        add     hl, hl
        jr      nc, .p126_ngs_crc_no_xor
        ld      a, h
        xor     #10
        ld      h, a
        ld      a, l
        xor     #21
        ld      l, a
.p126_ngs_crc_no_xor:
        djnz    .p126_ngs_crc_bit
        pop     bc
        ret


; Validate ABI 1.0 complete frame.
; IN: HL=frame pointer, BC=actual size. OUT: carry clear/A=0 or carry set/A=status.
; Clobbers AF,BC,DE,HL,IX. Scratch is non-reentrant.
p126_ngs_ipc_validate_frame::
        ld      (p126_ngs_ipc_frame_ptr),hl
        ld      (p126_ngs_ipc_frame_size),bc
        ld      a,b
        or      a
        jr      nz,.p126_ngs_frame_min_ok
        ld      a,c
        cp      P126_IPC_HEADER_SIZE
        jp      c,.p126_ngs_frame_bad
.p126_ngs_frame_min_ok:
        push    hl
        pop     ix
        ld      a,(ix+0)
        cp      'P'
        jp      nz,.p126_ngs_frame_magic
        ld      a,(ix+1)
        cp      '1'
        jp      nz,.p126_ngs_frame_magic
        ld      a,(ix+2)
        cp      '2'
        jp      nz,.p126_ngs_frame_magic
        ld      a,(ix+3)
        cp      '6'
        jp      nz,.p126_ngs_frame_magic
        ld      a,(ix+4)
        cp      P126_IPC_MAJOR
        jp      nz,.p126_ngs_frame_version
        ld      a,(ix+5)
        cp      P126_IPC_MINOR
        jp      nz,.p126_ngs_frame_version
        ld      a,(ix+6)
        cp      P126_MSG_REQUEST
        jr      z,.p126_ngs_frame_type
        cp      P126_MSG_RESPONSE
        jr      z,.p126_ngs_frame_type
        cp      P126_MSG_EVENT
        jr      z,.p126_ngs_frame_type
        cp      P126_MSG_CANCEL
        jp      nz,.p126_ngs_frame_bad
.p126_ngs_frame_type:
        ld      a,(ix+9)
        and     #F8
        jp      nz,.p126_ngs_frame_bad
        ld      l,(ix+12)
        ld      h,(ix+13)
        ld      de,P126_IPC_HEADER_SIZE
        add     hl,de
        ld      de,(p126_ngs_ipc_frame_size)
        or      a
        sbc     hl,de
        jp      nz,.p126_ngs_frame_bad
        ; CRC header and payload in one pass.
        ; Keep DE as the frame pointer while HL is the CRC accumulator.
        push    ix
        pop     de
        ld      hl,#FFFF
        ld      b,16
.p126_ngs_frame_crc_head:
        ld      a,(de)
        inc     de
        call    p126_ngs_ipc_crc16_update
        djnz    .p126_ngs_frame_crc_head
        ; DE currently points at frame+16; skip the two stored CRC bytes.
        inc     de
        inc     de
        push    de
        ld      ix,(p126_ngs_ipc_frame_ptr)
        ld      e,(ix+12)
        ld      d,(ix+13)
        ; Restore the payload pointer into IX, preserving the live CRC in HL.
        pop     ix
.p126_ngs_frame_crc_data:
        ld      a,d
        or      e
        jr      z,.p126_ngs_frame_crc_compare
        ld      a,(ix+0)
        inc     ix
        call    p126_ngs_ipc_crc16_update
        dec     de
        jr      .p126_ngs_frame_crc_data
.p126_ngs_frame_crc_compare:
        ld      (p126_ngs_ipc_crc_work),hl
        ld      ix,(p126_ngs_ipc_frame_ptr)
        ld      a,(ix+16)
        ld      e,a
        ld      a,(ix+17)
        ld      d,a
        ld      hl,(p126_ngs_ipc_crc_work)
        or      a
        sbc     hl,de
        jp      nz,.p126_ngs_frame_crc_bad
        xor     a
        ret
.p126_ngs_frame_magic:
        ld      a,P126_STATUS_BAD_MAGIC
        scf
        ret
.p126_ngs_frame_version:
        ld      a,P126_STATUS_BAD_VERSION
        scf
        ret
.p126_ngs_frame_crc_bad:
        ld      a,P126_STATUS_CRC_ERROR
        scf
        ret
.p126_ngs_frame_bad:
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret
p126_ngs_ipc_frame_ptr: dw 0
p126_ngs_ipc_frame_size: dw 0
p126_ngs_ipc_crc_work: dw 0


; -------------------------------------------------------------------------
; Receive one ATM -> NeoGS ABI 1.0 frame through ZX DMA.
; Entry: resident dispatcher consumed E0h from ZXCMD; CBIT remains asserted.
; Resident code, stack and interrupt handlers must stay in WIN0-WIN2.
; OUT: carry clear/A=0, HL=#C000 and BC=derived frame size; otherwise
; carry set/A=status. Production DMA destination is physical 108000h on
; page 42h, mapped into WIN3 through MPAGEX (#10) using Project125 selector encoding.
; -------------------------------------------------------------------------
P126_NGS_DMA_MOD      EQU #1B
P126_NGS_DMA_HAD      EQU #1C
P126_NGS_DMA_MAD      EQU #1D
P126_NGS_DMA_LAD      EQU #1E
P126_NGS_DMA_CST      EQU #1F
P126_NGS_ZXSTAT       EQU #04
P126_NGS_CLRCBIT      EQU #05
P126_NGS_MPAGEX_PORT  EQU #10
; Production DMA staging allocation: physical page 42h = 108000h.
; WIN3 (C000h-FFFFh) is the dedicated bank window; resident code/data/stack
; remain outside WIN3. Map the page before arming DMA and keep it mapped
; until frame validation or reverse-transfer completion.
P126_NGS_DMA_PROD_PAGE EQU #42
P126_NGS_DMA_WAIT_LIMIT EQU #FFFF
P126_NGS_DMA_WAIT_OUTER EQU 8

p126_ngs_ipc_dma_receive_frame::
        ; Production page-42 validation. WIN3 is selected through MPAGEX (#10),
        ; exactly as in Project125. MPAGEX expects the physical page number
        ; rotated right once (RRCA); PG3 (#23) is not the WIN3 selector.
        ; Resident stack/code remain in WIN0-WIN2.
        ld      a,P126_NGS_DMA_PROD_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      hl,p126_ngs_ipc_log_dma_page42_premapped
        call    p126_ngs_ipc_log
        ld      hl,p126_ngs_ipc_log_dma_cfg_begin
        call    p126_ngs_ipc_log

        ; Physical page 42h base = 108000h: HAD=10h, MAD=80h, LAD=00h.
        ld      a,1
        out     (P126_NGS_DMA_MOD),a
        ld      a,#10
        out     (P126_NGS_DMA_HAD),a
        ld      a,#80
        out     (P126_NGS_DMA_MAD),a
        xor     a
        out     (P126_NGS_DMA_LAD),a
        ld      a,#80
        out     (P126_NGS_DMA_CST),a
        ld      hl,p126_ngs_ipc_log_dma_armed
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      hl,p126_ngs_ipc_log_dma_ready
        call    p126_ngs_ipc_log

        ; Match Project125's proven DMA completion watchdog: eight full
        ; 16-bit polling windows. A single #FFFF window expires before the
        ; ATM can finish a 16 KiB LDIR at its host clock.
        ld      d,P126_NGS_DMA_WAIT_OUTER
.p126_ngs_dma_wait_outer:
        ld      bc,P126_NGS_DMA_WAIT_LIMIT
.p126_ngs_dma_wait_end:
        in      a,(P126_NGS_ZXSTAT)
        bit     0,a
        jr      nz,.p126_ngs_dma_host_end
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_ngs_dma_wait_end
        dec     d
        jr      nz,.p126_ngs_dma_wait_outer
        ld      hl,p126_ngs_ipc_log_dma_timeout
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_DMA_CST),a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_TIMEOUT
        scf
        ret

.p126_ngs_dma_host_end:
        ld      hl,p126_ngs_ipc_log_dma_host_end
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_DMA_CST),a
        ld      hl,p126_ngs_ipc_log_dma_stopped
        call    p126_ngs_ipc_log

        ; A maximum 16 KiB frame must advance 108000h to 10C000h.
        ld      hl,p126_ngs_ipc_log_dma_addr
        call    p126_ngs_ipc_log
        in      a,(P126_NGS_DMA_HAD)
        ld      (p126_ngs_ipc_dma_end_had),a
        call    p126_ngs_ipc_log_hex_byte_inline
        in      a,(P126_NGS_DMA_MAD)
        ld      (p126_ngs_ipc_dma_end_mad),a
        call    p126_ngs_ipc_log_hex_byte_inline
        in      a,(P126_NGS_DMA_LAD)
        ld      (p126_ngs_ipc_dma_end_lad),a
        call    p126_ngs_ipc_log_hex_byte_inline
        call    p126_ngs_ipc_log_crlf
        ; WIN3 remains mapped to physical page 42h; CPU view is C000h.
        ld      hl,p126_ngs_ipc_log_dma_page42_mapped
        call    p126_ngs_ipc_log
        ld      hl,p126_ngs_ipc_log_dma_end
        call    p126_ngs_ipc_log

        ld      hl,p126_ngs_ipc_log_rx_header
        call    p126_ngs_ipc_log
        ld      ix,#C000
        ld      b,16
.p126_ngs_rx_dump_loop:
        ld      a,(ix+0)
        call    p126_ngs_ipc_log_hex_byte_inline
        inc     ix
        djnz    .p126_ngs_rx_dump_loop
        call    p126_ngs_ipc_log_crlf

        ; Frame size must fit wholly in the 16 KiB production staging page.
        ld      a,(#C00C)
        ld      e,a
        ld      a,(#C00D)
        ld      d,a
        ld      hl,P126_IPC_HEADER_SIZE
        add     hl,de
        ld      a,h
        cp      #40
        jr      c,.p126_ngs_dma_size_ok
        jp      nz,.p126_ngs_dma_bad_length
        ld      a,l
        or      a
        jr      z,.p126_ngs_dma_size_ok
        jp      .p126_ngs_dma_bad_length
.p126_ngs_dma_size_ok:
        ld      (p126_ngs_ipc_rx_size),hl
        ; Compare DMA counter with base + the declared frame size. This
        ; validates exact byte count for every legal frame length; for the
        ; 16 KiB test the expected end address is 10C000h.
        ld      hl,(p126_ngs_ipc_rx_size)
        ld      de,#8000
        add     hl,de
        ld      a,(p126_ngs_ipc_dma_end_had)
        cp      #10
        jp      nz,.p126_ngs_dma_bad_length
        ld      a,(p126_ngs_ipc_dma_end_mad)
        cp      h
        jp      nz,.p126_ngs_dma_bad_length
        ld      a,(p126_ngs_ipc_dma_end_lad)
        cp      l
        jp      nz,.p126_ngs_dma_bad_length
        ld      bc,(p126_ngs_ipc_rx_size)
        ld      hl,#C000
        call    p126_ngs_ipc_validate_frame
        jr      c,.p126_ngs_dma_validation_failed
        ld      hl,p126_ngs_ipc_log_frame_valid
        call    p126_ngs_ipc_log

        ; Keep CBIT asserted until the service handler has consumed the
        ; validated frame. The host's FF wait therefore covers the complete
        ; service operation, not merely the DMA copy.
        ld      hl,#C000
        ld      bc,(p126_ngs_ipc_rx_size)
        xor     a
        ret

.p126_ngs_dma_validation_failed:
        push    af
        ld      hl,p126_ngs_ipc_log_frame_rejected
        call    p126_ngs_ipc_log
        pop     af
        call    p126_ngs_ipc_log_hex_byte
        push    af
        xor     a
        out     (P126_NGS_CLRCBIT),a
        pop     af
        scf
        ret

.p126_ngs_dma_bad_length:
        ld      hl,p126_ngs_ipc_log_bad_length
        call    p126_ngs_ipc_log
        ld      a,P126_STATUS_BAD_FRAME
        scf
        push    af
        xor     a
        out     (P126_NGS_CLRCBIT),a
        pop     af
        scf
        ret

p126_ngs_ipc_rx_size: dw 0
p126_ngs_ipc_dma_end_had: db 0
p126_ngs_ipc_dma_end_mad: db 0
p126_ngs_ipc_dma_end_lad: db 0
; -------------------------------------------------------------------------
; Resident command-dispatch entry, one bounded unit of work.
; OUT: carry clear/Z=1/A=0 when no command is pending;
;      carry clear/Z=0 with HL=#C000, BC=size on a valid E0h frame;
;      carry set/A=status for a rejected command or receive failure.
; The caller owns the resident main loop and must keep its stack/code outside
; WIN1. E0h is consumed from ZXCMD while CBIT stays asserted until DMA is armed.
; -------------------------------------------------------------------------
P126_NGS_ZXCMD       EQU #01

; Reverse DMA maximum-frame response for ABI command E1h (NGS_FRAME).
; Source is the complete 16 KiB physical page 42h at 108000h.
p126_ngs_ipc_dma_send_test_frame::
        ; Build the deterministic reverse diagnostics frame directly in page
        ; 42h through WIN3, then DMA-read it from physical address 108000h.
        ; Match Project125 WIN3 selection: MPAGEX (#10), page encoded by RRCA.
        ld      a,P126_NGS_DMA_PROD_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      hl,p126_ngs_ipc_dma_test_header
        ld      de,#C000
        ld      bc,P126_IPC_HEADER_SIZE
        ldir
        ld      hl,#C000+P126_IPC_HEADER_SIZE
        ld      bc,P126_IPC_MAX_PAYLOAD
.ngs_fill:
        xor     a
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.ngs_fill

        ; Payload[0] = stop reason, [1..2] = CS, [3..4] = IP.
        ; The remainder is zero-filled; the complete fixed-size DMA frame
        ; remains protected by the shared ABI CRC.
        ld      a,(x86_bios_trace_event_status)
        ld      (#C012),a
        ld      hl,(x86_bios_trace_event_cs)
        ld      (#C013),hl
        ld      hl,(x86_bios_trace_event_ip)
        ld      (#C015),hl

        jp      p126_ngs_ipc_dma_send_staged_frame

; Error response for a missing mode descriptor, unsupported VGA mode or
; unavailable converter. It still sends a complete fixed-size frame so the
; host-side reverse-DMA reader always completes deterministically.
p126_ngs_ipc_dma_send_video_error_frame:
        ld      a,P126_NGS_DMA_PROD_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      hl,p126_ngs_ipc_video_error_header
        ld      de,#C000
        ld      bc,P126_IPC_HEADER_SIZE
        ldir
        ld      hl,(p126_ngs_video_frame_sequence)
        inc     hl
        ld      (p126_ngs_video_frame_sequence),hl
        ld      (#C00A),hl
        ld      hl,#C012
        ld      bc,P126_IPC_MAX_PAYLOAD
.video_error_pad:
        xor     a
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.video_error_pad
        ; Payload byte 0 carries the exact VIDEO failure reason:
        ; E0=overlay, E1=descriptor, F1=mode, F2=VGA state, F3=converter.
        ld      a,(p126_ngs_video_error_code)
        ld      (#C012),a
        jp      p126_ngs_ipc_dma_send_staged_frame

; The converter has already written 4000 bytes at page42h:C012h. Complete
; the fixed-size DMA frame with a VIDEO response header and zero padding.
p126_ngs_ipc_dma_send_video_frame:
        ld      a,P126_NGS_DMA_PROD_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      hl,p126_ngs_ipc_video_header
        ld      de,#C000
        ld      bc,P126_IPC_HEADER_SIZE
        ldir
        ld      hl,(p126_ngs_video_frame_sequence)
        inc     hl
        ld      (p126_ngs_video_frame_sequence),hl
        ld      (#C00A),hl
        ld      hl,#C012+P126_VIDEO_TEXT80_FRAME_SIZE
        ld      bc,P126_IPC_MAX_PAYLOAD-P126_VIDEO_TEXT80_FRAME_SIZE
.video_frame_pad:
        xor     a
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.video_frame_pad
        jp      p126_ngs_ipc_dma_send_staged_frame

; Shared CRC and reverse-DMA transport for the diagnostics and VIDEO frames.
p126_ngs_ipc_dma_send_staged_frame:
        ; CRC covers header[0..15] followed by all 16366 payload bytes.
        ld      hl,#FFFF
        ld      de,#C000
        ld      b,16
.ngs_crc_header:
        ld      a,(de)
        inc     de
        call    p126_ngs_ipc_crc16_update
        djnz    .ngs_crc_header
        inc     de
        inc     de
        ld      bc,P126_IPC_MAX_PAYLOAD
.ngs_crc_payload:
        ld      a,(de)
        inc     de
        call    p126_ngs_ipc_crc16_update
        dec     bc
        ld      a,b
        or      c
        jr      nz,.ngs_crc_payload
        ld      (#C000+P126_IPC_OFF_CRC),hl

        ; Physical source page 42h base = 108000h.
        ld      a,1
        out     (P126_NGS_DMA_MOD),a
        ld      a,#10
        out     (P126_NGS_DMA_HAD),a
        ld      a,#80
        out     (P126_NGS_DMA_MAD),a
        xor     a
        out     (P126_NGS_DMA_LAD),a
        ld      a,#80
        out     (P126_NGS_DMA_CST),a
        ld      hl,p126_ngs_ipc_log_dma_rx_armed
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ; Same Project125 eight-window timeout as the receive endpoint.
        ld      d,P126_NGS_DMA_WAIT_OUTER
.ngs_wait_outer:
        ld      bc,P126_NGS_DMA_WAIT_LIMIT
.ngs_wait_end:
        in      a,(P126_NGS_ZXSTAT)
        bit     0,a
        jr      nz,.ngs_host_end
        dec     bc
        ld      a,b
        or      c
        jr      nz,.ngs_wait_end
        dec     d
        jr      nz,.ngs_wait_outer
        xor     a
        out     (P126_NGS_DMA_CST),a
        out     (P126_NGS_CLRCBIT),a
        ld      hl,p126_ngs_ipc_log_dma_rx_timeout
        call    p126_ngs_ipc_log
        ld      a,P126_STATUS_TIMEOUT
        scf
        ret
.ngs_host_end:
        xor     a
        out     (P126_NGS_DMA_CST),a
        ld      hl,p126_ngs_ipc_log_dma_rx_end
        call    p126_ngs_ipc_log
        ld      hl,p126_ngs_ipc_log_dma_rx_addr
        call    p126_ngs_ipc_log
        in      a,(P126_NGS_DMA_HAD)
        call    p126_ngs_ipc_log_hex_byte_inline
        in      a,(P126_NGS_DMA_MAD)
        call    p126_ngs_ipc_log_hex_byte_inline
        in      a,(P126_NGS_DMA_LAD)
        call    p126_ngs_ipc_log_hex_byte_inline
        call    p126_ngs_ipc_log_crlf
        ; One dummy aperture read plus exactly 4000h frame bytes. Do not
        ; acknowledge FF until the counter confirms the complete transfer.
        in      a,(P126_NGS_DMA_HAD)
        cp      #10
        jr      nz,.ngs_reverse_length_bad
        in      a,(P126_NGS_DMA_MAD)
        cp      #C0
        jr      nz,.ngs_reverse_length_bad
        in      a,(P126_NGS_DMA_LAD)
        cp      #01
        jr      nz,.ngs_reverse_length_bad
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ret
.ngs_reverse_length_bad:
        ld      hl,p126_ngs_ipc_log_dma_rx_length_bad
        call    p126_ngs_ipc_log
        ld      a,P126_STATUS_BAD_FRAME
        scf
        push    af
        xor     a
        out     (P126_NGS_CLRCBIT),a
        pop     af
        scf
        ret

p126_ngs_ipc_video_error_header:
        db 'P','1','2','6'
        db P126_IPC_MAJOR,P126_IPC_MINOR
        db P126_MSG_RESPONSE,P126_SERVICE_VIDEO,P126_OP_VIDEO_FRAME,0
        db #02,#00
        db #EE,#3F
        db P126_STATUS_NO_OPERATION,0
        db #00,#00

p126_ngs_ipc_video_header:
        db 'P','1','2','6'
        db P126_IPC_MAJOR,P126_IPC_MINOR
        db P126_MSG_RESPONSE,P126_SERVICE_VIDEO,P126_OP_VIDEO_FRAME,0
        db #02,#00
        db #EE,#3F
        db #00,#00
        db #00,#00

p126_ngs_ipc_dma_test_header:
        db 'P','1','2','6'
        db P126_IPC_MAJOR,P126_IPC_MINOR
        db P126_MSG_RESPONSE,P126_SERVICE_DIAGNOSTICS,P126_OP_DIAGNOSTIC,0
        db #02,#00              ; sequence = 2
        db #EE,#3F              ; payload length = 3FEEh (16366 bytes)
        db #00,#00
        db #00,#00

p126_ngs_ipc_dispatch_once::
        in      a,(P126_NGS_ZXSTAT)
        bit     0,a
        jr      nz,.p126_ngs_dispatch_command
        xor     a
        ret

.p126_ngs_dispatch_command:
        in      a,(P126_NGS_ZXCMD)
        cp      P126_CMD_HOST_FRAME
        jr      z,.p126_ngs_dispatch_host_frame

        cp      P126_CMD_NGS_FRAME
        jp      z,.p126_ngs_dispatch_ngs_frame
        cp      P126_CMD_NGS_VIDEO_FRAME
        jp      z,.p126_ngs_dispatch_video_frame

        ; Unknown command: release the doorbell and report a defined error.
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_NO_OPERATION
        scf
        ret

.p126_ngs_dispatch_host_frame:
        ld      hl,p126_ngs_ipc_log_dma_e0
        call    p126_ngs_ipc_log
        call    p126_ngs_ipc_dma_receive_frame
        ret     c

        ; Service dispatch happens only after full frame/CRC validation.
        ld      a,(#C007)
        cp      P126_SERVICE_IMAGE
        jr      z,.p126_ngs_dispatch_image
        cp      P126_SERVICE_VIDEO
        jr      z,.p126_ngs_dispatch_video
        cp      P126_SERVICE_INPUT
        jr      z,.p126_ngs_dispatch_input
        ; Diagnostics currently has no additional side effects.
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,1
        or      a
        ret

.p126_ngs_dispatch_input:
        ld      a,(#C008)
        cp      P126_OP_INPUT_KEYBOARD
        jp      nz,.input_keyboard_bad
        ld      hl,(#C00C)
        ld      de,1
        or      a
        sbc     hl,de
        jp      nz,.input_keyboard_bad
        ld      a,(p126_ngs_io_overlay_ready)
        or      a
        jp      z,.input_keyboard_bad
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        ld      ix,x86_io_keyboard_push_impl
        ld      a,(#C012)
        call    p126_overlay_call
        jr      c,.input_keyboard_full
        ld      hl,p126_ngs_input_keyboard_log
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,1
        or      a
        ret
.input_keyboard_full:
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_BUSY
        scf
        ret
.input_keyboard_bad:
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret

.p126_ngs_dispatch_video:
        ld      a,(#C008)
        cp      P126_OP_VIDEO_MODE
        jp      z,p126_ngs_video_mode
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_NO_OPERATION
        scf
        ret

.p126_ngs_dispatch_image:
        ld      a,(#C008)
        cp      P126_OP_IMAGE_BEGIN
        jp      z,p126_ngs_image_begin
        cp      P126_OP_IMAGE_FRAGMENT
        jp      z,p126_ngs_image_fragment
        cp      P126_OP_IMAGE_FINISH
        jp      z,p126_ngs_image_finish
        jr      .p126_ngs_image_bad_operation

.p126_ngs_image_bad_operation:
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_NO_OPERATION
        scf
        ret

.p126_ngs_dispatch_video_frame:
        ld      a,(p126_ngs_vid_overlay_ready)
        or      a
        jr      nz,.video_dispatch_mode_check
        ld      a,#E0                    ; X86VID overlay not installed
        jr      .video_dispatch_error
.video_dispatch_mode_check:
        ld      a,(p126_ngs_video_mode_ready)
        or      a
        jr      nz,.video_dispatch_convert
        ld      a,#E1                    ; ATM mode descriptor missing
        jr      .video_dispatch_error
.video_dispatch_convert:
        call    x86_video_convert
        jr      nc,.video_dispatch_success
        ; Preserve the converter's F1/F2/F3 reason in the error payload.
.video_dispatch_error:
        ld      (p126_ngs_video_error_code),a
        jp      p126_ngs_ipc_dma_send_video_error_frame
.video_dispatch_success:
        jp      p126_ngs_ipc_dma_send_video_frame

.p126_ngs_dispatch_ngs_frame:
        ; The host may request the stop record immediately after IMAGE_FINISH.
        ; BIOS execution requires SYSBIOS plus the X86IO, X86ALU and X86DEV overlays.
        ld      a,(p126_ngs_io_overlay_ready)
        or      a
        jr      z,.ngs_frame_trace_ready
        ld      a,(p126_ngs_alu_overlay_ready)
        or      a
        jr      z,.ngs_frame_trace_ready
        ld      a,(p126_ngs_dev_overlay_ready)
        or      a
        jr      z,.ngs_frame_trace_ready
        ld      a,(p126_ngs_exec_overlay_ready)
        or      a
        jr      z,.ngs_frame_trace_ready
        ; 0=BIOS image not installed, 1=installed/not started, 2=running.
        ; Keep the startup trace visible, then stop NeoGS #EF chatter: ATM and
        ; NeoGS writes share the emulator's merged debug stream and otherwise
        ; interleave with the host's per-byte IPC/CRC diagnostics.
        ld      a,(p126_ngs_bios_image_ready)
        cp      1
        jr      nz,.ngs_frame_trace_ready
        call    x86_bios_startup_trace
        ld      a,2
        ld      (p126_ngs_bios_image_ready),a
.ngs_frame_trace_ready:
        ld      hl,p126_ngs_ipc_log_dma_rx_request
        call    p126_ngs_ipc_log
        call    p126_ngs_ipc_dma_send_test_frame
        ret

; -------------------------------------------------------------------------
; VIDEO_MODE descriptor v1 (8 bytes):
; version, ATM mode, width, height, output format, flags, frame_size:u16.
; Only the currently implemented ATM RG6 80x25 text layout is accepted.
p126_ngs_video_mode:
        ld      hl,(#C00C)
        ld      de,P126_VIDEO_MODE_DESC_SIZE
        or      a
        sbc     hl,de
        jp      nz,.video_mode_bad
        ld      a,(#C012)
        cp      P126_VIDEO_DESC_VERSION
        jp      nz,.video_mode_bad
        ld      a,(#C013)
        cp      P126_ATM_MODE_RG6_TEXT80X25
        jp      nz,.video_mode_bad
        ld      a,(#C014)
        cp      P126_VIDEO_TEXT80_WIDTH
        jp      nz,.video_mode_bad
        ld      a,(#C015)
        cp      P126_VIDEO_TEXT80_HEIGHT
        jp      nz,.video_mode_bad
        ld      a,(#C016)
        cp      P126_VIDEO_FORMAT_TEXT80X25
        jp      nz,.video_mode_bad
        ld      a,(#C017)
        or      a
        jp      nz,.video_mode_bad
        ld      hl,(#C018)
        ld      de,P126_VIDEO_TEXT80_FRAME_SIZE
        or      a
        sbc     hl,de
        jp      nz,.video_mode_bad

        ld      hl,#C012
        ld      de,p126_ngs_video_mode_desc
        ld      bc,P126_VIDEO_MODE_DESC_SIZE
        ldir
        ld      a,1
        ld      (p126_ngs_video_mode_ready),a
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,1
        or      a
        ret
.video_mode_bad:
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret

; -------------------------------------------------------------------------
; IMAGE service ABI 1.1. The host supplies a physical destination page
; in IMAGE_BEGIN; the receiver validates the kind/page policy and derives
; the WIN3/MPAGEX selector instead of hard-wiring a selector per image kind.
; SYSBIOS remains pinned to page10h; X86IO/ALU/DEV/EXEC use pages04h-07h.
; X86VGA is installed on dynamic allocator page08h and registered after readback.
; -------------------------------------------------------------------------
p126_ngs_image_begin:
        ld      hl,p126_ngs_image_begin_log
        call    p126_ngs_ipc_log
        ld      a,(#C00C)
        cp      6
        jp      nz,.image_begin_bad

        ; Message ID is currently 0001h for each serialized image transaction.
        ld      hl,(#C012)
        ld      de,1
        or      a
        sbc     hl,de
        jp      nz,.image_begin_bad

        ld      a,(#C014)
        cp      P126_IMAGE_KIND_SYSBIOS
        jr      z,.image_begin_sysbios
        cp      P126_IMAGE_KIND_X86IO
        jr      z,.image_begin_x86io
        cp      P126_IMAGE_KIND_X86ALU
        jp      z,.image_begin_x86alu
        cp      P126_IMAGE_KIND_X86DEV
        jp      z,.image_begin_x86dev
        cp      P126_IMAGE_KIND_X86EXEC
        jp      z,.image_begin_x86exec
        cp      P126_IMAGE_KIND_X86VGA
        jp      z,.image_begin_x86vga
        cp      P126_IMAGE_KIND_X86VID
        jp      z,.image_begin_x86vid
        jp      .image_begin_bad

.image_begin_sysbios:
        ld      a,(#C015)
        cp      #10
        jp      nz,.image_begin_bad
        ld      hl,(#C016)
        ld      de,P126_IMAGE_SYSBIOS_SIZE
        or      a
        sbc     hl,de
        jp      nz,.image_begin_bad
        jp      .image_begin_common

.image_begin_x86io:
        ld      a,(#C015)
        cp      P126_NGS_X86IO_OVERLAY_PAGE
        jp      nz,.image_begin_bad
        ld      hl,(#C016)
        ld      a,h
        or      l
        jp      z,.image_begin_bad
        ld      de,P126_IMAGE_X86IO_MAX_SIZE
        or      a
        sbc     hl,de
        jp      c,.image_begin_common
        jp      z,.image_begin_common
        jp      .image_begin_bad

.image_begin_x86alu:
        ld      a,(#C015)
        cp      P126_NGS_ALU_OVERLAY_PAGE
        jp      nz,.image_begin_bad
        ld      hl,(#C016)
        ld      a,h
        or      l
        jp      z,.image_begin_bad
        ld      de,P126_IMAGE_X86ALU_MAX_SIZE
        or      a
        sbc     hl,de
        jp      c,.image_begin_common
        jp      z,.image_begin_common
        jp      .image_begin_bad

.image_begin_x86dev:
        ld      a,(#C015)
        cp      P126_NGS_X86DEV_OVERLAY_PAGE
        jp      nz,.image_begin_bad
        ld      hl,(#C016)
        ld      a,h
        or      l
        jp      z,.image_begin_bad
        ld      de,P126_IMAGE_X86DEV_MAX_SIZE
        or      a
        sbc     hl,de
        jp      c,.image_begin_common
        jp      z,.image_begin_common
        jp      .image_begin_bad

.image_begin_x86exec:
        ld      a,(#C015)
        cp      P126_NGS_X86EXEC_OVERLAY_PAGE
        jp      nz,.image_begin_bad
        ld      hl,(#C016)
        ld      a,h
        or      l
        jp      z,.image_begin_bad
        ld      de,P126_IMAGE_X86EXEC_MAX_SIZE
        or      a
        sbc     hl,de
        jp      c,.image_begin_common
        jr      z,.image_begin_common
        jp      .image_begin_bad

.image_begin_x86vga:
        ; Dynamic VGA overlay is installed on allocator page08h.
        ld      a,(#C015)
        cp      #08
        jp      nz,.image_begin_bad
        ld      hl,(#C016)
        ld      a,h
        or      l
        jp      z,.image_begin_bad
        ld      de,P126_IMAGE_X86VGA_MAX_SIZE
        or      a
        sbc     hl,de
        jr      c,.image_begin_common
        jr      z,.image_begin_common
        jp      .image_begin_bad

.image_begin_x86vid:
        ; Dynamic ATM video converter is installed on allocator page09h.
        ld      a,(#C015)
        cp      P126_NGS_X86VID_OVERLAY_PAGE
        jp      nz,.image_begin_bad
        ld      hl,(#C016)
        ld      a,h
        or      l
        jp      z,.image_begin_bad
        ld      de,P126_IMAGE_X86VID_MAX_SIZE
        or      a
        sbc     hl,de
        jr      c,.image_begin_common
        jr      z,.image_begin_common
        jp      .image_begin_bad

.image_begin_common:
        ; MPAGEX selector is ROR8(physical page), independent of WIN2 selector.
        ld      a,(#C015)
        rrca
        ld      (p126_ngs_image_dest_selector),a
        ld      hl,(#C012)
        ld      (p126_ngs_image_id),hl
        ld      hl,(#C016)
        ld      (p126_ngs_image_size),hl
        ld      a,(#C014)
        ld      (p126_ngs_image_kind),a
        ld      a,1
        ld      (p126_ngs_image_active),a
        xor     a
        ld      (p126_ngs_image_received),a
        ld      a,(p126_ngs_image_kind)
        cp      P126_IMAGE_KIND_SYSBIOS
        jr      nz,.image_begin_not_bios
        xor     a
        ld      (p126_ngs_bios_image_ready),a
        jp      .image_begin_ack
.image_begin_not_bios:
        cp      P126_IMAGE_KIND_X86IO
        jr      nz,.image_begin_not_x86io
        xor     a
        ld      (p126_ngs_io_overlay_ready),a
        jr      .image_begin_ack
.image_begin_not_x86io:
        cp      P126_IMAGE_KIND_X86ALU
        jr      nz,.image_begin_not_x86alu
        xor     a
        ld      (p126_ngs_alu_overlay_ready),a
        jr      .image_begin_ack
.image_begin_not_x86alu:
        cp      P126_IMAGE_KIND_X86DEV
        jr      nz,.image_begin_not_x86dev
        xor     a
        ld      (p126_ngs_dev_overlay_ready),a
        jr      .image_begin_ack
.image_begin_not_x86dev:
        cp      P126_IMAGE_KIND_X86EXEC
        jr      nz,.image_begin_not_x86exec
        xor     a
        ld      (p126_ngs_exec_overlay_ready),a
        jr      .image_begin_ack
.image_begin_not_x86exec:
        cp      P126_IMAGE_KIND_X86VGA
        jr      nz,.image_begin_not_x86vga
        xor     a
        ld      (p126_ngs_vga_overlay_ready),a
        jr      .image_begin_ack
.image_begin_not_x86vga:
        cp      P126_IMAGE_KIND_X86VID
        jr      nz,.image_begin_ack
        xor     a
        ld      (p126_ngs_vid_overlay_ready),a
.image_begin_ack:
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,1
        or      a
        ret
.image_begin_bad:
        ld      hl,p126_ngs_image_begin_rejected_log
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret

p126_ngs_image_fragment:
        ld      hl,p126_ngs_image_fragment_log
        call    p126_ngs_ipc_log
        ld      a,(p126_ngs_image_active)
        or      a
        jp      z,.image_fragment_bad
        ld      a,(#C009)
        bit     1,a
        jp      z,.image_fragment_bad

        ; Exactly one fragment: index 0, count 1, matching message ID.
        ld      hl,(#C012)
        ld      de,(p126_ngs_image_id)
        or      a
        sbc     hl,de
        jp      nz,.image_fragment_bad
        ld      hl,(#C014)
        ld      de,0
        or      a
        sbc     hl,de
        jp      nz,.image_fragment_bad
        ld      a,(#C016)
        cp      1
        jp      nz,.image_fragment_bad
        ld      a,(#C017)
        or      a
        jp      nz,.image_fragment_bad

        ; The u32 total logical length must equal the IMAGE_BEGIN size.
        ld      hl,(#C018)
        ld      de,(p126_ngs_image_size)
        or      a
        sbc     hl,de
        jp      nz,.image_fragment_bad
        ld      a,(#C01A)
        or      a
        jp      nz,.image_fragment_bad
        ld      a,(#C01B)
        or      a
        jp      nz,.image_fragment_bad

        ; Frame payload length must be exactly extension(10)+image bytes.
        ld      hl,(p126_ngs_image_size)
        ld      de,P126_IMAGE_FRAGMENT_EXT_SIZE
        add     hl,de
        ld      de,(#C00C)
        or      a
        sbc     hl,de
        jp      nz,.image_fragment_bad

        ; Copy the validated page-42 fragment into the selected physical page.
        ; Code/stack stay in WIN0/WIN1; WIN3 is used only as the copy aperture.
        ld      hl,#C01C
        ld      de,#C000
        ld      bc,(p126_ngs_image_size)
.image_copy_loop:
        ld      a,#21                  ; page 42h RRCA selector
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(hl)
        push    af
        ld      a,(p126_ngs_image_dest_selector)
        out     (P126_NGS_MPAGEX_PORT),a
        pop     af
        ld      (de),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.image_copy_loop

        ; Verify every installed byte against the validated staging frame.
        ld      hl,#C01C
        ld      de,#C000
        ld      bc,(p126_ngs_image_size)
        ld      (p126_ngs_image_verify_count),bc
.image_verify_loop:
        ld      a,#21
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(hl)
        ld      (p126_ngs_image_verify_byte),a
        ld      a,(p126_ngs_image_dest_selector)
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(de)
        ld      b,a
        ld      a,(p126_ngs_image_verify_byte)
        cp      b
        jp      nz,.image_verify_bad
        inc     hl
        inc     de
        ld      bc,(p126_ngs_image_verify_count)
        dec     bc
        ld      (p126_ngs_image_verify_count),bc
        ld      a,b
        or      c
        jr      nz,.image_verify_loop

        ; Restore production DMA staging mapping before acknowledging.
        ld      a,#21
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,1
        ld      (p126_ngs_image_received),a
        ld      a,(p126_ngs_image_kind)
        cp      P126_IMAGE_KIND_SYSBIOS
        jr      nz,.image_not_bios_verify_log
        ld      hl,p126_ngs_image_verify_ok_log
        jr      .image_verify_log
.image_not_bios_verify_log:
        cp      P126_IMAGE_KIND_X86IO
        jr      nz,.image_alu_verify_log
        ld      hl,p126_ngs_io_overlay_verify_ok_log
        jr      .image_verify_log
.image_alu_verify_log:
        cp      P126_IMAGE_KIND_X86ALU
        jr      nz,.image_dev_verify_log
        ld      hl,p126_ngs_alu_overlay_verify_ok_log
        jr      .image_verify_log
.image_dev_verify_log:
        ld      hl,p126_ngs_image_fragment_log
.image_verify_log:
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,1
        or      a
        ret

.image_verify_bad:
        ld      a,#21                  ; leave WIN3 on production DMA page
        out     (P126_NGS_MPAGEX_PORT),a
.image_fragment_bad:
        ld      hl,p126_ngs_image_fragment_rejected_log
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_BAD_FRAGMENT
        scf
        ret

p126_ngs_image_finish:
        ld      hl,p126_ngs_image_finish_log
        call    p126_ngs_ipc_log
        ld      a,(p126_ngs_image_active)
        or      a
        jp      z,.image_finish_bad
        ld      a,(p126_ngs_image_received)
        or      a
        jp      z,.image_finish_bad
        ld      a,(#C00C)
        cp      2
        jp      nz,.image_finish_bad
        ld      hl,(#C012)
        ld      de,(p126_ngs_image_id)
        or      a
        sbc     hl,de
        jp      nz,.image_finish_bad

        xor     a
        ld      (p126_ngs_image_active),a
        ld      a,(p126_ngs_image_kind)
        cp      P126_IMAGE_KIND_SYSBIOS
        jr      nz,.image_finish_not_bios
        ld      a,1
        ld      (p126_ngs_bios_image_ready),a
        ld      hl,p126_ngs_image_installed_log
        jp      .image_finish_log
.image_finish_not_bios:
        cp      P126_IMAGE_KIND_X86IO
        jp      nz,.image_finish_x86alu
.image_finish_x86io:
        ; Prove that MPAG selects two distinct physical pages through WIN2.
        ; At this point page05 is still free; X86ALU is loaded only after
        ; the X86IO mapping and nested-gate self-tests have completed.
        call    p126_ngs_overlay_win2_selftest
        jr      nc,.image_finish_x86io_map_ok
        call    p126_ngs_overlay_log_test_failure
        jp      .image_finish_bad
.image_finish_x86io_map_ok:
        ; The self-test leaves physical page 04h selected in WIN2.
        ; Keep the nested-call gate's software selector synchronized.
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_current_selector),a
        ld      a,5
        ld      (p126_ngs_overlay_test_fail_stage),a
        call    p126_ngs_overlay_gate_selftest
        jr      nc,.image_finish_gate_ok
        call    p126_ngs_overlay_log_test_failure
        jp      .image_finish_bad
.image_finish_gate_ok:
        ld      hl,p126_ngs_overlay_win2_test_pass_log
        call    p126_ngs_ipc_log
        ld      a,1
        ld      (p126_ngs_io_overlay_ready),a
        ld      hl,p126_ngs_io_overlay_installed_log
        jp      .image_finish_log
.image_finish_x86alu:
        cp      P126_IMAGE_KIND_X86ALU
        jr      nz,.image_finish_x86dev
        ; Page05 is the fixed-origin ALU overlay. Probe it through the same
        ; resident gate used by every arithmetic entry point.
        ld      a,#3C
        scf
        ld      hl,#1234
        call    x86_alu_overlay_probe
        cp      #A5
        jr      nz,.image_finish_alu_probe_bad
        ld      de,#5AA5
        or      a
        sbc     hl,de
        jr      nz,.image_finish_alu_probe_bad
        ld      a,(p126_overlay_current_selector)
        cp      P126_NGS_X86IO_OVERLAY_SELECTOR
        jr      nz,.image_finish_alu_probe_bad
        ld      a,1
        ld      (p126_ngs_alu_overlay_ready),a
        ld      hl,p126_ngs_alu_overlay_installed_log
        jp      .image_finish_log
.image_finish_alu_probe_bad:
        ld      hl,p126_ngs_alu_overlay_probe_fail_log
        call    p126_ngs_ipc_log
        jp      .image_finish_bad

.image_finish_x86dev:
        cp      P126_IMAGE_KIND_X86DEV
        jr      nz,.image_finish_x86exec
        ; Page06 must be callable through the resident gate and return to the
        ; prior page04 selector. Run both register-model self-tests before ready.
        call    x86_dev_reset
        cp      #5A
        jr      nz,.image_finish_dev_probe_bad
        ld      de,#06D1
        or      a
        sbc     hl,de
        jr      nz,.image_finish_dev_probe_bad
        ld      a,(p126_overlay_current_selector)
        cp      P126_NGS_X86IO_OVERLAY_SELECTOR
        jr      nz,.image_finish_dev_probe_bad
        call    x86_dev_reset
        ld      a,1
        ld      (p126_ngs_dev_overlay_ready),a
        ld      hl,p126_ngs_image_finish_log
        jp      .image_finish_log
.image_finish_dev_probe_bad:
        jp      .image_finish_bad

.image_finish_x86exec:
        cp      P126_IMAGE_KIND_X86EXEC
        jr      nz,.image_finish_x86vga
        ; Page07 contains the complete 8086 dispatcher. Probe it through the
        ; resident WIN2 gate and verify the prior X86IO mapping is restored.
        ld      a,P126_NGS_X86EXEC_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        ld      ix,x86_exec_overlay_probe
        call    p126_overlay_call
        cp      #E7
        jr      nz,.image_finish_exec_probe_bad
        ld      a,(p126_overlay_current_selector)
        cp      P126_NGS_X86IO_OVERLAY_SELECTOR
        jr      nz,.image_finish_exec_probe_bad
        ld      a,1
        ld      (p126_ngs_exec_overlay_ready),a
        ld      hl,p126_ngs_exec_overlay_installed_log
        jp      .image_finish_log
.image_finish_exec_probe_bad:
        ld      hl,p126_ngs_exec_overlay_probe_fail_log
        call    p126_ngs_ipc_log
        jp      .image_finish_bad

.image_finish_x86vga:
        cp      P126_IMAGE_KIND_X86VGA
        jp      nz,.image_finish_x86vid
        ; Register the dynamic page only after fragment readback has passed.
        ld      a,5
        ld      b,#08
        call    p126_overlay_register_dynamic
        jp      c,.image_finish_bad
        ; Probe through the normal resident gate before publishing READY.
        ld      a,5
        ld      ix,x86_vga_overlay_probe
        call    p126_overlay_call_module
        cp      #56
        jr      nz,.image_finish_vga_probe_bad
        ld      de,#A55A
        or      a
        sbc     hl,de
        jr      nz,.image_finish_vga_probe_bad
        ; Initialize VGA state only after the dynamic module passed its probe.
        ld      a,5
        ld      ix,x86_vga_reset_impl
        call    p126_overlay_call_module
        ld      a,5
        ld      ix,x86_vga_register_selftest_impl
        call    p126_overlay_call_module
        cp      #5A
        jr      nz,.image_finish_vga_probe_bad
        ld      de,#A55A
        or      a
        sbc     hl,de
        jr      nz,.image_finish_vga_probe_bad
        ld      a,1
        ld      (p126_ngs_vga_overlay_ready),a
        ld      hl,p126_ngs_vga_overlay_installed_log
        jr      .image_finish_log
.image_finish_vga_probe_bad:
        ld      a,5
        call    p126_overlay_unregister_dynamic
        jp      .image_finish_bad

.image_finish_x86vid:
        cp      P126_IMAGE_KIND_X86VID
        jp      nz,.image_finish_bad
        ; Converter module is separately registered on dynamic page09h.
        ld      a,P126_NGS_X86VID_MODULE_ID
        ld      b,P126_NGS_X86VID_OVERLAY_PAGE
        call    p126_overlay_register_dynamic
        jp      c,.image_finish_bad
        ld      a,P126_NGS_X86VID_MODULE_ID
        ld      ix,x86_video_overlay_probe
        call    p126_overlay_call_module
        cp      #56
        jr      nz,.image_finish_vid_probe_bad
        ld      de,#A55A
        or      a
        sbc     hl,de
        jr      nz,.image_finish_vid_probe_bad
        ld      a,1
        ld      (p126_ngs_vid_overlay_ready),a
        ld      hl,p126_ngs_image_finish_log
        jr      .image_finish_log
.image_finish_vid_probe_bad:
        ld      a,P126_NGS_X86VID_MODULE_ID
        call    p126_overlay_unregister_dynamic
        jp      .image_finish_bad

.image_finish_log:
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,1
        or      a
        ret
.image_finish_bad:
        ld      hl,p126_ngs_image_finish_rejected_log
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret

; Runtime WIN2 selector/read-write test for physical pages 04h and 05h.
; WIN3/MPAGEX is the physical reference. For each page, compare its last
; byte through WIN2/BFFFh and WIN3/CFFFh, write through WIN2, then read the
; same physical byte through WIN3. Save/restore both bytes and return with
; WIN2=page04 (X86IO), WIN3=page42 (production DMA staging).
; OUT: carry clear on success.
p126_ngs_overlay_win2_selftest:
        ; Reassert the required RAM/extended-window mode instead of relying
        ; on the configuration value left by stage-0. RAMRO must be clear;
        ; NOROM and EXPAG must be set for writable independent WIN2/WIN3.
        in      a,(#0F)
        and     #CD                    ; clear RAMRO and clock-select bits
        or      #29                    ; 20 MHz + NOROM + EXPAG
        out     (#0F),a
        in      a,(#0F)
        and     #0B                    ; NOROM, RAMRO, EXPAG
        cp      #09
        jp      nz,.overlay_win2_test_config_failed

        ; Save the original last byte of both pinned pages through WIN3.
        ld      a,P126_NGS_X86IO_OVERLAY_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(#FFFF)
        ld      (p126_ngs_overlay_test_old04),a
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(#FFFF)
        ld      (p126_ngs_overlay_test_old05),a

        ; Stage 01: prove WIN3 can write/read page04 with a nonzero marker.
        ld      a,1
        ld      (p126_ngs_overlay_test_fail_stage),a
        ld      a,P126_NGS_X86IO_OVERLAY_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,#3C
        ld      (#FFFF),a
        ld      a,(#FFFF)
        cp      #3C
        jp      nz,.overlay_win2_test_failed

        ; Stage 02: WIN2 page04 must see the exact marker written via WIN3.
        ld      a,2
        ld      (p126_ngs_overlay_test_fail_stage),a
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ld      a,(#BFFF)
        cp      #3C
        jp      nz,.overlay_win2_test_failed

        ; Stage 03: prove WIN3 can write/read page05 with a distinct marker.
        ld      a,3
        ld      (p126_ngs_overlay_test_fail_stage),a
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,#5A
        ld      (#FFFF),a
        ld      a,(#FFFF)
        cp      #5A
        jp      nz,.overlay_win2_test_failed

        ; Stage 04: WIN2 page05 must see the marker written via WIN3.
        ld      a,4
        ld      (p126_ngs_overlay_test_fail_stage),a
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ld      a,(#BFFF)
        cp      #5A
        jp      nz,.overlay_win2_test_failed

        ; Stage 05: write through WIN2 and verify the write locally.
        ld      a,5
        ld      (p126_ngs_overlay_test_fail_stage),a
        ld      a,#A5
        ld      (#BFFF),a
        ld      a,(#BFFF)
        cp      #A5
        jp      nz,.overlay_win2_test_failed

        ; Stage 06: the WIN2 page05 write must be visible through WIN3.
        ld      a,6
        ld      (p126_ngs_overlay_test_fail_stage),a
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(#FFFF)
        cp      #A5
        jp      nz,.overlay_win2_test_failed

        ; Stage 07: write through WIN2 page04 and verify through WIN3.
        ld      a,7
        ld      (p126_ngs_overlay_test_fail_stage),a
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ld      a,#C3
        ld      (#BFFF),a
        ld      a,P126_NGS_X86IO_OVERLAY_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(#FFFF)
        cp      #C3
        jp      nz,.overlay_win2_test_failed

        ; Restore both original bytes through WIN3 after all checks pass.
        ld      a,(p126_ngs_overlay_test_old04)
        ld      (#FFFF),a
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(p126_ngs_overlay_test_old05)
        ld      (#FFFF),a
        jr      .overlay_win2_test_restore_maps

.overlay_win2_test_config_failed:
        xor     a
        ld      (p126_ngs_overlay_test_fail_stage),a
        call    p126_ngs_overlay_test_restore_maps
        scf
        ret

.overlay_win2_test_failed:
        ; Best-effort restoration even when one WIN2 selector is incorrect.
        ld      a,P126_NGS_X86IO_OVERLAY_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(p126_ngs_overlay_test_old04)
        ld      (#FFFF),a
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(p126_ngs_overlay_test_old05)
        ld      (#FFFF),a
        call    p126_ngs_overlay_test_restore_maps
        scf
        ret

.overlay_win2_test_restore_maps:
        call    p126_ngs_overlay_test_restore_maps
        or      a
        ret

; Exercise the resident call gate before publishing X86IO_READY.
; Page 05h is currently free. Preserve its first four bytes, install a tiny
; CALL x86_io_reset / RET overlay stub, and execute it while WIN2=page05.
; The resident wrapper must switch to page04 for X86IO, then restore page05
; so the test stub can execute its RET at 8003h. Finally restore page05 bytes
; and leave WIN2=page04, WIN3=page42.
; OUT: carry clear if the page05 -> page04 -> page05 call completed correctly.
p126_ngs_overlay_gate_selftest:
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      hl,#C000
        ld      de,p126_ngs_overlay_gate_old_code
        ld      bc,4
        ldir

        ld      hl,p126_ngs_overlay_gate_test_code
        ld      de,#C000
        ld      bc,4
        ldir

        ; Set the software shadow before entering page05 through WIN2.
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        ld      (p126_overlay_current_selector),a
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a

        call    #8000                  ; page05 stub calls resident X86IO wrapper

        ; If the trampoline restored page05, its first opcode is still CDh.
        ld      a,(#8000)
        cp      #CD
        jr      nz,.overlay_gate_test_failed
        ld      a,(p126_overlay_current_selector)
        cp      #82                    ; ROR8(page05)
        jr      nz,.overlay_gate_test_failed

        ; Restore page05's original first four bytes.
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      hl,p126_ngs_overlay_gate_old_code
        ld      de,#C000
        ld      bc,4
        ldir
        jr      .overlay_gate_test_restore_maps

.overlay_gate_test_failed:
        ; Restore the scratch bytes even when the gate returned incorrectly.
        ld      a,P126_NGS_OVERLAY_TEST_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      hl,p126_ngs_overlay_gate_old_code
        ld      de,#C000
        ld      bc,4
        ldir
        call    p126_ngs_overlay_test_restore_maps
        scf
        ret

.overlay_gate_test_restore_maps:
        call    p126_ngs_overlay_test_restore_maps
        or      a
        ret

p126_ngs_overlay_gate_test_code:
        db      #CD
        dw      x86_io_reset
        db      #C9
p126_ngs_overlay_gate_old_code:
        defs    4,0
p126_ngs_overlay_test_restore_maps:
        ld      a,P126_NGS_DMA_PAGE
        rrca
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_current_selector),a
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ret

p126_ngs_overlay_test_old04: db 0
p126_ngs_overlay_test_old05: db 0
p126_ngs_overlay_test_fail_stage: db 0
p126_ngs_overlay_test_fail_prefix: db "[NGS] WIN2 FAIL STAGE ",0
p126_ngs_overlay_win2_test_pass_log: db "[NGS] WIN2 MAP/GATE TEST PASS",13,10,0

p126_ngs_overlay_log_test_failure:
        ld      hl,p126_ngs_overlay_test_fail_prefix
        call    p126_ngs_ipc_log
        ld      a,(p126_ngs_overlay_test_fail_stage)
        call    p126_ngs_ipc_log_hex_byte_inline
        jp      p126_ngs_ipc_log_crlf

p126_ngs_image_active:       db 0
p126_ngs_image_received:     db 0
p126_ngs_bios_image_ready:   db 0
p126_ngs_io_overlay_ready:   db 0
p126_ngs_alu_overlay_ready:  db 0
p126_ngs_dev_overlay_ready:  db 0
p126_ngs_exec_overlay_ready: db 0
p126_ngs_vga_overlay_ready:  db 0
p126_ngs_vid_overlay_ready:  db 0
p126_ngs_video_mode_ready:   db 0
p126_ngs_video_mode_desc:    defs P126_VIDEO_MODE_DESC_SIZE,0
p126_ngs_video_error_code:   db 0
p126_ngs_video_frame_sequence: dw 0
p126_ngs_image_id:           dw 0
p126_ngs_image_size:         dw 0
p126_ngs_image_kind:         db 0
p126_ngs_image_dest_selector: db 0
p126_ngs_image_verify_count: dw 0
p126_ngs_image_verify_byte:  db 0
p126_ngs_input_keyboard_log: db "[NGS] X86 KEY EVENT",13,10,0
p126_ngs_image_begin_log:    db "[NGS] IMG BEGIN",13,10,0
p126_ngs_image_fragment_log: db "[NGS] IMG FRAG",13,10,0
p126_ngs_image_finish_log:   db "[NGS] IMG FINISH",13,10,0
p126_ngs_image_installed_log: db "[NGS] SYSBIOS PAGE10 OK",13,10,0
p126_ngs_image_verify_ok_log: db "[NGS] SYSBIOS RD OK",13,10,0
p126_ngs_io_overlay_installed_log: db "[NGS] X86IO PAGE04 WIN2 OK",13,10,0
p126_ngs_io_overlay_verify_ok_log: db "[NGS] X86IO RD OK",13,10,0
p126_ngs_alu_overlay_verify_ok_log: db "[NGS] X86ALU RD OK",13,10,0
p126_ngs_alu_overlay_installed_log: db "[NGS] X86ALU GATE OK",13,10,0
p126_ngs_alu_overlay_probe_fail_log: db "[NGS] X86ALU GATE FAIL",13,10,0
p126_ngs_exec_overlay_installed_log: db "[NGS] X86EXEC PAGE07 GATE OK",13,10,0
p126_ngs_exec_overlay_probe_fail_log: db "[NGS] X86EXEC GATE FAIL",13,10,0
p126_ngs_vga_overlay_installed_log: db "[NGS] X86VGA DYNAMIC PAGE08 GATE OK",13,10,0
p126_ngs_image_begin_rejected_log: db "[NGS] IMG BEGIN BAD",13,10,0
p126_ngs_image_fragment_rejected_log: db "[NGS] IMG FRAG BAD",13,10,0
p126_ngs_image_finish_rejected_log: db "[NGS] IMG FINISH BAD",13,10,0

; Standard CRC-16/CCITT-FALSE regression vector.
; OUT: Carry clear and HL=#29B1 on pass; Carry set on failure.
p126_ngs_ipc_crc16_selftest::
        push    bc
        push    de
        ld      hl, #FFFF
        ld      de, p126_ngs_ipc_crc16_test_vector
        ld      b, 9
.p126_ngs_crc_test_loop:
        ld      a, (de)
        inc     de
        call    p126_ngs_ipc_crc16_update
        djnz    .p126_ngs_crc_test_loop
        ld      de, #29B1
        or      a
        sbc     hl, de
        jr      nz, .p126_ngs_crc_test_failed
        pop     de
        pop     bc
        ld      hl, #29B1
        or      a
        ret
.p126_ngs_crc_test_failed:
        pop     de
        pop     bc
        scf
        ret

p126_ngs_ipc_crc16_test_vector:
        db "123456789"

; Independent NeoGS #EF diagnostics for the DMA transaction lifecycle.
p126_ngs_ipc_log_dma_e0:          db "[NGS] DMA E0",13,10,0
p126_ngs_ipc_log_dma_cfg_begin:   db "[NGS] DMA CFG",13,10,0
p126_ngs_ipc_log_dma_armed:       db "[NGS] DMA ARMED",13,10,0
p126_ngs_ipc_log_dma_ready:       db "[NGS] DMA READY",13,10,0
p126_ngs_ipc_log_dma_host_end:    db "[NGS] DMA HOST END",13,10,0
p126_ngs_ipc_log_dma_timeout:     db "[NGS] DMA TIMEOUT",13,10,0
p126_ngs_ipc_log_bad_length:      db "[NGS] DMA BAD LENGTH",13,10,0
p126_ngs_ipc_log_dma_stopped:     db "[NGS] DMA STOPPED",13,10,0
p126_ngs_ipc_log_dma_page42_premapped: db "[NGS] P42 PRE",13,10,0
p126_ngs_ipc_log_dma_page42_mapped: db "[NGS] DMA P42 MAP",13,10,0
p126_ngs_ipc_log_dma_end:         db "[NGS] DMA END",13,10,0
p126_ngs_ipc_log_dma_addr:        db "[NGS] DMA ADDR=",0
p126_ngs_ipc_log_rx_header:       db "[NGS] RX HDR=",0
p126_ngs_ipc_log_frame_valid:     db "[NGS] FRAME OK",13,10,0
p126_ngs_ipc_log_frame_rejected:  db "[NGS] FRAME BAD=",0
p126_ngs_ipc_log_dma_rx_request: db "[NGS] DMA RX REQ",13,10,0
p126_ngs_ipc_log_dma_rx_armed:   db "[NGS] DMA RX ARMED",13,10,0
p126_ngs_ipc_log_dma_rx_end:     db "[NGS] DMA RX END",13,10,0
p126_ngs_ipc_log_dma_rx_addr:    db "[NGS] RX ADDR=",0
p126_ngs_ipc_log_dma_rx_timeout: db "[NGS] DMA RX TIMEOUT",13,10,0
p126_ngs_ipc_log_dma_rx_length_bad: db "[NGS] RX LEN BAD",13,10,0

; Emit CR/LF on NeoGS's independent #EF diagnostic channel.
p126_ngs_ipc_log_crlf:
        push    af
        push    bc
        ld      bc,#00EF
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a
        pop     bc
        pop     af
        ret

; Print A as two hex digits without a line ending. Preserves AF/BC.
p126_ngs_ipc_log_hex_byte_inline:
        push    af
        push    bc
        rrca
        rrca
        rrca
        rrca
        call    p126_ngs_ipc_log_hex_nibble
        pop     bc
        pop     af
        push    af
        and     #0F
        call    p126_ngs_ipc_log_hex_nibble
        pop     af
        ret

; Print a status byte as two hex digits followed by CR/LF. Preserves AF/BC.
p126_ngs_ipc_log_hex_byte:
        push    af
        push    bc
        rrca
        rrca
        rrca
        rrca
        call    p126_ngs_ipc_log_hex_nibble
        pop     bc
        pop     af
        push    af
        and     #0F
        call    p126_ngs_ipc_log_hex_nibble
        pop     af
        push    bc
        ld      bc,#00EF
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a
        pop     bc
        ret

p126_ngs_ipc_log_hex_nibble:
        and     #0F
        add     a,'0'
        cp      '9'+1
        jr      c,.p126_ngs_hex_emit
        add     a,7
.p126_ngs_hex_emit:
        push    bc
        ld      bc,#00EF
        out     (c),a
        pop     bc
        ret

; This IPC module is assembled both standalone and into the resident image.
; Keep its diagnostics self-contained instead of importing the resident logger.
; IN: HL = zero-terminated message. OUT: AF/BC preserved; HL advanced to NUL.
p126_ngs_ipc_log:
        push    af
        push    bc
        ld      a,(p126_ngs_bios_image_ready)
        cp      2
        jr      z,.p126_ngs_ipc_log_suppressed
        ld      bc,#00EF
.p126_ngs_ipc_log_loop:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,.p126_ngs_ipc_log_done
        out     (c),a
        jr      .p126_ngs_ipc_log_loop
.p126_ngs_ipc_log_done:
        pop     bc
        pop     af
        ret
.p126_ngs_ipc_log_suppressed:
        ; Retain the logger's documented HL-to-NUL behavior without output.
        ld      a,(hl)
        inc     hl
        or      a
        jr      nz,.p126_ngs_ipc_log_suppressed
        pop     bc
        pop     af
        ret
