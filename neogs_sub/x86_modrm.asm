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
; Segment override prefixes are applied by the x86_exec prefix layer.
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
        call    x86_modrm_apply_segment_override
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
        call    x86_modrm_apply_segment_override
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
        call    x86_modrm_apply_segment_override
        or      a
        ret

.disp16:
        call    x86_cpu_fetch16
        ret     c
        ld      de,(x86_ea_offset)
        add     hl,de
        ld      (x86_ea_offset),hl
        call    x86_modrm_apply_segment_override
        or      a
        ret

x86_modrm_set_ss:
        ld      hl,(x86_reg_ss)
        ld      (x86_ea_segment),hl
        ret

; Replace the ModR/M default segment only when a segment override prefix
; was present for the current instruction.
x86_modrm_apply_segment_override:
        ld      a,(x86_exec_prefix_seg)
        or      a
        ret     z
        call    x86_exec_get_data_segment
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

; -------------------------------------------------------------------------
; Operand access helpers for the decoded ModR/M byte.
;
; x86_modrm_read_reg8:  input A=register code (0..7), output A=byte.
; x86_modrm_write_reg8: input A=register code, C=value.
; x86_modrm_read_rm8:   output A=byte from r/m operand.
; x86_modrm_write_rm8:  input A=value, writes r/m operand.
; x86_modrm_read_reg16: output HL=word from ModR/M reg field.
; x86_modrm_write_reg16: input HL=word, writes ModR/M reg field.
; x86_modrm_read_rm16: output HL=word from r/m operand.
; x86_modrm_write_rm16: input HL=word, writes r/m operand.
;
; Guest memory word accesses are two byte transactions, with 16-bit offset
; wrap and the same Project126 physical mapper used by the fetch path.

x86_modrm_read_reg8:
        and     7
        ld      (x86_modrm_operand_index),a
        and     3
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_modrm_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      a,(x86_modrm_operand_index)
        cp      4
        jr      c,.read_reg8_ptr_ready
        inc     de
.read_reg8_ptr_ready:
        ld      a,(de)
        or      a
        ret

x86_modrm_write_reg8:
        ; PCem's 808x.c keeps the ModR/M register selector separate from the
        ; byte being written. A is the selector; C is the source byte.
        ; Preserve the selector before loading C, otherwise AL's value is
        ; accidentally decoded as the destination register number.
        and     7
        ld      (x86_modrm_operand_index),a
        ld      a,c
        ld      (x86_modrm_operand_value),a
        ld      a,(x86_modrm_operand_index)
        and     3
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_modrm_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      a,(x86_modrm_operand_index)
        cp      4
        jr      c,.write_reg8_ptr_ready
        inc     de
.write_reg8_ptr_ready:
        ld      a,(x86_modrm_operand_value)
        ld      (de),a
        or      a
        ret

; Regression for all eight 8086 byte-register encodings:
; AL,CL,DL,BL,AH,CH,DH,BH. Returns carry clear on pass.
x86_modrm_reg8_selftest:
        ld      hl,#A1A0
        ld      (x86_reg_ax),hl
        ld      hl,#C1C0
        ld      (x86_reg_cx),hl
        ld      hl,#D1D0
        ld      (x86_reg_dx),hl
        ld      hl,#B1B0
        ld      (x86_reg_bx),hl

        ld      a,0
        ld      c,#10
        call    x86_modrm_write_reg8
        ld      a,1
        ld      c,#21
        call    x86_modrm_write_reg8
        ld      a,2
        ld      c,#32
        call    x86_modrm_write_reg8
        ld      a,3
        ld      c,#43
        call    x86_modrm_write_reg8
        ld      a,4
        ld      c,#54
        call    x86_modrm_write_reg8
        ld      a,5
        ld      c,#65
        call    x86_modrm_write_reg8
        ld      a,6
        ld      c,#76
        call    x86_modrm_write_reg8
        ld      a,7
        ld      c,#87
        call    x86_modrm_write_reg8

        ld      hl,(x86_reg_ax)
        ld      de,#5410
        or      a
        sbc     hl,de
        jr      nz,.reg8_test_fail
        ld      hl,(x86_reg_cx)
        ld      de,#6521
        or      a
        sbc     hl,de
        jr      nz,.reg8_test_fail
        ld      hl,(x86_reg_dx)
        ld      de,#7632
        or      a
        sbc     hl,de
        jr      nz,.reg8_test_fail
        ld      hl,(x86_reg_bx)
        ld      de,#8743
        or      a
        sbc     hl,de
        jr      nz,.reg8_test_fail
        or      a
        ret
