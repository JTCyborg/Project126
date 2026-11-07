; PROJECT126 / X86_ALU v0.2.0
; 8-bit ADD/SUB flag semantics for the Intel 8086 guest.
; PCem reference: PCem/808x.c setadd8(), setsub8() and related helpers.
;
; API:
;   x86_alu_add8_impl: A=left operand, C=right operand.
;                A=result; updates x86_reg_flags arithmetic flags.
;   x86_alu_sub8_impl: A=left operand, C=right operand.
;                A=result; updates x86_reg_flags arithmetic flags.
;   x86_alu_selftest: Carry clear=pass, set=fail.
;
; Clobbers: AF, BC, HL. Other guest state is not modified.
; Preserves all non-arithmetic x86 FLAGS bits; bit 1 is forced to one.
; Arithmetic flags: CF, PF, AF, ZF, SF, OF.

X86_ALU_KEEP_FLAGS_LO EQU #2A
X86_ALU_KEEP_FLAGS_HI EQU #F7

; Runtime component identity for NeoGS #EF diagnostics.
x86_alu_emit_version:
        push    af
        push    hl
        ld      hl,x86_alu_version_text
.version_loop:
        ld      a,(hl)
        or      a
        jr      z,.version_done
        out     (#EF),a
        inc     hl
        jr      .version_loop
.version_done:
        pop     hl
        pop     af
        ret

x86_alu_version_text:
        defb    "[P126 X86_ALU v0.2.0]",13,10,0

x86_alu_add8_impl:
        ld      (x86_alu_lhs),a
        ld      a,c
        ld      (x86_alu_rhs),a
        ld      a,(x86_alu_rhs)
        ld      c,a
        ld      a,(x86_alu_lhs)
        add     a,c
        ld      (x86_alu_result),a
        push    af
        pop     hl
        ld      a,l
        ld      (x86_alu_z80_flags),a
        call    x86_alu_merge_flags
        ld      a,(x86_alu_result)
        ret

x86_alu_sub8_impl:
        ld      (x86_alu_lhs),a
        ld      a,c
        ld      (x86_alu_rhs),a
        ld      a,(x86_alu_rhs)
        ld      c,a
        ld      a,(x86_alu_lhs)
        sub     c
        ld      (x86_alu_result),a
        push    af
        pop     hl
        ld      a,l
        ld      (x86_alu_z80_flags),a
        call    x86_alu_merge_flags
        ld      a,(x86_alu_result)
        ret

; 16-bit arithmetic uses the low-byte operation to capture AF and the
; high-byte ADC/SBC to capture full-word CF, SF and OF. Guest PF is the
; parity of the low result byte, as on the 8086.

x86_alu_add16_impl:
        ld      (x86_alu_word_lhs),hl
        ld      (x86_alu_word_rhs),de
        ld      a,l
        ld      c,e
        add     a,c
        ld      (x86_alu_word_result),a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_low_flags),a
        ld      a,h
        ld      c,d
        adc     a,c
        ld      (x86_alu_word_result+1),a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_high_flags),a
        ld      hl,(x86_alu_word_result)
        call    x86_alu_merge_word_flags
        ret

x86_alu_sub16_impl:
        ld      (x86_alu_word_lhs),hl
        ld      (x86_alu_word_rhs),de
        ld      a,l
        ld      c,e
        sub     c
        ld      (x86_alu_word_result),a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_low_flags),a
        ld      a,h
        ld      c,d
        sbc     a,c
        ld      (x86_alu_word_result+1),a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_high_flags),a
        ld      hl,(x86_alu_word_result)
        call    x86_alu_merge_word_flags
        ret

x86_alu_merge_word_flags:
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     X86_ALU_KEEP_FLAGS_LO
        ld      l,a
        ld      a,h
        and     X86_ALU_KEEP_FLAGS_HI
        ld      h,a
        set     1,l

        ld      a,(x86_alu_high_flags)
        bit     0,a
        jr      z,.word_no_cf
        set     0,l
