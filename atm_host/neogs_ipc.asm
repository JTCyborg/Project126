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

; Long completion watchdog for DMA frames whose service handler performs
; post-receive work (for example installing an 8 KiB BIOS image).
; Matches Project125's eight independent #FFFF polling windows.
p126_ipc_wait_cbit_clear_dma::
        ld      d,8
.p126_dma_cbit_outer:
        ld      bc,#FFFF
.p126_dma_cbit_inner:
        call    p126_ipc_read_status
        bit     P126_CBIT,a
        jr      z,.p126_dma_cbit_ready
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_dma_cbit_inner
        dec     d
        jr      nz,.p126_dma_cbit_outer
        ld      a,(p126_ipc_last_status)
        scf
        ret
.p126_dma_cbit_ready:
        ld      a,(p126_ipc_last_status)
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
        inc     de
        inc     de
        push    de
        ld      ix,(p126_ipc_frame_ptr)
        ld      e,(ix+12)
        ld      d,(ix+13)
        ; Restore the saved payload pointer directly into IX.
        ; Do not pop it into HL: HL is the live CRC accumulator and must
        ; survive the transition from header processing to payload processing.
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
        ; Capture both values before emitting diagnostics. This lets the next
        ; hardware log distinguish a bad CRC calculation from a bad frame
        ; write/byte order without involving the NeoGS DMA receiver.
        ld      (p126_ipc_crc_work),hl
        ld      ix,(p126_ipc_frame_ptr)
        ld      a,(ix+16)
        ld      e,a
        ld      a,(ix+17)
        ld      d,a
        ld      (p126_ipc_crc_expected),de
        ld      hl,p126_ipc_log_crc_calculated
        call    p126_ipc_debug_string
        ld      hl,(p126_ipc_crc_work)
        ld      a,h
        call    p126_ipc_debug_hex_byte
        ld      a,l
        call    p126_ipc_debug_hex_byte
        ld      hl,p126_ipc_log_crc_expected
        call    p126_ipc_debug_string
        ld      hl,(p126_ipc_crc_expected)
        ld      a,h
        call    p126_ipc_debug_hex_byte
        ld      a,l
        call    p126_ipc_debug_hex_byte
        ld      bc,#00EF
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a
        ld      hl,(p126_ipc_crc_work)
        ld      de,(p126_ipc_crc_expected)
        or      a
        sbc     hl,de
        jp      nz,.p126_frame_crc_bad
        xor     a
        ret
.p126_frame_magic:
        ; Preserve the validator result while reporting the actual source
        ; address and four bytes. This distinguishes a bad header from a
        ; wrong ATM page mapping at C000h before DMA is armed.
        push    af
        push    hl
        push    de
        push    ix
        ld      hl,p126_ipc_log_bad_magic_ptr
        call    p126_ipc_debug_string
        ld      hl,(p126_ipc_frame_ptr)
        ld      a,h
        call    p126_ipc_debug_hex_byte
        ld      a,l
        call    p126_ipc_debug_hex_byte
        ld      hl,p126_ipc_log_bad_magic_data
        call    p126_ipc_debug_string
        ld      ix,(p126_ipc_frame_ptr)
        ld      b,4
.p126_bad_magic_dump:
        ld      a,(ix+0)
        call    p126_ipc_debug_hex_byte
        inc     ix
        djnz    .p126_bad_magic_dump
        call    p126_ipc_debug_crlf
        pop     ix
        pop     de
        pop     hl
        pop     af
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
p126_ipc_crc_expected: dw 0

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
; Fast ATM->NeoGS transmit preflight.
; This is deliberately structural only: full CRC validation belongs to the
; receiving NeoGS endpoint, after the Project125-compatible DMA LDIR.
; IN: HL=frame pointer, BC=actual frame size.
; OUT: carry clear/A=0 or carry set/A=status.
; -------------------------------------------------------------------------
p126_ipc_validate_tx_frame::
        ld      (p126_ipc_frame_ptr),hl
        ld      (p126_ipc_frame_size),bc
        ld      a,b
        or      a
        jr      nz,.p126_tx_min_ok
        ld      a,c
        cp      P126_IPC_HEADER_SIZE
        jp      c,.p126_tx_bad
