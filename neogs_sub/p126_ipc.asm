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
; OUT: carry clear/A=0, HL=#5000 and BC=derived frame size; otherwise
; carry set/A=status. Diagnostic DMA destination is physical 00D000h on
; page 03h, matching Project125. Production page-42 staging is not yet tested.
; -------------------------------------------------------------------------
P126_NGS_DMA_MOD      EQU #1B
P126_NGS_DMA_HAD      EQU #1C
P126_NGS_DMA_MAD      EQU #1D
P126_NGS_DMA_LAD      EQU #1E
P126_NGS_DMA_CST      EQU #1F
P126_NGS_ZXSTAT       EQU #04
P126_NGS_CLRCBIT      EQU #05
P126_NGS_PG1_PORT     EQU #21
; Project125 hardware-parity diagnostic locations. WIN1 is physical page 03;
; its operational stack is at logical 7FFEh (physical offset 3FFEh). The two
; 274-byte smoke buffers at logical 5000h and 6000h (physical D000h and E000h) do not overlap that stack.
; These are diagnostic carve-outs only; production ABI staging remains page 42h.
P126_NGS_DMA_DIAG_PAGE        EQU #03
P126_NGS_DMA_TIMEOUT          EQU #FFFF

p126_ngs_ipc_dma_receive_frame::
        ; Match the proven Project125 DMA setup ordering: map the physical
        ; destination page into a CPU window before arming ZX DMA. Resident
        ; code, data and stack remain in WIN0-WIN2; WIN1 is only the aperture.
        ld      a,P126_NGS_DMA_DIAG_PAGE
        out     (P126_NGS_PG1_PORT),a
        ld      hl,p126_ngs_ipc_log_dma_page_premapped
        call    p126_ngs_ipc_log
        ld      hl,p126_ngs_ipc_log_dma_cfg_begin
        call    p126_ngs_ipc_log
        ld      a,1
        out     (P126_NGS_DMA_MOD),a
        xor     a
        out     (P126_NGS_DMA_HAD),a
        ld      a,#D0
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

        ld      bc,P126_NGS_DMA_TIMEOUT
.p126_ngs_dma_wait_end:
        in      a,(P126_NGS_ZXSTAT)
        bit     0,a
        jr      nz,.p126_ngs_dma_host_end
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_ngs_dma_wait_end
        ; Always stop DMA before releasing the command on timeout.
        ld      hl,p126_ngs_ipc_log_dma_timeout
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_DMA_CST),a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_TIMEOUT
        scf
        ret

.p126_ngs_dma_host_end:
        ; FFh/CBIT marks the end of the host write. Stop DMA and map the
        ; staging page, but keep CBIT asserted until validation is complete.
        ld      hl,p126_ngs_ipc_log_dma_host_end
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_DMA_CST),a
        ld      hl,p126_ngs_ipc_log_dma_stopped
        call    p126_ngs_ipc_log

        ; Read back DMA address registers after stop. For the 274-byte smoke
        ; frame, D000h + 0112h must be visible as 00D112h.
        ld      hl,p126_ngs_ipc_log_dma_addr
        call    p126_ngs_ipc_log
        in      a,(P126_NGS_DMA_HAD)
        call    p126_ngs_ipc_log_hex_byte_inline
        in      a,(P126_NGS_DMA_MAD)
        call    p126_ngs_ipc_log_hex_byte_inline
        in      a,(P126_NGS_DMA_LAD)
        call    p126_ngs_ipc_log_hex_byte_inline
        call    p126_ngs_ipc_log_crlf

        ; WIN1 remains mapped to physical page 03. The DMA destination is
        ; physical D000h / logical 5000h (the Project125-proven host-to-NeoGS diagnostic address).
        ld      hl,p126_ngs_ipc_log_dma_page_mapped
        call    p126_ngs_ipc_log
        ld      hl,p126_ngs_ipc_log_dma_end
        call    p126_ngs_ipc_log

        ; Inspect the Project125 parity destination: physical D000h at WIN1 logical 5000h.
        ld      hl,p126_ngs_ipc_log_rx_header
        call    p126_ngs_ipc_log
        ld      ix,#5000
        ld      b,16
