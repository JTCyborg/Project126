; PROJECT126 / X86_ALU v0.1.0
; 8-bit ADD/SUB flag semantics for the Intel 8086 guest.
; PCem reference: PCem/808x.c setadd8(), setsub8() and related helpers.
;
; API:
;   x86_alu_add8: A=left operand, C=right operand.
;                A=result; updates x86_reg_flags arithmetic flags.
;   x86_alu_sub8: A=left operand, C=right operand.
;                A=result; updates x86_reg_flags arithmetic flags.
;   x86_alu_selftest: Carry clear=pass, set=fail.
;
; Clobbers: AF, BC, HL. Other guest state is not modified.
; Preserves all non-arithmetic x86 FLAGS bits; bit 1 is forced to one.
; Arithmetic flags: CF, PF, AF, ZF, SF, OF.

X86_ALU_KEEP_FLAGS_LO EQU #2A
X86_ALU_KEEP_FLAGS_HI EQU #F7

x86_alu_add8:
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

x86_alu_sub8:
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

; Regression vectors cover signed overflow, carry, auxiliary carry,
; zero, sign and even parity for both addition and subtraction.
x86_alu_selftest:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl,(x86_reg_flags)
        ld      (x86_alu_saved_flags),hl

        ; 7F + 01 = 80: OF,SF,AF set; CF,ZF,PF clear.
        ld      a,#7F
        ld      c,#01
        call    x86_alu_add8
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
        call    x86_alu_add8
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
        call    x86_alu_sub8
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
        call    x86_alu_sub8
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

x86_alu_lhs:         db 0
x86_alu_rhs:         db 0
x86_alu_result:      db 0
x86_alu_z80_flags:   db 0
x86_alu_saved_flags: dw 0