.word_no_cf:
        ld      a,(x86_alu_low_flags)
        bit     4,a
        jr      z,.word_no_af
        set     4,l
.word_no_af:
        ld      a,(x86_alu_high_flags)
        bit     7,a
        jr      z,.word_no_sf
        set     7,l
.word_no_sf:
        bit     2,a
        jr      z,.word_no_of
        set     3,h
.word_no_of:
        ld      a,(x86_alu_word_result)
        or      a
        jr      nz,.word_no_zf
        ld      a,(x86_alu_word_result+1)
        or      a
        jr      nz,.word_no_zf
        set     6,l
.word_no_zf:
        ld      a,(x86_alu_word_result)
        and     a
        jp      po,.word_no_pf
        set     2,l
.word_no_pf:
        ld      (x86_reg_flags),hl
        ret

; Translate Z80 ADD/SUB result flags to the corresponding 8086 flags.
; Z80 S/Z/H/PV/C map directly to 8086 SF/ZF/AF/OF/CF.
; PF is calculated separately from the result byte.
x86_alu_merge_flags:
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     X86_ALU_KEEP_FLAGS_LO
        ld      l,a
        ld      a,h
        and     X86_ALU_KEEP_FLAGS_HI
        ld      h,a
        set     1,l

        ld      a,(x86_alu_z80_flags)
        bit     0,a
        jr      z,.no_cf
        set     0,l
.no_cf:
        bit     4,a
        jr      z,.no_af
        set     4,l
.no_af:
        bit     6,a
        jr      z,.no_zf
        set     6,l
.no_zf:
        bit     7,a
        jr      z,.no_sf
        set     7,l
.no_sf:
        bit     2,a
        jr      z,.no_of
        set     3,h
.no_of:
        ld      a,(x86_alu_result)
        and     a
        jp      po,.no_pf
        set     2,l
.no_pf:
        ld      (x86_reg_flags),hl
        ret



; ADC/SBB helpers. Carry/borrow input is B bit 0; result and arithmetic
; flags are returned exactly like ADD/SUB. The 16-bit variants propagate the
; low-byte carry/borrow into the high-byte operation.
x86_alu_adc8_impl:
        ld      (x86_alu_lhs),a
        ld      a,c
        ld      (x86_alu_rhs),a
        ld      a,b
        and     1
        ld      (x86_alu_carry_in),a
        ld      a,(x86_alu_rhs)
        ld      c,a
        ld      a,(x86_alu_carry_in)
        or      a
        jr      z,.adc8_carry_clear
        scf
        jr      .adc8_apply
.adc8_carry_clear:
        or      a
.adc8_apply:
        ld      a,(x86_alu_lhs)
        adc     a,c
        ld      (x86_alu_result),a
        push    af
        pop     hl
        ld      a,l
        ld      (x86_alu_z80_flags),a
        call    x86_alu_merge_flags
        ld      a,(x86_alu_result)
        ret

x86_alu_sbb8_impl:
        ld      (x86_alu_lhs),a
        ld      a,c
        ld      (x86_alu_rhs),a
        ld      a,b
        and     1
        ld      (x86_alu_carry_in),a
        ld      a,(x86_alu_rhs)
        ld      c,a
        ld      a,(x86_alu_carry_in)
        or      a
        jr      z,.sbb8_borrow_clear
        scf
        jr      .sbb8_apply
.sbb8_borrow_clear:
        or      a
.sbb8_apply:
        ld      a,(x86_alu_lhs)
        sbc     a,c
        ld      (x86_alu_result),a
        push    af
        pop     hl
        ld      a,l
        ld      (x86_alu_z80_flags),a
        call    x86_alu_merge_flags
        ld      a,(x86_alu_result)
        ret