.p126_ngs_rx_dump_loop:
        ld      a,(ix+0)
        call    p126_ngs_ipc_log_hex_byte_inline
        inc     ix
        djnz    .p126_ngs_rx_dump_loop
        call    p126_ngs_ipc_log_crlf

        ; Derive exact frame size from the fixed header's payload length.
        ld      a,(#500C)
        ld      e,a
        ld      a,(#500D)
        ld      d,a
        ld      hl,P126_IPC_HEADER_SIZE
        add     hl,de
        ; Physical diagnostic target starts at D000h (WIN1 logical 5000h); reject a page crossing.
        ld      a,h
        cp      #30
        jr      c,.p126_ngs_dma_size_ok
        jp      nz,.p126_ngs_dma_bad_length
        ld      a,l
        or      a
        jr      z,.p126_ngs_dma_size_ok
        jp      .p126_ngs_dma_bad_length
.p126_ngs_dma_size_ok:
        ld      (p126_ngs_ipc_rx_size),hl
        ld      bc,(p126_ngs_ipc_rx_size)
        ld      hl,#5000
        call    p126_ngs_ipc_validate_frame
        jr      c,.p126_ngs_dma_validation_failed
        ld      hl,p126_ngs_ipc_log_frame_valid
        call    p126_ngs_ipc_log

        ; Validation succeeded: only now acknowledge completion to ATM.
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      hl,#5000
        ld      bc,(p126_ngs_ipc_rx_size)
        xor     a
        ret

.p126_ngs_dma_validation_failed:
        ; Preserve the ABI status and carry while releasing the host.
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
; -------------------------------------------------------------------------
; Resident command-dispatch entry, one bounded unit of work.
; OUT: carry clear/Z=1/A=0 when no command is pending;
;      carry clear/Z=0 with HL=#5000, BC=size on a valid E0h frame;
;      carry set/A=status for a rejected command or receive failure.
; The caller owns the resident main loop and must keep its stack/code outside
; WIN1. E0h is consumed from ZXCMD while CBIT stays asserted until DMA is armed.
; -------------------------------------------------------------------------
P126_NGS_ZXCMD       EQU #01

; Reverse DMA diagnostic response for ABI command E1h (NGS_FRAME).
; Use the Project125 reference source address: physical 00E000h at
; WIN1 logical 6000h. This is diagnostic only.
p126_ngs_ipc_dma_send_test_frame::
        ld      a,P126_NGS_DMA_DIAG_PAGE
        out     (P126_NGS_PG1_PORT),a
        ld      hl,p126_ngs_ipc_dma_test_header
        ld      de,#6000
        ld      bc,P126_IPC_HEADER_SIZE
        ldir
        ld      hl,#6000+P126_IPC_HEADER_SIZE
        xor     a
        ld      b,0
.ngs_fill:
        ld      (hl),a
        inc     hl
        inc     a
        djnz    .ngs_fill
        ; CRC covers header[0..15] followed by payload[18..273].
        ld      hl,#FFFF
        ld      de,#6000
        ld      b,16
.ngs_crc_header:
        ld      a,(de)
        inc     de
        call    p126_ngs_ipc_crc16_update
        djnz    .ngs_crc_header
        inc     de
        inc     de
        ld      b,0
.ngs_crc_payload:
        ld      a,(de)
        inc     de
        call    p126_ngs_ipc_crc16_update
        djnz    .ngs_crc_payload
        ld      (#6000+P126_IPC_OFF_CRC),hl
        ld      a,1
        out     (P126_NGS_DMA_MOD),a
        xor     a
        out     (P126_NGS_DMA_HAD),a
        ld      a,#E0
        out     (P126_NGS_DMA_MAD),a
        xor     a
        out     (P126_NGS_DMA_LAD),a
        ld      a,#80
        out     (P126_NGS_DMA_CST),a
        ld      hl,p126_ngs_ipc_log_dma_rx_armed
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      bc,P126_NGS_DMA_TIMEOUT
.ngs_wait_end:
        in      a,(P126_NGS_ZXSTAT)
        bit     0,a
        jr      nz,.ngs_host_end
        dec     bc
        ld      a,b
        or      c
        jr      nz,.ngs_wait_end
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
        xor     a
        out     (P126_NGS_CLRCBIT),a
        xor     a
        ret

p126_ngs_ipc_dma_test_header:
        db 'P','1','2','6'
        db P126_IPC_MAJOR,P126_IPC_MINOR
        db P126_MSG_RESPONSE,P126_SERVICE_DIAGNOSTICS,P126_OP_DIAGNOSTIC,0
        db #00,#00
        db #00,#01
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

        ; Unknown/unimplemented command: release the doorbell so the host
        ; cannot remain blocked, and report a defined ABI error.
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
        ld      a,1
        or      a
        ret


.p126_ngs_dispatch_ngs_frame:
        ld      hl,p126_ngs_ipc_log_dma_rx_request
        call    p126_ngs_ipc_log
        call    p126_ngs_ipc_dma_send_test_frame
        ret

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
p126_ngs_ipc_log_dma_page_premapped: db "[NGS] DMA DIAG PAGE 03 PRE-MAPPED",13,10,0
p126_ngs_ipc_log_dma_page_mapped: db "[NGS] DMA DIAG PAGE 03 STILL MAPPED",13,10,0
p126_ngs_ipc_log_dma_end:         db "[NGS] DMA END RECEIVED",13,10,0
p126_ngs_ipc_log_dma_addr:        db "[NGS] DMA ADDR READBACK=",0
p126_ngs_ipc_log_rx_header:       db "[NGS] DMA RX HEADER=",0
p126_ngs_ipc_log_frame_valid:     db "[NGS] DMA FRAME VALID",13,10,0
p126_ngs_ipc_log_frame_rejected:  db "[NGS] DMA FRAME REJECTED STATUS=",0
p126_ngs_ipc_log_dma_rx_request: db "[NGS] DMA RX TEST REQUESTED",13,10,0
p126_ngs_ipc_log_dma_rx_armed:   db "[NGS] DMA RX TEST ARMED",13,10,0
p126_ngs_ipc_log_dma_rx_end:     db "[NGS] DMA RX TEST HOST END",13,10,0
p126_ngs_ipc_log_dma_rx_timeout: db "[NGS] DMA RX TEST TIMEOUT",13,10,0

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
