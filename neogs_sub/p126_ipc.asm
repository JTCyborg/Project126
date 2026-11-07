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
        push    ix
        pop     de
        ex      de,hl
        ld      hl,#FFFF
        ld      b,16
.p126_ngs_frame_crc_head:
        ld      a,(de)
        inc     de
        call    p126_ngs_ipc_crc16_update
        djnz    .p126_ngs_frame_crc_head
        push    de
        ld      ix,(p126_ngs_ipc_frame_ptr)
        ld      e,(ix+12)
        ld      d,(ix+13)
        pop     hl
        push    hl
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
; carry set/A=status. Uses physical DMA page 42h (108000h), then maps it
; into WIN3. The callable dispatcher below routes E0h to this endpoint.
; -------------------------------------------------------------------------
P126_NGS_DMA_MOD      EQU #1B
P126_NGS_DMA_HAD      EQU #1C
P126_NGS_DMA_MAD      EQU #1D
P126_NGS_DMA_LAD      EQU #1E
P126_NGS_DMA_CST      EQU #1F
P126_NGS_ZXSTAT       EQU #04
P126_NGS_CLRCBIT      EQU #05
P126_NGS_WIN3_PORT    EQU #23
P126_NGS_DMA_TARGET_PAGE     EQU #42
P126_NGS_DMA_TIMEOUT  EQU #FFFF

p126_ngs_ipc_dma_receive_frame::
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
        ld      hl,p126_ngs_ipc_log_dma_ready
        call    p126_ngs_ipc_log
        xor     a
        out     (P126_NGS_CLRCBIT),a

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
        xor     a
        out     (P126_NGS_DMA_CST),a
        out     (P126_NGS_CLRCBIT),a
        ld      a,P126_STATUS_TIMEOUT
        scf
        ret

.p126_ngs_dma_host_end:
        ; FFh/CBIT marks the end of the host write. Stop DMA and map the
        ; staging page, but keep CBIT asserted until validation is complete.
        xor     a
        out     (P126_NGS_DMA_CST),a
        ld      a,P126_NGS_DMA_TARGET_PAGE
        out     (P126_NGS_WIN3_PORT),a
        ld      hl,p126_ngs_ipc_log_dma_end
        call    p126_ngs_ipc_log

        ; Derive exact frame size from the fixed header's payload length.
        ld      a,(#C00C)
        ld      e,a
        ld      a,(#C00D)
        ld      d,a
        ld      hl,P126_IPC_HEADER_SIZE
        add     hl,de
        ; Reject any declared frame larger than the 16 KiB DMA page.
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
        ld      bc,(p126_ngs_ipc_rx_size)
        ld      hl,#C000
        call    p126_ngs_ipc_validate_frame
        jr      c,.p126_ngs_dma_validation_failed

        ; Validation succeeded: only now acknowledge completion to ATM.
        xor     a
        out     (P126_NGS_CLRCBIT),a
        ld      hl,#C000
        ld      bc,(p126_ngs_ipc_rx_size)
        xor     a
        ret

.p126_ngs_dma_validation_failed:
        ; Preserve the ABI status and carry while releasing the host.
        push    af
        xor     a
        out     (P126_NGS_CLRCBIT),a
        pop     af
        scf
        ret

.p126_ngs_dma_bad_length:
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
;      carry clear/Z=0 with HL=#C000, BC=size on a valid E0h frame;
;      carry set/A=status for a rejected command or receive failure.
; The caller owns the resident main loop and must keep its stack/code outside
; WIN3. E0h is consumed from ZXCMD while CBIT stays asserted until DMA is armed.
; -------------------------------------------------------------------------
P126_NGS_ZXCMD       EQU #01

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
p126_ngs_ipc_log_dma_e0:    db "[NGS] DMA E0 RECEIVED",13,10,0
p126_ngs_ipc_log_dma_ready: db "[NGS] DMA READY",13,10,0
p126_ngs_ipc_log_dma_end:   db "[NGS] DMA END RECEIVED",13,10,0

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
