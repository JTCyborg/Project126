; =========================================================================
; PROJECT126 — ATM Turbo 2+ / NeoGS host-side IPC driver
; Version: P126_ATM_IPC v0.1.0
;
; This is ATM Z80 code. It runs on the 7 MHz host CPU.
; NeoGS is an independent Z80 and has its own private debug port #EF.
;
; The implementation follows the proven Project125 host transport v2
; handshake semantics. It intentionally contains no NeoGS-local IN/OUT
; and does not program DMA_MOD/HAD/MAD/LAD/CST from the ATM side.
; =========================================================================

        INCLUDE "atm_host/neogs_ipc.inc"

; -------------------------------------------------------------------------
; Read the current hardware handshake state.
; OUT: A=status; p126_ipc_last_status updated.
; -------------------------------------------------------------------------
p126_ipc_read_status::
        in      a, (P126_GSSTAT)
        ld      (p126_ipc_last_status), a
        ret

; -------------------------------------------------------------------------
; Wait routines. Every wait is bounded by P126_IPC_TIMEOUT.
; OUT: Carry clear on requested state; carry set on timeout.
;      A=last sampled GSSTAT. BC is clobbered.
; -------------------------------------------------------------------------
p126_ipc_wait_cbit_clear::
        ld      bc, P126_IPC_TIMEOUT
.p126_cbit_loop:
        call    p126_ipc_read_status
        bit     P126_CBIT, a
        jr      z, .p126_cbit_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .p126_cbit_loop
        ld      a, (p126_ipc_last_status)
        scf
        ret
.p126_cbit_ready:
        ld      a, (p126_ipc_last_status)
        or      a
        ret

p126_ipc_wait_dbit_clear::
        ld      bc, P126_IPC_TIMEOUT
.p126_dbit_clear_loop:
        call    p126_ipc_read_status
        bit     P126_DBIT, a
        jr      z, .p126_dbit_clear_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .p126_dbit_clear_loop
        ld      a, (p126_ipc_last_status)
        scf
        ret
.p126_dbit_clear_ready:
        ld      a, (p126_ipc_last_status)
        or      a
        ret

p126_ipc_wait_dbit_set::
        ld      bc, P126_IPC_TIMEOUT
.p126_dbit_set_loop:
        call    p126_ipc_read_status
        bit     P126_DBIT, a
        jr      nz, .p126_dbit_set_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .p126_dbit_set_loop
        ld      a, (p126_ipc_last_status)
        scf
        ret
.p126_dbit_set_ready:
        ld      a, (p126_ipc_last_status)
        or      a
        ret

; -------------------------------------------------------------------------
; Send one command through GSCOM.
; IN : A=command.
; OUT: Carry clear after NeoGS clears CBIT; carry set on timeout.
; -------------------------------------------------------------------------
p126_ipc_send_command::
        ld      (p126_ipc_tx_byte), a
        ld      a, (p126_ipc_tx_byte)
        out     (P126_GSCOM), a
        jp      p126_ipc_wait_cbit_clear

; -------------------------------------------------------------------------
; Preload one data byte before issuing a command.
; This ordering is required by the stock GS105a #13/#14 command ABI.
; IN : A=argument.
; OUT: Carry clear after GSDAT write; carry set if the data slot is busy.
; -------------------------------------------------------------------------
p126_ipc_send_argument::
        ld      (p126_ipc_tx_byte), a
        call    p126_ipc_wait_dbit_clear
        ret     c
        ld      a, (p126_ipc_tx_byte)
        out     (P126_GSDAT), a
        or      a
        ret

; -------------------------------------------------------------------------
; Send a data byte and wait until NeoGS consumes it (DBIT clears).
; IN : A=data.
; OUT: Carry clear on consumption; carry set on timeout.
; -------------------------------------------------------------------------
p126_ipc_send_byte::
        ld      (p126_ipc_tx_byte), a
        call    p126_ipc_wait_dbit_clear
        ret     c
        ld      a, (p126_ipc_tx_byte)
        out     (P126_GSDAT), a
        jp      p126_ipc_wait_dbit_clear

; -------------------------------------------------------------------------
; Receive one byte published by NeoGS.
; OUT: A=data; carry clear. Carry set on timeout.
; Reading GSDAT acknowledges the byte and clears DBIT in the host view.
; -------------------------------------------------------------------------
p126_ipc_receive_byte::
        call    p126_ipc_wait_dbit_set
        ret     c
        in      a, (P126_GSDAT)
        ld      (p126_ipc_rx_byte), a
        or      a
        ret