x86_alu_adc16_impl:
        ld      (x86_alu_word_lhs),hl
        ld      (x86_alu_word_rhs),de
        ld      a,b
        and     1
        ld      (x86_alu_carry_in),a
        ld      a,(x86_alu_carry_in)
        or      a
        jr      z,.adc16_carry_clear
        scf
        jr      .adc16_low
.adc16_carry_clear:
        or      a
.adc16_low:
        ld      a,l
        ld      c,e
        adc     a,c
        ld      (x86_alu_word_result),a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_low_flags),a
        ld      a,h
        ld      c,d
        adc     a,c
        ld      (x86_alu_word_result+1),a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_high_flags),a
        ld      hl,(x86_alu_word_result)
        call    x86_alu_merge_word_flags
        ret

x86_alu_sbb16_impl:
        ld      (x86_alu_word_lhs),hl
        ld      (x86_alu_word_rhs),de
        ld      a,b
        and     1
        ld      (x86_alu_carry_in),a
        ld      a,(x86_alu_carry_in)
        or      a
        jr      z,.sbb16_borrow_clear
        scf
        jr      .sbb16_low
.sbb16_borrow_clear:
        or      a
.sbb16_low:
        ld      a,l
        ld      c,e
        sbc     a,c
        ld      (x86_alu_word_result),a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_low_flags),a
        ld      a,h
        ld      c,d
        sbc     a,c
        ld      (x86_alu_word_result+1),a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_high_flags),a
        ld      hl,(x86_alu_word_result)
        call    x86_alu_merge_word_flags
        ret

; Logical operations for the original 8086.
; API: x86_alu_logic8_impl: A=lhs, C=rhs, B=operation (0 OR, 1 AND, 2 XOR).
;      Returns A=result and updates SF/ZF/PF; clears CF/AF/OF.
;      x86_alu_logic16_impl: HL=lhs, DE=rhs, B=operation; returns HL=result.
; The AF bit is cleared, matching the existing Project126 logical-flag policy.

x86_alu_logic8_impl:
        ld      (x86_alu_logic_lhs),a
        ld      a,c
        ld      (x86_alu_logic_rhs),a
        ld      a,b
        ld      (x86_alu_logic_op),a
        ld      a,(x86_alu_logic_rhs)
        ld      c,a
        ld      a,(x86_alu_logic_lhs)
        call    x86_alu_logic_apply8
        ld      (x86_alu_logic_result),a
        or      a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_logic_z80_flags),a
        call    x86_alu_logic_merge8
        ld      a,(x86_alu_logic_result)
        ret

x86_alu_logic16_impl:
        ld      (x86_alu_logic_word_lhs),hl
        ld      (x86_alu_logic_word_rhs),de
        ld      a,b
        ld      (x86_alu_logic_op),a
        ld      a,l
        ld      c,e
        call    x86_alu_logic_apply8
        ld      (x86_alu_logic_word_result),a
        ld      a,h
        ld      c,d
        call    x86_alu_logic_apply8
        ld      (x86_alu_logic_word_result+1),a

        ld      a,(x86_alu_logic_word_result)
        or      a
        push    af
        pop     bc
        ld      a,c
        ld      (x86_alu_logic_z80_flags),a

        ld      hl,(x86_reg_flags)
        ld      a,l
        and     X86_ALU_KEEP_FLAGS_LO
        ld      l,a
        ld      a,h
        and     X86_ALU_KEEP_FLAGS_HI
        ld      h,a
        set     1,l

        ld      a,(x86_alu_logic_z80_flags)
        bit     2,a
        jr      z,.logic16_no_pf
        set     2,l
.logic16_no_pf:
        ld      a,(x86_alu_logic_word_result+1)
        bit     7,a
        jr      z,.logic16_no_sf
        set     7,l
.logic16_no_sf:
        ld      a,(x86_alu_logic_word_result)
        ld      b,a
        ld      a,(x86_alu_logic_word_result+1)
        or      b
        jr      nz,.logic16_no_zf
        set     6,l