.p126_tx_min_ok:
        ld      a,b
        cp      #40
        jr      c,.p126_tx_size_ok
        jp      nz,.p126_tx_bad
        ld      a,c
        or      a
        jp      nz,.p126_tx_bad
.p126_tx_size_ok:
        push    hl
        pop     ix
        ld      a,(ix+0)
        cp      'P'
        jp      nz,.p126_tx_magic
        ld      a,(ix+1)
        cp      '1'
        jp      nz,.p126_tx_magic
        ld      a,(ix+2)
        cp      '2'
        jp      nz,.p126_tx_magic
        ld      a,(ix+3)
        cp      '6'
        jp      nz,.p126_tx_magic
        ld      a,(ix+4)
        cp      P126_IPC_MAJOR
        jp      nz,.p126_tx_version
        ld      a,(ix+5)
        cp      P126_IPC_MINOR
        jp      nz,.p126_tx_version
        ld      a,(ix+6)
        cp      P126_MSG_REQUEST
        jp      nz,.p126_tx_bad
        ld      a,(ix+9)
        and     #F8
        jp      nz,.p126_tx_bad
        ; actual_size must equal header_size + declared_payload_length.
        ld      l,(ix+12)
        ld      h,(ix+13)
        ld      de,P126_IPC_HEADER_SIZE
        add     hl,de
        ld      de,(p126_ipc_frame_size)
        or      a
        sbc     hl,de
        jp      nz,.p126_tx_bad
        xor     a
        ret
.p126_tx_magic:
        ld      a,P126_STATUS_BAD_MAGIC
        scf
        ret
.p126_tx_version:
        ld      a,P126_STATUS_BAD_VERSION
        scf
        ret
.p126_tx_bad:
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret

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
        ; Preserve the caller's frame pointer and length before any logger
        ; call, because the string writer advances HL.
        ld      a,1
        ld      (p126_ipc_dma_stage),a
        ld      (p126_ipc_dma_source),hl
        ld      (p126_ipc_dma_size),bc
        ld      hl,p126_ipc_log_dma_tx_begin
        call    p126_ipc_debug_string
        ld      hl,(p126_ipc_dma_source)
        ld      bc,(p126_ipc_dma_size)
        ; Match the proven Project125 host path: validate the frame envelope
        ; here, but do not spend the transfer startup path recalculating the
        ; complete 16 KiB CRC. The frame builder already wrote the CRC; NeoGS
        ; performs the authoritative full CRC check after DMA reception.
        call    p126_ipc_validate_tx_frame
        jr      nc,.p126_dma_frame_valid
        ld      (p126_ipc_dma_error),a
        push    af
        ld      hl,p126_ipc_log_dma_tx_validate_bad
        call    p126_ipc_debug_string
        pop     af
        ; Emit the exact rejected frame envelope so the first failing header
        ; field can be identified without guessing or weakening validation.
        call    p126_ipc_debug_hex_byte
        ld      hl,p126_ipc_log_dma_tx_bad_size
        call    p126_ipc_debug_string
        ld      hl,(p126_ipc_dma_size)
        ld      a,h
        call    p126_ipc_debug_hex_byte
        ld      a,l
        call    p126_ipc_debug_hex_byte
        ld      hl,p126_ipc_log_dma_tx_bad_header
        call    p126_ipc_debug_string
        ld      ix,(p126_ipc_dma_source)
        ld      b,P126_IPC_HEADER_SIZE
.p126_dma_bad_header_dump:
        ld      a,(ix+0)
        call    p126_ipc_debug_hex_byte
        inc     ix
        djnz    .p126_dma_bad_header_dump
        call    p126_ipc_debug_crlf
        scf
        ret