; -------------------------------------------------------------------------
; CRC-16/CCITT-FALSE byte update for the shared P126 DMA/IPC frame ABI.
; IN : HL=current CRC, A=next byte.
; OUT: HL=updated CRC. BC and DE are preserved.
; The caller initializes HL to #FFFF and processes header[0..15]
; followed by exactly payload_length bytes.
; -------------------------------------------------------------------------
p126_ipc_crc16_update::
        push    bc
        xor     h
        ld      h, a
        ld      b, 8
.p126_crc_bit:
        add     hl, hl
        jr      nc, .p126_crc_no_xor
        ld      a, h
        xor     #10
        ld      h, a
        ld      a, l
        xor     #21
        ld      l, a
.p126_crc_no_xor:
        djnz    .p126_crc_bit
        pop     bc
        ret


; Validate ABI 1.0 complete frame.
; IN: HL=frame pointer, BC=actual size. OUT: carry clear/A=0 or carry set/A=status.
; Clobbers AF,BC,DE,HL,IX. Scratch is non-reentrant.
p126_ipc_validate_frame::
        ld      (p126_ipc_frame_ptr),hl
        ld      (p126_ipc_frame_size),bc
        ld      a,b
        or      a
        jr      nz,.p126_frame_min_ok
        ld      a,c
        cp      P126_IPC_HEADER_SIZE
        jp      c,.p126_frame_bad
.p126_frame_min_ok:
        push    hl
        pop     ix
        ld      a,(ix+0)
        cp      'P'
        jp      nz,.p126_frame_magic
        ld      a,(ix+1)
        cp      '1'
        jp      nz,.p126_frame_magic
        ld      a,(ix+2)
        cp      '2'
        jp      nz,.p126_frame_magic
        ld      a,(ix+3)
        cp      '6'
        jp      nz,.p126_frame_magic
        ld      a,(ix+4)
        cp      P126_IPC_MAJOR
        jp      nz,.p126_frame_version
        ld      a,(ix+5)
        cp      P126_IPC_MINOR
        jp      nz,.p126_frame_version
        ld      a,(ix+6)
        cp      P126_MSG_REQUEST
        jr      z,.p126_frame_type
        cp      P126_MSG_RESPONSE
        jr      z,.p126_frame_type
        cp      P126_MSG_EVENT
        jr      z,.p126_frame_type
        cp      P126_MSG_CANCEL
        jp      nz,.p126_frame_bad
.p126_frame_type:
        ld      a,(ix+9)
        and     #F8
        jp      nz,.p126_frame_bad
        ld      l,(ix+12)
        ld      h,(ix+13)
        ld      de,P126_IPC_HEADER_SIZE
        add     hl,de
        ld      de,(p126_ipc_frame_size)
        or      a
        sbc     hl,de
        jp      nz,.p126_frame_bad
        ; CRC header and payload in one pass.
        ; Keep DE pointing at the frame while HL holds the CRC accumulator.
        ; EX DE,HL here would move the frame pointer into HL and then lose it
        ; when HL is initialized to FFFFh, causing CRC to read from address 0000h.
        push    ix
        pop     de
        ld      hl,#FFFF
        ld      b,16
.p126_frame_crc_head:
        ld      a,(de)
        inc     de
        call    p126_ipc_crc16_update
        djnz    .p126_frame_crc_head
        push    de
        ld      ix,(p126_ipc_frame_ptr)
        ld      e,(ix+12)
        ld      d,(ix+13)
        pop     hl
        push    hl
        pop     ix
.p126_frame_crc_data:
        ld      a,d
        or      e
        jr      z,.p126_frame_crc_compare
        ld      a,(ix+0)
        inc     ix
        call    p126_ipc_crc16_update
        dec     de
        jr      .p126_frame_crc_data
.p126_frame_crc_compare:
        ld      (p126_ipc_crc_work),hl
        ld      ix,(p126_ipc_frame_ptr)
        ld      a,(ix+16)
        ld      e,a
        ld      a,(ix+17)
        ld      d,a
        ld      hl,(p126_ipc_crc_work)
        or      a
        sbc     hl,de
        jr      nz,.p126_frame_crc_bad
        xor     a
        ret
.p126_frame_magic:
        ld      a,P126_STATUS_BAD_MAGIC
        scf
        ret
.p126_frame_version:
        ld      a,P126_STATUS_BAD_VERSION
        scf
        ret