.logic16_no_zf:
        ld      (x86_reg_flags),hl
        ld      hl,(x86_alu_logic_word_result)
        ret

; A=lhs, C=rhs, x86_alu_logic_op selects OR/AND/XOR.
x86_alu_logic_apply8:
        ld      b,a
        ld      a,(x86_alu_logic_op)
        cp      0
        jr      z,.logic_or
        cp      1
        jr      z,.logic_and
        ld      a,b
        xor     c
        ret
.logic_or:
        ld      a,b
        or      c
        ret
.logic_and:
        ld      a,b
        and     c
        ret

x86_alu_logic_merge8:
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     X86_ALU_KEEP_FLAGS_LO
        ld      l,a
        ld      a,h
        and     X86_ALU_KEEP_FLAGS_HI
        ld      h,a
        set     1,l
        ld      a,(x86_alu_logic_z80_flags)
        bit     2,a
        jr      z,.logic8_no_pf
        set     2,l
.logic8_no_pf:
        bit     6,a
        jr      z,.logic8_no_zf
        set     6,l
.logic8_no_zf:
        bit     7,a
        jr      z,.logic8_no_sf
        set     7,l
.logic8_no_sf:
        ld      (x86_reg_flags),hl
        ret

; Regression vectors cover signed overflow, carry, auxiliary carry,
; zero, sign and even parity for both addition and subtraction.
x86_alu_selftest:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl,(x86_reg_flags)
        ld      (x86_alu_saved_flags),hl

        ; Preserve non-arithmetic control flags (TF, IF, DF) and FLAGS bit 1.
        ld      hl,#0702
        ld      (x86_reg_flags),hl
        ld      a,#01
        ld      c,#01
        call    x86_alu_add8_impl
        ld      hl,(x86_reg_flags)
        bit     0,h
        jp      z,.fail
        bit     1,h
        jp      z,.fail
        bit     2,h
        jp      z,.fail
        bit     1,l
        jp      z,.fail

        ; 7F + 01 = 80: OF,SF,AF set; CF,ZF,PF clear.
        ld      a,#7F
        ld      c,#01
        call    x86_alu_add8_impl
        cp      #80
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        bit     3,h
        jp      z,.fail
        bit     7,l
        jp      z,.fail
        bit     4,l
        jp      z,.fail
        bit     0,l
        jp      nz,.fail
        bit     6,l
        jp      nz,.fail
        bit     2,l
        jp      nz,.fail

        ; FF + 01 = 00: CF,AF,ZF,PF set; OF,SF clear.
        ld      a,#FF
        ld      c,#01
        call    x86_alu_add8_impl
        or      a
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        bit     0,l
        jp      z,.fail
        bit     4,l
        jp      z,.fail
        bit     6,l
        jp      z,.fail
        bit     2,l
        jp      z,.fail
        bit     3,h
        jp      nz,.fail
        bit     7,l
        jp      nz,.fail

        ; 80 - 01 = 7F: OF,AF set; CF,SF,ZF,PF clear.
        ld      a,#80
        ld      c,#01
        call    x86_alu_sub8_impl
        cp      #7F
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        bit     3,h
        jp      z,.fail
        bit     4,l
        jp      z,.fail
        bit     0,l
        jp      nz,.fail
        bit     7,l
        jp      nz,.fail
        bit     6,l
        jp      nz,.fail
        bit     2,l
        jp      nz,.fail

        ; 00 - 01 = FF: CF,AF,SF,PF set; OF,ZF clear.
        ld      a,#00
        ld      c,#01
        call    x86_alu_sub8_impl
        cp      #FF
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        bit     0,l
        jp      z,.fail
        bit     4,l
        jp      z,.fail
        bit     7,l
        jp      z,.fail
        bit     2,l
        jp      z,.fail
        bit     3,h
        jp      nz,.fail
        bit     6,l
        jp      nz,.fail

        ; 7FFF + 0001 = 8000: 16-bit signed overflow.
        ld      hl,#7FFF
        ld      de,#0001
        call    x86_alu_add16_impl
        ld      de,#8000
        or      a
        sbc     hl,de
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        bit     3,h
        jp      z,.fail
        bit     7,l
        jp      z,.fail
        bit     4,l
        jp      z,.fail
        bit     2,l
        jp      z,.fail
        bit     0,l
        jp      nz,.fail
        bit     6,l
        jp      nz,.fail

        ; FFFF + 0001 = 0000: carry, AF, ZF and PF.
        ld      hl,#FFFF
        ld      de,#0001
        call    x86_alu_add16_impl
        ld      a,h
        or      l
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        bit     0,l
        jp      z,.fail
        bit     4,l
        jp      z,.fail
        bit     6,l
        jp      z,.fail
        bit     2,l
        jp      z,.fail
        bit     3,h
        jp      nz,.fail
        bit     7,l
        jp      nz,.fail

        ; 8000 - 0001 = 7FFF: signed overflow and auxiliary borrow.
        ld      hl,#8000
        ld      de,#0001
        call    x86_alu_sub16_impl
        ld      de,#7FFF
        or      a
        sbc     hl,de
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        bit     3,h
        jp      z,.fail
        bit     4,l
        jp      z,.fail
        bit     2,l
        jp      z,.fail
        bit     0,l
        jp      nz,.fail
        bit     7,l
        jp      nz,.fail
        bit     6,l
        jp      nz,.fail

        ; 0000 - 0001 = FFFF: borrow, sign, AF and even parity.
        ld      hl,#0000
        ld      de,#0001
        call    x86_alu_sub16_impl
        ld      de,#FFFF
        or      a
        sbc     hl,de
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        bit     0,l
        jp      z,.fail
        bit     4,l
        jp      z,.fail
        bit     7,l
        jp      z,.fail
        bit     2,l
        jp      z,.fail
        bit     3,h
        jp      nz,.fail
        bit     6,l
        jp      nz,.fail

        ld      hl,(x86_alu_saved_flags)
        ld      (x86_reg_flags),hl
        pop     hl
        pop     de
        pop     bc
        pop     af
        or      a
        ret
