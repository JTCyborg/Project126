; =========================================================================
; PROJECT126 — NeoGS-side CRC primitive for unified DMA/IPC ABI 1.0
; This module performs no hardware port I/O and owns no DMA addresses.
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
        jr      c,.p126_ngs_frame_bad
.p126_ngs_frame_min_ok:
        push    hl
        pop     ix
        ld      a,(ix+0)
        cp      'P'
        jr      nz,.p126_ngs_frame_magic
        ld      a,(ix+1)
        cp      '1'
        jr      nz,.p126_ngs_frame_magic
        ld      a,(ix+2)
        cp      '2'
        jr      nz,.p126_ngs_frame_magic
        ld      a,(ix+3)
        cp      '6'
        jr      nz,.p126_ngs_frame_magic
        ld      a,(ix+4)
        cp      P126_IPC_MAJOR
        jr      nz,.p126_ngs_frame_version
        ld      a,(ix+5)
        cp      P126_IPC_MINOR
        jr      nz,.p126_ngs_frame_version
        ld      a,(ix+6)
        cp      P126_MSG_REQUEST
        jr      z,.p126_ngs_frame_type
        cp      P126_MSG_RESPONSE
        jr      z,.p126_ngs_frame_type
        cp      P126_MSG_EVENT
        jr      z,.p126_ngs_frame_type
        cp      P126_MSG_CANCEL
        jr      nz,.p126_ngs_frame_bad
.p126_ngs_frame_type:
        ld      a,(ix+9)
        and     #F8
        jr      nz,.p126_ngs_frame_bad
        ld      l,(ix+12)
        ld      h,(ix+13)
        ld      de,P126_IPC_HEADER_SIZE
        add     hl,de
        ld      de,(p126_ngs_ipc_frame_size)
        or      a
        sbc     hl,de
        jr      nz,.p126_ngs_frame_bad
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
        jr      nz,.p126_ngs_frame_crc_bad
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