.p126_dma_frame_valid:
        ld      hl,p126_ipc_log_dma_tx_validate_ok
        call    p126_ipc_debug_string
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
        ld      hl,p126_ipc_log_dma_tx_e0
        call    p126_ipc_debug_string
        ld      a,P126_CMD_HOST_FRAME
        call    p126_ipc_send_command
        jr      nc,.p126_dma_e0_ack
        push    af
        ld      hl,p126_ipc_log_dma_tx_e0_timeout
        call    p126_ipc_debug_string
        pop     af
        scf
        ret
.p126_dma_e0_ack:
        ld      hl,p126_ipc_log_dma_tx_ready
        call    p126_ipc_debug_string

        ld      a,4
        ld      (p126_ipc_dma_stage),a
        di
        ld      hl,p126_ipc_log_dma_tx_copy_begin
        call    p126_ipc_debug_string
        ld      hl,(p126_ipc_dma_source)
        ld      bc,(p126_ipc_dma_size)
        ld      de,P126_IPC_DMA_WINDOW
        ldir
        ld      hl,p126_ipc_log_dma_tx_copy_done
        call    p126_ipc_debug_string

        ld      a,5
        ld      (p126_ipc_dma_stage),a
        ld      hl,p126_ipc_log_dma_tx_ff
        call    p126_ipc_debug_string
        ld      a,P126_IPC_DMA_END
        out     (P126_GSCOM),a
        call    p126_ipc_wait_cbit_clear_dma
        jr      nc,.p126_dma_ff_ack
        push    af
        ld      hl,p126_ipc_log_dma_tx_ff_timeout
        call    p126_ipc_debug_string
        pop     af
        scf
        ret
.p126_dma_ff_ack:
        ld      hl,p126_ipc_log_dma_tx_done
        call    p126_ipc_debug_string
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

; Reverse DMA diagnostic: NeoGS sends a CRC-protected maximum-size 16 KiB frame.
; The first memory read from the DMA aperture is discarded per hardware docs.
; Destination is the same 16 KiB page-0 buffer used by the forward test.
; Requires ROM visible at ATM 0000h..3FFFh during the reverse transfer.
P126_IPC_DMA_RX_TEST_SIZE EQU P126_IPC_MAX_FRAME_SIZE
P126_IPC_DMA_RX_BUFFER    EQU #C000
p126_ipc_dma_receive_test::
        ld      a,1
        ld      (p126_ipc_dma_rx_stage),a
        ld      hl,p126_ipc_log_dma_rx_begin
        call    p126_ipc_debug_string
        ld      a,P126_CMD_NGS_FRAME
        call    p126_ipc_send_command
        jr      nc,.rx_ready
        ld      a,1
        jp      .rx_failed
.rx_ready:
        ; Project125 disables IM1 before the first ROM-aperture read; an
        ; interrupt would fetch NeoGS DMA bytes at #0038h instead of ROM.
        di
        ld      hl,0
        ld      a,(hl)                  ; required discarded first read
        ld      hl,0
        ld      de,P126_IPC_DMA_RX_BUFFER
        ld      bc,P126_IPC_DMA_RX_TEST_SIZE
        ldir
        ld      hl,p126_ipc_log_dma_rx_copy_done
        call    p126_ipc_debug_string
        ld      a,P126_CMD_DMA_END
        call    p126_ipc_send_command
        jr      nc,.rx_end_ack
        ld      a,2
        jp      .rx_failed
.rx_end_ack:
        ld      a,2
        ld      (p126_ipc_dma_rx_stage),a
        ld      hl,P126_IPC_DMA_RX_BUFFER
        ld      bc,P126_IPC_DMA_RX_TEST_SIZE
        call    p126_ipc_validate_frame
        jr      nc,.rx_crc_ok
        ld      (p126_ipc_dma_rx_error),a
        ld      hl,p126_ipc_log_dma_rx_crc_bad
        call    p126_ipc_debug_string
        ld      a,(p126_ipc_dma_rx_error)
        call    p126_ipc_debug_hex_byte
        call    p126_ipc_debug_crlf
        scf
        ret