.reg8_test_fail:
        scf
        ret

x86_modrm_read_reg16:
        ld      a,(x86_modrm_reg)
        jr      x86_modrm_read_reg16_index
x86_modrm_read_reg16_index:
        and     7
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_modrm_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        or      a
        ret

x86_modrm_write_reg16:
        ld      (x86_modrm_operand_word),hl
        ld      a,(x86_modrm_reg)
        and     7
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_modrm_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      de,(x86_modrm_operand_word)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        or      a
        ret

x86_modrm_read_rm8:
        ld      a,(x86_ea_is_reg)
        or      a
        jr      z,.read_rm8_memory
        ld      a,(x86_ea_reg)
        jp      x86_modrm_read_reg8
.read_rm8_memory:
        call    x86_modrm_make_ea_address
        call    x86_guest_mem_read8
        ret

x86_modrm_write_rm8:
        ld      (x86_modrm_operand_value),a
        ld      a,(x86_ea_is_reg)
        or      a
        jr      z,.write_rm8_memory
        ld      a,(x86_modrm_operand_value)
        ld      c,a
        ld      a,(x86_ea_reg)
        jp      x86_modrm_write_reg8
.write_rm8_memory:
        call    x86_modrm_make_ea_address
        ld      a,(x86_modrm_operand_value)
        call    x86_guest_mem_write8
        ret

x86_modrm_read_rm16:
        ld      a,(x86_ea_is_reg)
        or      a
        jr      z,.read_rm16_memory
        ld      a,(x86_ea_reg)
        and     7
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_modrm_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        or      a
        ret
.read_rm16_memory:
        call    x86_modrm_make_ea_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_modrm_operand_word),a
        ld      hl,(x86_ea_offset)
        inc     hl
        ld      (x86_modrm_temp_offset),hl
        call    x86_modrm_make_temp_ea_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_modrm_operand_word+1),a
        ld      hl,(x86_modrm_operand_word)
        or      a
        ret

x86_modrm_write_rm16:
        ld      (x86_modrm_operand_word),hl
        ld      a,(x86_ea_is_reg)
        or      a
        jr      z,.write_rm16_memory
        ld      a,(x86_ea_reg)
        and     7
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_modrm_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      de,(x86_modrm_operand_word)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        or      a
        ret
.write_rm16_memory:
        call    x86_modrm_make_ea_address
        ld      a,(x86_modrm_operand_word)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_ea_offset)
        inc     hl
        ld      (x86_modrm_temp_offset),hl
        call    x86_modrm_make_temp_ea_address
        ld      a,(x86_modrm_operand_word+1)
        call    x86_guest_mem_write8
        ret

x86_modrm_make_ea_address:
        ld      hl,(x86_ea_segment)
        ld      de,(x86_ea_offset)
        jp      x86_cpu_calc_phys

x86_modrm_make_temp_ea_address:
        ld      hl,(x86_ea_segment)
        ld      de,(x86_modrm_temp_offset)
        jp      x86_cpu_calc_phys

x86_modrm_reg16_table:
        dw x86_reg_ax,x86_reg_cx,x86_reg_dx,x86_reg_bx
        dw x86_reg_sp,x86_reg_bp,x86_reg_si,x86_reg_di

x86_modrm_operand_index: db 0
x86_modrm_operand_value: db 0
x86_modrm_operand_word: dw 0
x86_modrm_temp_offset: dw 0
