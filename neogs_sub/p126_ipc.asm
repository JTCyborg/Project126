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
        ; Build the deterministic reverse frame directly in production page
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
        jr      z,.p126_ngs_dispatch_ngs_frame

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
        ; Diagnostics currently has no additional side effects.
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,1
        or      a
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

.p126_ngs_dispatch_ngs_frame:
        ; The host may request the stop record immediately after IMAGE_FINISH.
        ; If the resident loop has not consumed BIOS_IMAGE_READY yet, execute
        ; the bounded startup slice now so the DMA response contains its result.
        ld      a,(p126_ngs_bios_image_ready)
        or      a
        jr      z,.ngs_frame_trace_ready
        xor     a
        ld      (p126_ngs_bios_image_ready),a
        call    x86_bios_startup_trace
.ngs_frame_trace_ready:
        ld      hl,p126_ngs_ipc_log_dma_rx_request
        call    p126_ngs_ipc_log
        call    p126_ngs_ipc_dma_send_test_frame
        ret

; -------------------------------------------------------------------------
; IMAGE service — initial 8 KiB system BIOS installation.
; The standard 10-byte ABI fragment extension is used even for one fragment.
; WIN3 maps the DMA staging page 42h and the destination SYSBIOS page 10h.
; Resident code/stack remain outside WIN3.
; -------------------------------------------------------------------------
p126_ngs_image_begin:
        ld      hl,p126_ngs_image_begin_log
        call    p126_ngs_ipc_log
        ld      a,(#C00C)
        cp      6
        jr      nz,.image_begin_bad
        ld      a,(#C012)
        cp      1
        jr      nz,.image_begin_bad
        ld      a,(#C013)
        or      a
        jr      nz,.image_begin_bad
        ld      a,(#C014)
        cp      P126_IMAGE_KIND_SYSBIOS
        jr      nz,.image_begin_bad
        ld      a,(#C015)
        or      a
        jr      nz,.image_begin_bad
        ld      a,(#C016)
        or      a
        jr      nz,.image_begin_bad
        ld      a,(#C017)
        cp      #20
        jr      nz,.image_begin_bad
        ld      a,1
        ld      (p126_ngs_image_active),a
        xor     a
        ld      (p126_ngs_image_received),a
        ld      (p126_ngs_bios_image_ready),a
        ld      hl,p126_ngs_image_id
        ld      (hl),1
        inc     hl
        ld      (hl),0
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
        ld      a,(#C00C)
        cp      #0A
        jp      nz,.image_fragment_bad
        ld      a,(#C00D)
        cp      #20
        jp      nz,.image_fragment_bad
        ld      a,(#C012)
        cp      1
        jp      nz,.image_fragment_bad
        ld      a,(#C013)
        or      a
        jp      nz,.image_fragment_bad
        ld      a,(#C014)
        or      a
        jp      nz,.image_fragment_bad
        ld      a,(#C015)
        or      a
        jp      nz,.image_fragment_bad
        ld      a,(#C016)
        cp      1
        jp      nz,.image_fragment_bad
        ld      a,(#C017)
        or      a
        jp      nz,.image_fragment_bad
        ld      a,(#C018)
        or      a
        jp      nz,.image_fragment_bad
        ld      a,(#C019)
        cp      #20
        jp      nz,.image_fragment_bad
        ld      a,(#C01A)
        or      a
        jp      nz,.image_fragment_bad
        ld      a,(#C01B)
        or      a
        jp      nz,.image_fragment_bad

        ; Copy 8192 bytes from the validated page-42 frame payload to
        ; physical SYSBIOS page 10h, offset 0000h. Alternate WIN3 mapping
        ; per byte; resident code and stack are never mapped out.
        ld      hl,#C01C
        ld      de,#C000
        ld      bc,P126_IMAGE_SYSBIOS_SIZE
.image_copy_loop:
        ld      a,#21                  ; page 42h RRCA selector
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(hl)
        push    af
        ld      a,#08                  ; page 10h RRCA selector
        out     (P126_NGS_MPAGEX_PORT),a
        pop     af
        ld      (de),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.image_copy_loop

        ; Verify every installed byte against the still-preserved DMA frame.
        ; The receive-frame CRC proves the staging data; this second pass proves
        ; that the physical SYSBIOS page-10 copy is byte-for-byte identical.
        ld      hl,#C01C
        ld      de,#C000
        ld      bc,P126_IMAGE_SYSBIOS_SIZE
        ld      (p126_ngs_image_verify_count),bc
.image_verify_loop:
        ld      a,#21                  ; page 42h RRCA selector
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(hl)
        ld      (p126_ngs_image_verify_byte),a
        ld      a,#08                  ; page 10h RRCA selector
        out     (P126_NGS_MPAGEX_PORT),a
        ld      a,(de)
        ld      b,a
        ld      a,(p126_ngs_image_verify_byte)
        cp      b
        jr      nz,.image_verify_bad
        inc     hl
        inc     de
        ld      bc,(p126_ngs_image_verify_count)
        dec     bc
        ld      (p126_ngs_image_verify_count),bc
        ld      a,b
        or      c
        jr      nz,.image_verify_loop

        ; Restore the production DMA page mapping for subsequent IPC frames.
        ld      a,#21
        out     (P126_NGS_MPAGEX_PORT),a
        ld      hl,p126_ngs_image_verify_ok_log
        call    p126_ngs_ipc_log
        ld      a,1
        ld      (p126_ngs_image_received),a
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      a,1
        or      a
        ret
.image_verify_bad:
        ld      a,#21                  ; leave WIN3 on the production DMA page
        out     (P126_NGS_MPAGEX_PORT),a
        jp      .image_fragment_bad
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
        jr      z,.image_finish_bad
        ld      a,(p126_ngs_image_received)
        or      a
        jr      z,.image_finish_bad
        ld      a,(#C00C)
        cp      2
        jr      nz,.image_finish_bad
        ld      a,(#C012)
        cp      1
        jr      nz,.image_finish_bad
        ld      a,(#C013)
        or      a
        jr      nz,.image_finish_bad
        xor     a
        ld      (p126_ngs_image_active),a
        ld      a,1
        ld      (p126_ngs_bios_image_ready),a
        ld      hl,p126_ngs_image_installed_log
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

p126_ngs_image_active:       db 0
p126_ngs_image_received:     db 0
p126_ngs_bios_image_ready:   db 0
p126_ngs_image_id:           dw 0
p126_ngs_image_verify_count: dw 0
p126_ngs_image_verify_byte:  db 0
p126_ngs_image_begin_log:    db "[NGS] SYSBIOS IMAGE BEGIN",13,10,0
p126_ngs_image_fragment_log: db "[NGS] SYSBIOS IMAGE FRAGMENT",13,10,0
p126_ngs_image_finish_log:   db "[NGS] SYSBIOS IMAGE FINISH",13,10,0
p126_ngs_image_installed_log: db "[NGS] SYSBIOS IMAGE INSTALLED AT PAGE 10",13,10,0
p126_ngs_image_verify_ok_log: db "[NGS] SYSBIOS PAGE 10 READBACK MATCH",13,10,0
p126_ngs_image_begin_rejected_log: db "[NGS] SYSBIOS IMAGE BEGIN REJECTED",13,10,0
p126_ngs_image_fragment_rejected_log: db "[NGS] SYSBIOS IMAGE FRAGMENT REJECTED",13,10,0
p126_ngs_image_finish_rejected_log: db "[NGS] SYSBIOS IMAGE FINISH REJECTED",13,10,0

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
p126_ngs_ipc_log_dma_e0:          db "[NGS] DMA E0 RECEIVED",13,10,0
p126_ngs_ipc_log_dma_cfg_begin:   db "[NGS] DMA CONFIG BEGIN",13,10,0
p126_ngs_ipc_log_dma_armed:       db "[NGS] DMA ARMED",13,10,0
p126_ngs_ipc_log_dma_ready:       db "[NGS] DMA READY / CBIT RELEASED",13,10,0
p126_ngs_ipc_log_dma_host_end:    db "[NGS] DMA HOST END DETECTED",13,10,0
p126_ngs_ipc_log_dma_timeout:     db "[NGS] DMA WAIT TIMEOUT",13,10,0
p126_ngs_ipc_log_bad_length:      db "[NGS] DMA FRAME LENGTH INVALID",13,10,0
p126_ngs_ipc_log_dma_stopped:     db "[NGS] DMA STOPPED",13,10,0
p126_ngs_ipc_log_dma_page42_premapped: db "[NGS] DMA PRODUCTION PAGE 42 PRE-MAPPED",13,10,0
p126_ngs_ipc_log_dma_page42_mapped: db "[NGS] DMA PRODUCTION PAGE 42 STILL MAPPED",13,10,0
p126_ngs_ipc_log_dma_end:         db "[NGS] DMA END RECEIVED",13,10,0
p126_ngs_ipc_log_dma_addr:        db "[NGS] DMA ADDR READBACK=",0
p126_ngs_ipc_log_rx_header:       db "[NGS] DMA RX HEADER=",0
p126_ngs_ipc_log_frame_valid:     db "[NGS] DMA FRAME VALID",13,10,0
p126_ngs_ipc_log_frame_rejected:  db "[NGS] DMA FRAME REJECTED STATUS=",0
p126_ngs_ipc_log_dma_rx_request: db "[NGS] DMA RX MAX FRAME REQUESTED",13,10,0
p126_ngs_ipc_log_dma_rx_armed:   db "[NGS] DMA RX MAX FRAME ARMED",13,10,0
p126_ngs_ipc_log_dma_rx_end:     db "[NGS] DMA RX MAX FRAME HOST END",13,10,0
p126_ngs_ipc_log_dma_rx_addr:    db "[NGS] DMA RX ADDR READBACK=",0
p126_ngs_ipc_log_dma_rx_timeout: db "[NGS] DMA RX MAX FRAME TIMEOUT",13,10,0
p126_ngs_ipc_log_dma_rx_length_bad: db "[NGS] DMA RX MAX FRAME LENGTH INVALID",13,10,0

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