.rx_crc_ok:
        ld      hl,p126_ipc_log_dma_rx_crc_ok
        call    p126_ipc_debug_string
        ld      hl,P126_IPC_DMA_RX_BUFFER+P126_IPC_HEADER_SIZE
        ld      bc,P126_IPC_MAX_PAYLOAD
        ld      e,0
.rx_pattern:
        ld      a,e
        cp      (hl)
        jr      nz,.rx_pattern_bad
        inc     hl
        inc     e
        dec     bc
        ld      a,b
        or      c
        jr      nz,.rx_pattern
        ld      hl,p126_ipc_log_dma_rx_pattern_ok
        call    p126_ipc_debug_string
        xor     a
        ld      (p126_ipc_dma_rx_stage),a
        ld      (p126_ipc_dma_rx_error),a
        ret
.rx_pattern_bad:
        ld      a,3
        ld      (p126_ipc_dma_rx_error),a
        ld      hl,p126_ipc_log_dma_rx_pattern_bad
        call    p126_ipc_debug_string
        scf
        ret
.rx_failed:
        ld      (p126_ipc_dma_rx_error),a
        ld      hl,p126_ipc_log_dma_rx_transport_bad
        call    p126_ipc_debug_string
        ld      a,(p126_ipc_dma_rx_error)
        call    p126_ipc_debug_hex_byte
        call    p126_ipc_debug_crlf
        scf
        ret
p126_ipc_dma_rx_stage: db 0
p126_ipc_dma_rx_error: db 0

; -------------------------------------------------------------------------
; Receive and render the one-shot 8086 BIOS stop event.
; The request is the existing E1 reverse-DMA control command. Payload bytes
; travel only through ZX DMA; DBIT/GSDAT are not used for diagnostics.
; OUT: carry clear when a valid event frame was rendered.
; -------------------------------------------------------------------------
p126_ipc_dma_receive_debug_frame::
        ld      a,P126_CMD_NGS_FRAME
        call    p126_ipc_send_command
        jp      c,.debug_dma_failed

        ; Reverse DMA reads the complete 16 KiB frame from the ROM aperture.
        ; The first aperture read is discarded by the documented GS ABI.
        di
        ld      hl,0
        ld      a,(hl)
        ld      hl,0
        ld      de,P126_IPC_DMA_RX_BUFFER
        ld      bc,P126_IPC_MAX_FRAME_SIZE
        ldir

        ld      a,P126_CMD_DMA_END
        call    p126_ipc_send_command
        jp      c,.debug_dma_failed

        ld      hl,P126_IPC_DMA_RX_BUFFER
        ld      bc,P126_IPC_MAX_FRAME_SIZE
        call    p126_ipc_validate_frame
        jp      c,.debug_dma_failed

        ; Decode the compact stop event from the first five payload bytes.
        ld      a,(P126_IPC_DMA_RX_BUFFER+P126_IPC_HEADER_SIZE)
        cp      1
        jr      z,.debug_budget
        cp      2
        jr      z,.debug_halted
        cp      3
        jr      z,.debug_fault
        cp      4
        jr      z,.debug_reset_fault
        ; Unknown event payload is not a CPU register snapshot. Report
        ; the actual frame envelope and first payload bytes instead of
        ; misleadingly formatting arbitrary data as CS:IP.
        ld      hl,p126_ipc_debug_event_missing
        call    p126_ipc_console_string
        ld      a,(P126_IPC_DMA_RX_BUFFER+6)
        call    p126_ipc_console_hex_byte
        ld      a,(P126_IPC_DMA_RX_BUFFER+7)
        call    p126_ipc_console_hex_byte
        ld      a,(P126_IPC_DMA_RX_BUFFER+8)
        call    p126_ipc_console_hex_byte
        ld      a,':'
        call    BIOS_DebugConsole_PrintChar
        ld      a,(P126_IPC_DMA_RX_BUFFER+P126_IPC_HEADER_SIZE)
        call    p126_ipc_console_hex_byte
        ld      a,(P126_IPC_DMA_RX_BUFFER+P126_IPC_HEADER_SIZE+1)
        call    p126_ipc_console_hex_byte
        ld      a,(P126_IPC_DMA_RX_BUFFER+P126_IPC_HEADER_SIZE+2)
        call    p126_ipc_console_hex_byte
        ld      a,13
        call    BIOS_DebugConsole_PrintChar
        ld      a,10
        call    BIOS_DebugConsole_PrintChar
        or      a
        ret