.p126_frame_crc_bad:
        ld      a,P126_STATUS_CRC_ERROR
        scf
        ret
.p126_frame_bad:
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret
p126_ipc_frame_ptr: dw 0
p126_ipc_frame_size: dw 0
p126_ipc_crc_work: dw 0

; Standard CRC-16/CCITT-FALSE regression vector.
; OUT: Carry clear and HL=#29B1 on pass; Carry set on failure.
p126_ipc_crc16_selftest::
        push    bc
        push    de
        ld      hl, #FFFF
        ld      de, p126_ipc_crc16_test_vector
        ld      b, 9
.p126_crc_test_loop:
        ld      a, (de)
        inc     de
        call    p126_ipc_crc16_update
        djnz    .p126_crc_test_loop
        ld      de, #29B1
        or      a
        sbc     hl, de
        jr      nz, .p126_crc_test_failed
        pop     de
        pop     bc
        ld      hl, #29B1
        or      a
        ret
.p126_crc_test_failed:
        pop     de
        pop     bc
        scf
        ret

p126_ipc_crc16_test_vector:
        db "123456789"

; -------------------------------------------------------------------------
; Emit a build/runtime identity to ATM's independent debug port #EF.
; Preserves AF, BC and HL.
; -------------------------------------------------------------------------
p126_ipc_emit_version::
        push    af
        push    bc
        push    hl
        ld      hl, p126_ipc_version_text
        ld      bc, #00EF
.p126_version_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .p126_version_done
        out     (c), a
        jr      .p126_version_loop
.p126_version_done:
        pop     hl
        pop     bc
        pop     af
        ret

; Driver state is private to this module. Callers must not modify it.
p126_ipc_last_status: db 0
p126_ipc_tx_byte:     db 0
p126_ipc_rx_byte:     db 0

p126_ipc_version_text:
        db "[P126 ATM_IPC v0.2.0]", 13, 10, 0

; -------------------------------------------------------------------------
; Send one complete ATM -> NeoGS ABI 1.0 frame through the ZX DMA aperture.
; IN: HL=frame, BC=exact frame size (18..16384).
; OUT: carry clear/A=0 only after NeoGS closes DMA and acknowledges #FF.
; Clobbers AF,BC,DE,HL. Leaves interrupts disabled during/after transfer.
; Source buffer remains caller-owned and must remain stable until return.
; -------------------------------------------------------------------------
P126_IPC_DMA_WINDOW EQU #0000
P126_IPC_DMA_END    EQU #FF

p126_ipc_dma_send_frame::
        ld      a,1
        ld      (p126_ipc_dma_stage),a
        ld      (p126_ipc_dma_source),hl
        ld      (p126_ipc_dma_size),bc
        call    p126_ipc_validate_frame
        jr      nc,.p126_dma_frame_valid
        ld      (p126_ipc_dma_error),a
        scf
        ret
.p126_dma_frame_valid:
        xor     a
        ld      (p126_ipc_dma_error),a

        ld      a,2
        ld      (p126_ipc_dma_stage),a
        ld      bc,(p126_ipc_dma_size)
        ld      a,b
        cp      #40
        jr      c,.p126_dma_size_valid
        jp      nz,.p126_dma_bad_size
        ld      a,c
        or      a
        jr      z,.p126_dma_size_valid
        jp      .p126_dma_bad_size

.p126_dma_size_valid:
        ld      a,3
        ld      (p126_ipc_dma_stage),a
        ld      a,P126_CMD_HOST_FRAME
        call    p126_ipc_send_command
        ret     c

        ld      a,4
        ld      (p126_ipc_dma_stage),a
        ld      hl,(p126_ipc_dma_source)
        ld      bc,(p126_ipc_dma_size)
        ld      de,P126_IPC_DMA_WINDOW
        di
        ldir

        ld      a,5
        ld      (p126_ipc_dma_stage),a
        ld      a,P126_IPC_DMA_END
        out     (P126_GSCOM),a
        call    p126_ipc_wait_cbit_clear
        ret     c
        xor     a
        ld      (p126_ipc_dma_stage),a
        ret

.p126_dma_bad_size:
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret

p126_ipc_dma_source: dw 0
p126_ipc_dma_size:   dw 0
; 0=success/not started, 1=local frame validation, 2=DMA size,
; 3=E0/READY handshake, 4=payload copy, 5=FF/completion acknowledgement.
p126_ipc_dma_stage:  db 0

p126_ipc_dma_error: db 0