.fail:
        ld      hl,(x86_alu_saved_flags)
        ld      (x86_reg_flags),hl
        pop     hl
        pop     de
        pop     bc
        pop     af
        scf
        ret

x86_alu_carry_in: db 0
x86_alu_logic_lhs: db 0
x86_alu_logic_rhs: db 0
x86_alu_logic_result: db 0
x86_alu_logic_op: db 0
x86_alu_logic_z80_flags: db 0
x86_alu_logic_word_lhs: dw 0
x86_alu_logic_word_rhs: dw 0
x86_alu_logic_word_result: dw 0

x86_alu_lhs:         db 0
x86_alu_rhs:         db 0
x86_alu_result:      db 0
x86_alu_z80_flags:   db 0
x86_alu_saved_flags: dw 0
x86_alu_word_lhs:    dw 0
x86_alu_word_rhs:    dw 0
x86_alu_word_result: dw 0
x86_alu_low_flags:   db 0
x86_alu_high_flags:  db 0

; Fixed-origin probe used by IMAGE_FINISH to validate the page-05 gate path.
x86_alu_overlay_probe_impl:
        ; IMAGE_FINISH enters with A=3Ch, carry set and HL=1234h.
        ; Check input AF/HL survived the resident gate, then return a
        ; signature in both A and HL for the caller-side return check.
        jp      nc,.overlay_probe_failed
        cp      #3C
        jr      nz,.overlay_probe_failed
        ld      hl,#5AA5
        ld      a,#A5
        ret
.overlay_probe_failed:
        xor     a
        ret