.debug_budget:
        ld      hl,p126_ipc_debug_budget
        jr      .debug_render
.debug_halted:
        ld      hl,p126_ipc_debug_halted
        jr      .debug_render
.debug_fault:
        ld      hl,p126_ipc_debug_fault
        jr      .debug_render
.debug_reset_fault:
        ld      hl,p126_ipc_debug_reset_fault
.debug_render:
        call    p126_ipc_console_string
        ld      hl,(P126_IPC_DMA_RX_BUFFER+P126_IPC_HEADER_SIZE+1)
        call    p126_ipc_console_hex16
        ld      a,':'
        call    BIOS_DebugConsole_PrintChar
        ld      hl,(P126_IPC_DMA_RX_BUFFER+P126_IPC_HEADER_SIZE+3)
        call    p126_ipc_console_hex16
        ld      a,13
        call    BIOS_DebugConsole_PrintChar
        ld      a,10
        call    BIOS_DebugConsole_PrintChar
        or      a
        ret

.debug_dma_failed:
        ld      hl,p126_ipc_debug_dma_failed
        call    p126_ipc_console_string
        scf
        ret

; Request one converted frame from NeoGS and apply the RG6 text payload
; to the ATM's active page7/page3 text memory.
p126_ipc_dma_receive_video_frame::
        ld      a,(p126_atm_video_mode)
        cp      P126_ATM_VIDEO_MODE_RG6_TEXT80X25
        jp      nz,.video_bad_host_mode
        ld      a,P126_CMD_NGS_VIDEO_FRAME
        call    p126_ipc_send_command
        jp      c,.video_command_timeout

        di
        ld      hl,0
        ld      a,(hl)
        ld      hl,0
        ld      de,P126_IPC_DMA_RX_BUFFER
        ld      bc,P126_IPC_MAX_FRAME_SIZE
        ldir

        ld      a,P126_CMD_DMA_END
        call    p126_ipc_send_command
        jr      c,.video_dma_end_timeout

        ld      hl,P126_IPC_DMA_RX_BUFFER
        ld      bc,P126_IPC_MAX_FRAME_SIZE
        call    p126_ipc_validate_frame
        jr      c,.video_bad_frame
        ld      a,(P126_IPC_DMA_RX_BUFFER+7)
        cp      P126_SERVICE_VIDEO
        jr      nz,.video_bad_service
        ld      a,(P126_IPC_DMA_RX_BUFFER+8)
        cp      P126_OP_VIDEO_FRAME
        jr      nz,.video_bad_operation

        ; Header bytes 14..15 are STATUS (not reserved bytes).
        ld      a,(P126_IPC_DMA_RX_BUFFER+14)
        ld      b,a
        ld      a,(P126_IPC_DMA_RX_BUFFER+15)
        or      b
        jr      nz,.video_remote_error

        call    p126_screen_apply_text_frame
        jr      c,.video_apply_failed
        ld      hl,p126_ipc_video_frame_applied
        call    p126_ipc_console_string
        or      a
        ret

.video_bad_host_mode:
        ld      a,#01
        jr      .video_report_failure
.video_command_timeout:
        ld      a,#02
        jr      .video_report_failure
