; PROJECT126 / X86_MODRM v0.1.0
; Intel 8086 16-bit ModR/M effective-address decoder.
; Reference: PCem/808x.c fetcheal(), mod1add[] and mod1seg[].
;
; API:
;   x86_decode_modrm16 fetches the ModR/M byte from guest CS:IP.
;   OUT: x86_modrm_mod/reg/rm, x86_ea_is_reg, x86_ea_reg,
;        x86_ea_offset, x86_ea_segment.
;   Carry set on instruction-stream or displacement memory fault.
;
; Register encoding: AX,CX,DX,BX,SP,BP,SI,DI.
; Memory addressing follows the original 8086 BX/BP/SI/DI combinations.
; Default segment is SS for BP-based forms, DS otherwise.
; mod=00,r/m=110 is direct [disp16] and defaults to DS.
; Segment override prefixes are applied by the later prefix execution layer.
; All guest instruction bytes are fetched via x86_cpu_fetch8/fetch16.

x86_decode_modrm16:
        call    x86_cpu_fetch8
        ret     c
        ld      (x86_modrm_byte),a

        and     #C0
        rlca
        rlca
        ld      (x86_modrm_mod),a

        ld      a,(x86_modrm_byte)
        and     #38
        rrca
        rrca
        rrca
        ld      (x86_modrm_reg),a

        ld      a,(x86_modrm_byte)
        and     #07
        ld      (x86_modrm_rm),a

        ld      a,(x86_modrm_mod)
        cp      3
        jr      nz,.memory
        ld      a,1
        ld      (x86_ea_is_reg),a
        ld      a,(x86_modrm_rm)
        ld      (x86_ea_reg),a
        or      a
        ret

.memory:
        xor     a
        ld      (x86_ea_is_reg),a
        ld      hl,(x86_reg_ds)
        ld      (x86_ea_segment),hl

        ; Special direct displacement form [disp16].
        ld      a,(x86_modrm_mod)
        or      a
        jr      nz,.base_decode
        ld      a,(x86_modrm_rm)
        cp      6
        jr      nz,.base_decode
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_ea_offset),hl
        or      a
        ret

.base_decode:
        ld      a,(x86_modrm_rm)
        cp      0
        jr      z,.bx_si
        cp      1
        jr      z,.bx_di
        cp      2
        jr      z,.bp_si
        cp      3
        jr      z,.bp_di
        cp      4
        jr      z,.si_only
        cp      5
        jr      z,.di_only
        cp      6
        jr      z,.bp_only
        jr      .bx_only

.bx_si:
        ld      hl,(x86_reg_bx)
        ld      de,(x86_reg_si)
        add     hl,de
        jr      .base_ready
.bx_di:
        ld      hl,(x86_reg_bx)
        ld      de,(x86_reg_di)
        add     hl,de
        jr      .base_ready
.bp_si:
        call    x86_modrm_set_ss
        ld      hl,(x86_reg_bp)
        ld      de,(x86_reg_si)
        add     hl,de
        jr      .base_ready
.bp_di:
        call    x86_modrm_set_ss
        ld      hl,(x86_reg_bp)
        ld      de,(x86_reg_di)
        add     hl,de
        jr      .base_ready
.si_only:
        ld      hl,(x86_reg_si)
        jr      .base_ready
.di_only:
        ld      hl,(x86_reg_di)
        jr      .base_ready
.bp_only:
        call    x86_modrm_set_ss
        ld      hl,(x86_reg_bp)
        jr      .base_ready
.bx_only:
        ld      hl,(x86_reg_bx)

.base_ready:
        ld      (x86_ea_offset),hl
        ld      a,(x86_modrm_mod)
        cp      1
        jr      z,.disp8
        cp      2
        jr      z,.disp16
        or      a
        ret

.disp8:
        call    x86_cpu_fetch8
        ret     c
        ld      e,a
        ld      d,0
        bit     7,a
        jr      z,.disp8_add
        dec     d
.disp8_add:
        ld      hl,(x86_ea_offset)
        add     hl,de
        ld      (x86_ea_offset),hl
        or      a
        ret

.disp16:
        call    x86_cpu_fetch16
        ret     c
        ld      de,(x86_ea_offset)
        add     hl,de
        ld      (x86_ea_offset),hl
        or      a
        ret

x86_modrm_set_ss:
        ld      hl,(x86_reg_ss)
        ld      (x86_ea_segment),hl
        ret

x86_modrm_byte: db 0
x86_modrm_mod: db 0
x86_modrm_reg: db 0
x86_modrm_rm: db 0
x86_ea_is_reg: db 0
x86_ea_reg: db 0
x86_ea_offset: dw 0
x86_ea_segment: dw 0