.video_dma_end_timeout:
        ld      a,#03
        jr      .video_report_failure
.video_bad_frame:
        ld      a,#04
        jr      .video_report_failure
.video_bad_service:
        ld      a,#05
        jr      .video_report_failure
.video_bad_operation:
        ld      a,#06
        jr      .video_report_failure
.video_remote_error:
        ld      a,#07
        jr      .video_report_failure
.video_apply_failed:
        ld      a,#08
.video_report_failure:
        ld      (p126_ipc_video_failure_code),a
        ld      hl,p126_ipc_video_dma_failed
        call    p126_ipc_console_string
        ld      a,(p126_ipc_video_failure_code)
        call    p126_ipc_console_hex_byte
        ld      a,':'
        call    BIOS_DebugConsole_PrintChar
        ld      a,(P126_IPC_DMA_RX_BUFFER+14)
        call    p126_ipc_console_hex_byte
        ld      a,(P126_IPC_DMA_RX_BUFFER+15)
        call    p126_ipc_console_hex_byte
        ld      a,':'
        call    BIOS_DebugConsole_PrintChar
        ld      a,(P126_IPC_DMA_RX_BUFFER+P126_IPC_HEADER_SIZE)
        call    p126_ipc_console_hex_byte
        ld      a,13
        call    BIOS_DebugConsole_PrintChar
        ld      a,10
        call    BIOS_DebugConsole_PrintChar
        scf
        ret

p126_ipc_video_failure_code: db 0

p126_ipc_console_string:
        ld      a,(hl)
        or      a
        ret     z
        push    hl
        call    BIOS_DebugConsole_PrintChar
        pop     hl
        inc     hl
        jr      p126_ipc_console_string

p126_ipc_console_hex16:
        ld      a,h
        call    p126_ipc_console_hex8
        ld      a,l
        jp      p126_ipc_console_hex8

p126_ipc_console_hex8:
        ld      (p126_ipc_console_hex_byte),a
        rrca
        rrca
        rrca
        rrca
        and     #0F
        call    p126_ipc_console_hex_nibble
        ld      a,(p126_ipc_console_hex_byte)
        and     #0F
        jp      p126_ipc_console_hex_nibble

p126_ipc_console_hex_nibble:
        and     #0F
        add     a,'0'
        cp      '9'+1
        jr      c,.console_hex_emit
        add     a,7
.console_hex_emit:
        jp      BIOS_DebugConsole_PrintChar

p126_ipc_console_hex_byte: db 0
p126_ipc_debug_budget: db "[X86] BIOS PAUSED: 16-INSTRUCTION SLICE COMPLETE; CS:IP=",0
p126_ipc_debug_halted: db "[X86] BIOS HALTED BY GUEST; CS:IP=",0
p126_ipc_debug_fault: db "[X86] BIOS STOPPED: OPCODE OR MEMORY FAULT; CS:IP=",0
p126_ipc_debug_reset_fault: db "[X86] BIOS RESET VECTOR FAILED; CS:IP=",0
p126_ipc_debug_event_missing: db "[X86] BIOS TRACE EVENT MISSING; CS:IP=",0
p126_ipc_debug_dma_failed: db "[X86] DIAGNOSTIC DMA FAILED",13,10,0
p126_ipc_video_frame_applied: db "[VIDEO] RG6 FRAME APPLIED",13,10,0
p126_ipc_video_dma_failed: db "[VIDEO] FRAME RECEIVE/APPLY FAILED",13,10,0

; Print A as two hexadecimal digits on ATM's independent #EF stream.
; Preserves AF and BC.
p126_ipc_debug_hex_byte:
        push    af
        push    bc
        rrca
        rrca
        rrca
        rrca
        call    p126_ipc_debug_hex_nibble
        pop     bc
        pop     af
        push    af
        and     #0F
        call    p126_ipc_debug_hex_nibble
        pop     af
        ret

p126_ipc_debug_hex_nibble:
        and     #0F
        add     a,'0'
        cp      '9'+1
        jr      c,.p126_ipc_debug_hex_emit
        add     a,7
.p126_ipc_debug_hex_emit:
        push    bc
        ld      bc,#00EF
        out     (c),a
        pop     bc
        ret

; Emit CR/LF on ATM's independent #EF debug channel.
p126_ipc_debug_crlf:
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

; ATM-local trace output, on ATM's own physical #EF stream.
; IN: HL=zero-terminated string. Preserves AF/BC; clobbers HL.
p126_ipc_debug_string:
        push    af
        push    bc
        ld      bc,#00EF
.p126_ipc_debug_loop:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,.p126_ipc_debug_done
        out     (c),a
        jr      .p126_ipc_debug_loop
.p126_ipc_debug_done:
        pop     bc
        pop     af
        ret

p126_ipc_log_crc_calculated:      db "[ATM IPC] CRC CALCULATED=",0
p126_ipc_log_crc_expected:        db " FRAME CRC=",0
p126_ipc_log_bad_magic_ptr: db "[ATM IPC] BAD MAGIC PTR=",0
p126_ipc_log_bad_magic_data: db " DATA=",0
p126_ipc_log_dma_tx_begin:        db "[ATM IPC] DMA TX BEGIN",13,10,0
p126_ipc_log_dma_tx_validate_ok:  db "[ATM IPC] FRAME STRUCTURE VALID",13,10,0
p126_ipc_log_dma_tx_validate_bad: db "[ATM IPC] FRAME STRUCTURE INVALID status=",0
p126_ipc_log_dma_tx_bad_size:    db " size=",0
p126_ipc_log_dma_tx_bad_header:  db " hdr=",0
p126_ipc_log_dma_tx_e0:           db "[ATM IPC] SEND E0",13,10,0
p126_ipc_log_dma_tx_e0_timeout:   db "[ATM IPC] E0 ACK TIMEOUT",13,10,0
p126_ipc_log_dma_tx_ready:        db "[ATM IPC] E0 ACK / READY",13,10,0
p126_ipc_log_dma_tx_copy_begin:   db "[ATM IPC] DMA COPY BEGIN",13,10,0
p126_ipc_log_dma_tx_copy_done:    db "[ATM IPC] DMA COPY DONE",13,10,0
p126_ipc_log_dma_tx_ff:           db "[ATM IPC] SEND FF",13,10,0
p126_ipc_log_dma_tx_ff_timeout:   db "[ATM IPC] FF ACK TIMEOUT",13,10,0
p126_ipc_log_dma_tx_done:         db "[ATM IPC] DMA TX COMPLETE",13,10,0
p126_ipc_log_dma_rx_begin:        db "[ATM IPC] DMA RX MAX FRAME BEGIN",13,10,0
p126_ipc_log_dma_rx_copy_done:    db "[ATM IPC] DMA RX 16K COPY DONE",13,10,0
p126_ipc_log_dma_rx_crc_ok:       db "[ATM IPC] DMA RX FRAME CRC VALID",13,10,0
p126_ipc_log_dma_rx_crc_bad:      db "[ATM IPC] DMA RX FRAME VALIDATION FAILED STATUS=",0
p126_ipc_log_dma_rx_pattern_ok:   db "[ATM IPC] DMA RX 16K PATTERN PASS",13,10,0
p126_ipc_log_dma_rx_pattern_bad:  db "[ATM IPC] DMA RX PATTERN FAIL",13,10,0
p126_ipc_log_dma_rx_transport_bad: db "[ATM IPC] DMA RX TRANSPORT FAILED STAGE=",0
; DMA RX storage aliases the 16 KiB ATM page-0 staging buffer at C000h.
; It is intentionally shared with the forward test because the transfers
; are sequential and the reverse test overwrites the request after TX.
p126_ipc_dma_rx_buffer EQU P126_IPC_DMA_RX_BUFFER
