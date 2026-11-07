; PROJECT126 / X86_EXEC v0.1.0
; Intel 8086 Real Mode instruction execution core.
; Semantics cross-checked against PCem/808x.c (FETCH, EA opcode and JMP paths).
; This is the first executable slice; unsupported opcodes fail closed.
;
; Public API:
;   x86_cpu_fetch8  -> A=byte, advances guest IP, carry on memory fault.
;   x86_cpu_fetch16 -> HL=word, little-endian, advances guest IP.
;   x86_cpu_step   -> executes exactly one instruction; carry on fault/unsupported.
;
; Guest memory is accessed only through x86_guest_mem_read8 and the Project126
; physical-address mapper. No physical device I/O is issued by this CPU core.

x86_cpu_fetch8:
        push    bc
        ld      hl,(x86_reg_cs)
        ld      de,(x86_reg_ip)
        call    x86_cpu_calc_phys
        call    x86_guest_mem_read8
        jr      c,.fetch_fault
        ld      (x86_exec_fetch_byte),a
        ld      hl,(x86_reg_ip)
        inc     hl
        ld      (x86_reg_ip),hl
        ld      a,(x86_exec_fetch_byte)
        pop     bc
        or      a
        ret
.fetch_fault:
        pop     bc
        scf
        ret

x86_cpu_fetch16:
        call    x86_cpu_fetch8
        ret     c
        ld      (x86_exec_imm_low),a
        call    x86_cpu_fetch8
        ret     c
        ld      h,a
        ld      a,(x86_exec_imm_low)
        ld      l,a
        ret

; One architectural instruction boundary. The dispatcher intentionally
; rejects unknown opcodes rather than silently advancing or corrupting state.
x86_cpu_step:
        call    x86_cpu_fetch8
        ret     c
        ld      (x86_exec_opcode),a

        cp      #06
        jp      c,x86_exec_add_family
        cp      #27
        jp      z,x86_exec_daa
        cp      #2F
        jp      z,x86_exec_das
        cp      #37
        jp      z,x86_exec_aaa
        cp      #3F
        jp      z,x86_exec_aas
        cp      #F6
        jp      z,x86_exec_group3
        cp      #F7
        jp      z,x86_exec_group3
        cp      #FE
        jp      z,x86_exec_group4_5
        cp      #FF
        jp      z,x86_exec_group4_5
        cp      #80
        jp      z,x86_exec_group1_immediate
        cp      #81
        jp      z,x86_exec_group1_immediate
        cp      #82
        jp      z,x86_exec_group1_immediate
        cp      #83
        jp      z,x86_exec_group1_immediate
        cp      #10
        jp      c,.not_adc_family
        cp      #16
        jp      c,x86_exec_adc_sbb_family
.not_adc_family:
        cp      #18
        jp      c,.not_sbb_family
        cp      #1E
        jp      c,x86_exec_adc_sbb_family
.not_sbb_family:
        cp      #08
        jp      c,.not_logic_or
        cp      #0E
        jp      c,x86_exec_logic_family
.not_logic_or:
        cp      #20
        jp      c,.not_logic_and
        cp      #26
        jp      c,x86_exec_logic_family
.not_logic_and:
        cp      #30
        jp      c,.not_logic_xor
        cp      #36
        jp      c,x86_exec_logic_family
.not_logic_xor:
        cp      #84
        jp      z,x86_exec_logic_family
        cp      #85
        jp      z,x86_exec_logic_family
        cp      #28
        jp      c,.not_sub_family_28
        cp      #2E
        jp      c,x86_exec_subcmp_family
.not_sub_family_28:
        cp      #38
        jp      c,.not_sub_family_38
        cp      #3E
        jp      c,x86_exec_subcmp_family
.not_sub_family_38:
        cp      #06
        jp      z,x86_exec_push_segment
        cp      #07
        jp      z,x86_exec_pop_segment
        cp      #0E
        jp      z,x86_exec_push_segment
        cp      #16
        jp      z,x86_exec_push_segment
        cp      #17
        jp      z,x86_exec_pop_segment
        cp      #1E
        jp      z,x86_exec_push_segment
        cp      #1F
        jp      z,x86_exec_pop_segment
        cp      #D7
        jp      z,x86_exec_xlat
        cp      #F5
        jp      z,x86_exec_cmc
        cp      #F8
        jp      c,.not_flag_control
        cp      #FE
        jp      c,x86_exec_flag_control
.not_flag_control:
        cp      #98
        jp      z,x86_exec_cbw
        cp      #99
        jp      z,x86_exec_cwd
        cp      #9A
        jp      z,x86_exec_call_far_imm
        cp      #9B
        jp      z,x86_exec_wait
        cp      #C4
        jp      z,x86_exec_les_lds
        cp      #C5
        jp      z,x86_exec_les_lds
        cp      #C6
        jp      z,x86_exec_mov_imm_rm
        cp      #C7
        jp      z,x86_exec_mov_imm_rm
        cp      #C1
        jp      z,x86_exec_ret_near
        cp      #C2
        jp      z,x86_exec_ret_near
        cp      #C3
        jp      z,x86_exec_ret_near
        cp      #C8
        jp      z,x86_exec_ret_far
        cp      #C9
        jp      z,x86_exec_ret_far
        cp      #CA
        jp      z,x86_exec_ret_far
        cp      #CB
        jp      z,x86_exec_ret_far
        cp      #9C
        jp      z,x86_exec_pushf
        cp      #9D
        jp      z,x86_exec_popf
        cp      #9E
        jp      z,x86_exec_sahf
        cp      #9F
        jp      z,x86_exec_lahf
        cp      #EA
        jp      z,x86_exec_jmp_far_imm
        cp      #E0
        jp      c,.not_loop_family
        cp      #E4
        jp      c,x86_exec_loop_family
.not_loop_family:
        cp      #E8
        jp      z,x86_exec_call_near_rel16
        cp      #E9
        jp      z,x86_exec_jmp_near_rel16
        cp      #EB
        jp      z,x86_exec_jmp_short_rel8
        cp      #90
        jp      z,x86_exec_nop
        ; 91-97: XCHG AX,r16 (90 is the NOP encoding).
        ld      a,(x86_exec_opcode)
        cp      #91
        jp      c,.not_xchg_ax_reg
        cp      #98
        jp      c,x86_exec_xchg_ax_reg
.not_xchg_ax_reg:
        cp      #8C
        jp      z,x86_exec_mov_sreg_rm
        cp      #8E
        jp      z,x86_exec_mov_sreg_rm
        cp      #8F
        jp      z,x86_exec_pop_rm16
        cp      #86
        jp      z,x86_exec_xchg_rm_reg
        cp      #87
        jp      z,x86_exec_xchg_rm_reg
        cp      #8D
        jp      z,x86_exec_lea
        cp      #88
        jp      c,.not_mov_rm_reg
        cp      #8C
        jp      c,x86_exec_mov_rm_reg
.not_mov_rm_reg:
        cp      #A8
        jp      z,x86_exec_test_al_imm
        cp      #A9
        jp      z,x86_exec_test_ax_imm
        cp      #A0
        jp      c,.not_moffs
        cp      #A4
        jp      c,x86_exec_moffs
.not_moffs:
        cp      #60
        jp      c,.not_jcc
        cp      #80
        jp      c,x86_exec_jcc
.not_jcc:
        cp      #50
        jp      c,.not_push_pop_reg
        cp      #60
        jp      c,x86_exec_push_pop_reg
.not_push_pop_reg:
        cp      #F4
        jp      z,x86_exec_hlt
        ; 40-4F: INC/DEC r16. Carry flag is preserved by both operations.
        ld      a,(x86_exec_opcode)
        cp      #40
        jp      c,.not_incdec_reg
        cp      #50
        jp      c,x86_exec_incdec_reg
.not_incdec_reg:
        ; B0-BF: MOV r8/r16, immediate.
        ld      a,(x86_exec_opcode)
        cp      #B0
        jp      c,.not_mov_imm_reg
        cp      #C0
        jp      nc,.not_mov_imm_reg
        jp      x86_exec_mov_imm_reg
.not_mov_imm_reg:
        scf
        ret

; 00-03 ADD r/m,r and r,r/m; 04-05 ADD AL/AX,immediate.
; Uses the PCem-compatible arithmetic flag helpers in x86_alu.asm.
x86_exec_add_family:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_alu_opcode),a
        cp      #04
        jp      nc,.add_accumulator

        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_exec_alu_opcode)
        bit     0,a
        jr      nz,.add_word
        bit     1,a
        jr      nz,.add_r8_from_rm8

        ; ADD r/m8,r8
        call    x86_modrm_read_rm8
        ld      (x86_exec_alu_lhs8),a
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      c,a
        ld      a,(x86_exec_alu_lhs8)
        call    x86_alu_add8
        jp      x86_modrm_write_rm8

.add_r8_from_rm8:
        ; ADD r8,r/m8
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      (x86_exec_alu_lhs8),a
        call    x86_modrm_read_rm8
        ld      c,a
        ld      a,(x86_exec_alu_lhs8)
        call    x86_alu_add8
        ld      c,a
        ld      a,(x86_modrm_reg)
        jp      x86_modrm_write_reg8

.add_word:
        bit     1,a
        jr      nz,.add_r16_from_rm16

        ; ADD r/m16,r16
        call    x86_modrm_read_rm16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_reg16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        call    x86_alu_add16
        jp      x86_modrm_write_rm16

.add_r16_from_rm16:
        ; ADD r16,r/m16
        call    x86_modrm_read_reg16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_rm16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        call    x86_alu_add16
        jp      x86_modrm_write_reg16

.add_accumulator:
        bit     0,a
        jr      nz,.add_ax_immediate
        call    x86_cpu_fetch8
        ret     c
        ld      c,a
        ld      a,(x86_reg_ax)
        call    x86_alu_add8
        ld      (x86_reg_ax),a
        or      a
        ret
.add_ax_immediate:
        call    x86_cpu_fetch16
        ret     c
        ex      de,hl
        ld      hl,(x86_reg_ax)
        call    x86_alu_add16
        ld      (x86_reg_ax),hl
        or      a
        ret

; 28-2D SUB r/m,r and SUB AL/AX,imm; 38-3D CMP equivalents.
; CMP performs the same subtraction/flag calculation without committing
; the destination. Operand width and direction follow the opcode low bits.
x86_exec_subcmp_family:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_alu_opcode),a
        and     #10
        ld      (x86_exec_alu_is_cmp),a
        ld      a,(x86_exec_alu_opcode)
        bit     2,a
        jp      nz,.subcmp_accumulator

        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_exec_alu_opcode)
        bit     0,a
        jr      nz,.subcmp_word
        bit     1,a
        jr      nz,.subcmp_r8_from_rm8

        ; SUB/CMP r/m8,r8
        call    x86_modrm_read_rm8
        ld      (x86_exec_alu_lhs8),a
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      c,a
        ld      a,(x86_exec_alu_lhs8)
        call    x86_alu_sub8
        ld      c,a
        ld      a,(x86_exec_alu_is_cmp)
        or      a
        ret     nz
        ld      a,(x86_exec_alu_opcode)
        bit     1,a
        jp      nz,x86_modrm_write_reg8
        jp      x86_modrm_write_rm8

.subcmp_r8_from_rm8:
        ; SUB/CMP r8,r/m8
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      (x86_exec_alu_lhs8),a
        call    x86_modrm_read_rm8
        ld      c,a
        ld      a,(x86_exec_alu_lhs8)
        call    x86_alu_sub8
        ld      c,a
        ld      a,(x86_exec_alu_is_cmp)
        or      a
        ret     nz
        ld      a,(x86_modrm_reg)
        jp      x86_modrm_write_reg8

.subcmp_word:
        bit     1,a
        jr      nz,.subcmp_r16_from_rm16

        ; SUB/CMP r/m16,r16
        call    x86_modrm_read_rm16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_reg16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        call    x86_alu_sub16
        ld      (x86_exec_alu_result16),hl
        ld      a,(x86_exec_alu_is_cmp)
        or      a
        ret     nz
        ld      hl,(x86_exec_alu_result16)
        jp      x86_modrm_write_rm16

.subcmp_r16_from_rm16:
        ; SUB/CMP r16,r/m16
        call    x86_modrm_read_reg16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_rm16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        call    x86_alu_sub16
        ld      (x86_exec_alu_result16),hl
        ld      a,(x86_exec_alu_is_cmp)
        or      a
        ret     nz
        ld      hl,(x86_exec_alu_result16)
        jp      x86_modrm_write_reg16

.subcmp_accumulator:
        bit     0,a
        jr      nz,.subcmp_ax_immediate
        call    x86_cpu_fetch8
        ret     c
        ld      c,a
        ld      a,(x86_reg_ax)
        call    x86_alu_sub8
        ld      (x86_exec_alu_result8),a
        ld      a,(x86_exec_alu_is_cmp)
        or      a
        ret     nz
        ld      a,(x86_exec_alu_result8)
        ld      (x86_reg_ax),a
        or      a
        ret
.subcmp_ax_immediate:
        call    x86_cpu_fetch16
        ret     c
        ex      de,hl
        ld      hl,(x86_reg_ax)
        call    x86_alu_sub16
        ld      (x86_exec_alu_result16),hl
        ld      a,(x86_exec_alu_is_cmp)
        or      a
        ret     nz
        ld      hl,(x86_exec_alu_result16)
        ld      (x86_reg_ax),hl
        or      a
        ret

; 10-15 ADC and 18-1D SBB: ModR/M directions and accumulator immediate.
; Carry/borrow-in is captured from guest FLAGS before calling the ALU helper.
x86_exec_adc_sbb_family:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_alu_opcode),a
        cp      #18
        jr      c,.adc_select
        ld      a,1
        jr      .adc_sbb_selected
.adc_select:
        xor     a
.adc_sbb_selected:
        ld      (x86_exec_alu_is_sbb),a
        ld      a,(x86_exec_alu_opcode)
        bit     2,a
        jp      nz,.adc_sbb_accumulator

        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_exec_alu_opcode)
        bit     0,a
        jp      nz,.adc_sbb_word
        bit     1,a
        jr      nz,.adc_sbb_r8_from_rm8

        ; ADC/SBB r/m8,r8
        call    x86_modrm_read_rm8
        ld      (x86_exec_alu_lhs8),a
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      c,a
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     1
        ld      b,a
        ld      a,(x86_exec_alu_lhs8)
        call    x86_exec_adc_sbb8
        jp      x86_modrm_write_rm8

.adc_sbb_r8_from_rm8:
        ; ADC/SBB r8,r/m8
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      (x86_exec_alu_lhs8),a
        call    x86_modrm_read_rm8
        ld      c,a
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     1
        ld      b,a
        ld      a,(x86_exec_alu_lhs8)
        call    x86_exec_adc_sbb8
        ld      c,a
        ld      a,(x86_modrm_reg)
        jp      x86_modrm_write_reg8

.adc_sbb_word:
        bit     1,a
        jr      nz,.adc_sbb_r16_from_rm16

        ; ADC/SBB r/m16,r16
        call    x86_modrm_read_rm16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_reg16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        ld      a,(x86_reg_flags)
        and     1
        ld      b,a
        call    x86_exec_adc_sbb16
        jp      x86_modrm_write_rm16

.adc_sbb_r16_from_rm16:
        ; ADC/SBB r16,r/m16
        call    x86_modrm_read_reg16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_rm16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        ld      a,(x86_reg_flags)
        and     1
        ld      b,a
        call    x86_exec_adc_sbb16
        jp      x86_modrm_write_reg16

.adc_sbb_accumulator:
        bit     0,a
        jr      nz,.adc_sbb_ax_immediate
        call    x86_cpu_fetch8
        ret     c
        ld      c,a
        ld      a,(x86_reg_flags)
        and     1
        ld      b,a
        ld      a,(x86_reg_ax)
        ld      (x86_exec_adc_sbb_lhs8),a
        call    x86_exec_adc_sbb8
        ld      (x86_reg_ax),a
        or      a
        ret
.adc_sbb_ax_immediate:
        call    x86_cpu_fetch16
        ret     c
        ex      de,hl
        ld      hl,(x86_reg_ax)
        ld      (x86_exec_adc_sbb_lhs16),hl
        ld      a,(x86_reg_flags)
        and     1
        ld      b,a
        call    x86_exec_adc_sbb16
        ld      (x86_reg_ax),hl
        or      a
        ret

; Dispatch wrappers preserve the common A/C or HL/DE operand contracts.
x86_exec_adc_sbb8:
        ld      (x86_exec_adc_sbb_lhs8),a
        ld      a,(x86_exec_alu_is_sbb)
        or      a
        ld      a,(x86_exec_adc_sbb_lhs8)
        jp      nz,x86_alu_sbb8
        jp      x86_alu_adc8

x86_exec_adc_sbb16:
        ld      (x86_exec_adc_sbb_lhs16),hl
        ld      a,(x86_exec_alu_is_sbb)
        or      a
        ld      hl,(x86_exec_adc_sbb_lhs16)
        jp      nz,x86_alu_sbb16
        jp      x86_alu_adc16

; 06/0E/16/1E PUSH ES/CS/SS/DS; 07/17/1F POP ES/SS/DS.
; POP SS arms the same one-instruction interrupt-inhibit latch as MOV SS.
x86_exec_push_segment:
        ld      a,(x86_exec_opcode)
        cp      #06
        jr      z,.push_es
        cp      #0E
        jr      z,.push_cs
        cp      #16
        jr      z,.push_ss
        ld      hl,(x86_reg_ds)
        jp      x86_exec_push_word
.push_es:
        ld      hl,(x86_reg_es)
        jp      x86_exec_push_word
.push_cs:
        ld      hl,(x86_reg_cs)
        jp      x86_exec_push_word
.push_ss:
        ld      hl,(x86_reg_ss)
        jp      x86_exec_push_word

x86_exec_pop_segment:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_segment_pop_opcode),a
        call    x86_exec_pop_word
        ret     c
        ld      a,(x86_exec_segment_pop_opcode)
        cp      #07
        jr      z,.pop_es
        cp      #17
        jr      z,.pop_ss
        ld      (x86_reg_ds),hl
        or      a
        ret
.pop_es:
        ld      (x86_reg_es),hl
        or      a
        ret
.pop_ss:
        ld      (x86_reg_ss),hl
        ld      a,1
        ld      (x86_irq_inhibit),a
        or      a
        ret

; POP helper: reads SS:SP, advances SP by two, returns word in HL.
x86_exec_pop_word:
        ld      hl,(x86_reg_sp)
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value),a
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value+1),a
        ld      hl,(x86_reg_sp)
        inc     hl
        inc     hl
        ld      (x86_reg_sp),hl
        ld      hl,(x86_exec_stack_value)
        or      a
        ret

; 27 DAA, 2F DAS, 37 AAA, 3F AAS.
; Decimal-adjust behavior follows PCem's original 8086 path.
x86_exec_daa:
        ld      hl,(x86_reg_flags)
        bit     4,l
        jr      nz,.daa_low_adjust
        ld      a,(x86_reg_ax)
        and     #0F
        cp      10
        jr      c,.daa_high_test
.daa_low_adjust:
        ld      a,(x86_reg_ax)
        add     a,6
        ld      (x86_reg_ax),a
        push    af
        pop     bc
        bit     0,c
        jr      z,.daa_low_no_carry
        call    x86_exec_set_cf
.daa_low_no_carry:
        call    x86_exec_set_af
.daa_high_test:
        ld      hl,(x86_reg_flags)
        bit     0,l
        jr      nz,.daa_high_adjust
        ld      a,(x86_reg_ax)
        cp      #A0
        jr      c,.daa_done
.daa_high_adjust:
        ld      a,(x86_reg_ax)
        add     a,#60
        ld      (x86_reg_ax),a
        call    x86_exec_set_cf
.daa_done:
        ld      a,(x86_reg_ax)
        jp      x86_exec_update_szp8

x86_exec_das:
        ld      hl,(x86_reg_flags)
        bit     4,l
        jr      nz,.das_low_adjust
        ld      a,(x86_reg_ax)
        and     #0F
        cp      10
        jr      c,.das_high_test
.das_low_adjust:
        ld      a,(x86_reg_ax)
        sub     6
        ld      (x86_reg_ax),a
        push    af
        pop     bc
        bit     0,c
        jr      z,.das_low_no_borrow
        call    x86_exec_set_cf
.das_low_no_borrow:
        call    x86_exec_set_af
.das_high_test:
        ld      hl,(x86_reg_flags)
        bit     0,l
        jr      nz,.das_high_adjust
        ld      a,(x86_reg_ax)
        cp      #A0
        jr      c,.das_done
.das_high_adjust:
        ld      a,(x86_reg_ax)
        sub     #60
        ld      (x86_reg_ax),a
        call    x86_exec_set_cf
.das_done:
        ld      a,(x86_reg_ax)
        jp      x86_exec_update_szp8

x86_exec_aaa:
        ld      hl,(x86_reg_flags)
        bit     4,l
        jr      nz,.aaa_adjust
        ld      a,(x86_reg_ax)
        and     #0F
        cp      10
        jr      c,.aaa_no_adjust
.aaa_adjust:
        ld      a,(x86_reg_ax)
        add     a,6
        ld      (x86_reg_ax),a
        ld      a,(x86_reg_ax+1)
        inc     a
        ld      (x86_reg_ax+1),a
        call    x86_exec_set_cf
        call    x86_exec_set_af
        jr      .aaa_mask_al
.aaa_no_adjust:
        call    x86_exec_clear_cf_af
.aaa_mask_al:
        ld      a,(x86_reg_ax)
        and     #0F
        ld      (x86_reg_ax),a
        or      a
        ret

x86_exec_aas:
        ld      hl,(x86_reg_flags)
        bit     4,l
        jr      nz,.aas_adjust
        ld      a,(x86_reg_ax)
        and     #0F
        cp      10
        jr      c,.aas_no_adjust
.aas_adjust:
        ld      a,(x86_reg_ax)
        sub     6
        ld      (x86_reg_ax),a
        ld      a,(x86_reg_ax+1)
        dec     a
        ld      (x86_reg_ax+1),a
        call    x86_exec_set_cf
        call    x86_exec_set_af
        jr      .aas_mask_al
.aas_no_adjust:
        call    x86_exec_clear_cf_af
.aas_mask_al:
        ld      a,(x86_reg_ax)
        and     #0F
        ld      (x86_reg_ax),a
        or      a
        ret

x86_exec_set_cf:
        ld      hl,(x86_reg_flags)
        set     0,l
        ld      (x86_reg_flags),hl
        ret

x86_exec_set_af:
        ld      hl,(x86_reg_flags)
        set     4,l
        ld      (x86_reg_flags),hl
        ret

x86_exec_clear_cf_af:
        ld      hl,(x86_reg_flags)
        res     0,l
        res     4,l
        ld      (x86_reg_flags),hl
        ret

; Input A=result. Update only SF/ZF/PF, preserving CF/AF/OF and control flags.
x86_exec_update_szp8:
        or      a
        push    af
        pop     bc
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     #9B
        ld      l,a
        bit     2,c
        jr      z,.szp_no_pf
        set     2,l
.szp_no_pf:
        bit     6,c
        jr      z,.szp_no_zf
        set     6,l
.szp_no_zf:
        bit     7,c
        jr      z,.szp_no_sf
        set     7,l
.szp_no_sf:
        ld      (x86_reg_flags),hl
        or      a
        ret

; F6/F7 Group 3 initial 8086 forms:
; /0,/1 TEST r/m,immediate; /2 NOT r/m; /3 NEG r/m.
; /4-/7 MUL/IMUL/DIV/IDIV are reserved for the next arithmetic tranche.
x86_exec_group3:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_group3_opcode),a
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_modrm_reg)
        ld      (x86_exec_group3_ext),a
        cp      0
        jp      z,x86_exec_group3_test
        cp      1
        jp      z,x86_exec_group3_test
        cp      2
        jp      z,x86_exec_group3_not
        cp      3
        jp      z,x86_exec_group3_neg
        scf
        ret

x86_exec_group3_test:
        ld      a,(x86_exec_group3_opcode)
        bit     0,a
        jr      nz,.group3_test_word
        call    x86_cpu_fetch8
        ret     c
        ld      (x86_exec_group3_imm8),a
        call    x86_modrm_read_rm8
        ld      (x86_exec_group3_value8),a
        ld      a,(x86_exec_group3_imm8)
        ld      c,a
        ld      a,(x86_exec_group3_value8)
        ld      b,1
        call    x86_alu_logic8
        or      a
        ret
.group3_test_word:
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_group3_imm16),hl
        call    x86_modrm_read_rm16
        ld      de,(x86_exec_group3_imm16)
        ld      b,1
        call    x86_alu_logic16
        or      a
        ret

x86_exec_group3_not:
        ld      a,(x86_exec_group3_opcode)
        bit     0,a
        jr      nz,.group3_not_word
        call    x86_modrm_read_rm8
        cpl
        jp      x86_modrm_write_rm8
.group3_not_word:
        call    x86_modrm_read_rm16
        ld      a,l
        cpl
        ld      l,a
        ld      a,h
        cpl
        ld      h,a
        jp      x86_modrm_write_rm16

x86_exec_group3_neg:
        ld      a,(x86_exec_group3_opcode)
        bit     0,a
        jr      nz,.group3_neg_word
        call    x86_modrm_read_rm8
        ld      c,a
        xor     a
        call    x86_alu_sub8
        jp      x86_modrm_write_rm8
.group3_neg_word:
        call    x86_modrm_read_rm16
        ex      de,hl
        ld      hl,0
        call    x86_alu_sub16
        jp      x86_modrm_write_rm16

; FE Group 4: INC/DEC r/m8.
; FF Group 5: INC/DEC, near/far CALL/JMP and PUSH r/m16.
x86_exec_group4_5:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_group45_opcode),a
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_modrm_reg)
        ld      (x86_exec_group45_ext),a
        ld      a,(x86_exec_group45_opcode)
        cp      #FE
        jp      z,x86_exec_group4_byte

        ld      a,(x86_exec_group45_ext)
        cp      0
        jp      z,x86_exec_group5_incdec
        cp      1
        jp      z,x86_exec_group5_incdec
        cp      2
        jp      z,x86_exec_group5_call_near
        cp      3
        jp      z,x86_exec_group5_call_far
        cp      4
        jp      z,x86_exec_group5_jmp_near
        cp      5
        jp      z,x86_exec_group5_jmp_far
        cp      6
        jp      z,x86_exec_group5_push
        scf
        ret

x86_exec_group4_byte:
        ld      a,(x86_exec_group45_ext)
        cp      0
        jr      z,.group4_inc
        cp      1
        jr      nz,.group4_invalid
        call    x86_modrm_read_rm8
        ld      (x86_exec_group45_value8),a
        call    x86_exec_group45_save_cf
        ld      a,(x86_exec_group45_value8)
        ld      c,1
        call    x86_alu_sub8
        ld      (x86_exec_group45_value8),a
        call    x86_exec_group45_restore_cf
        ld      a,(x86_exec_group45_value8)
        jp      x86_modrm_write_rm8
.group4_inc:
        call    x86_modrm_read_rm8
        ld      (x86_exec_group45_value8),a
        call    x86_exec_group45_save_cf
        ld      a,(x86_exec_group45_value8)
        ld      c,1
        call    x86_alu_add8
        ld      (x86_exec_group45_value8),a
        call    x86_exec_group45_restore_cf
        ld      a,(x86_exec_group45_value8)
        jp      x86_modrm_write_rm8
.group4_invalid:
        scf
        ret

x86_exec_group5_incdec:
        call    x86_modrm_read_rm16
        ld      (x86_exec_group45_value16),hl
        call    x86_exec_group45_save_cf
        ld      hl,(x86_exec_group45_value16)
        ld      de,1
        ld      a,(x86_exec_group45_ext)
        or      a
        jr      nz,.group5_dec
        call    x86_alu_add16
        jr      .group5_incdec_done
.group5_dec:
        call    x86_alu_sub16
.group5_incdec_done:
        ld      (x86_exec_group45_value16),hl
        call    x86_exec_group45_restore_cf
        ld      hl,(x86_exec_group45_value16)
        jp      x86_modrm_write_rm16

x86_exec_group5_call_near:
        call    x86_modrm_read_rm16
        ld      (x86_exec_target_ip),hl
        ld      hl,(x86_reg_ip)
        call    x86_exec_push_word
        ret     c
        ld      hl,(x86_exec_target_ip)
        ld      (x86_reg_ip),hl
        or      a
        ret

x86_exec_group5_call_far:
        ld      a,(x86_ea_is_reg)
        or      a
        jr      nz,.group5_far_invalid
        call    x86_modrm_read_rm16
        ld      (x86_exec_target_ip),hl
        ld      hl,(x86_ea_offset)
        inc     hl
        inc     hl
        ld      (x86_ea_offset),hl
        call    x86_modrm_read_rm16
        ld      (x86_exec_target_cs),hl
        ld      hl,(x86_reg_cs)
        call    x86_exec_push_word
        ret     c
        ld      hl,(x86_reg_ip)
        call    x86_exec_push_word
        ret     c
        ld      hl,(x86_exec_target_cs)
        ld      (x86_reg_cs),hl
        ld      hl,(x86_exec_target_ip)
        ld      (x86_reg_ip),hl
        or      a
        ret
.group5_far_invalid:
        scf
        ret

x86_exec_group5_jmp_near:
        call    x86_modrm_read_rm16
        ld      (x86_reg_ip),hl
        or      a
        ret

x86_exec_group5_jmp_far:
        ld      a,(x86_ea_is_reg)
        or      a
        jr      nz,.group5_jmp_far_invalid
        call    x86_modrm_read_rm16
        ld      (x86_exec_target_ip),hl
        ld      hl,(x86_ea_offset)
        inc     hl
        inc     hl
        ld      (x86_ea_offset),hl
        call    x86_modrm_read_rm16
        ld      (x86_exec_target_cs),hl
        ld      hl,(x86_exec_target_cs)
        ld      (x86_reg_cs),hl
        ld      hl,(x86_exec_target_ip)
        ld      (x86_reg_ip),hl
        or      a
        ret
.group5_jmp_far_invalid:
        scf
        ret

x86_exec_group5_push:
        call    x86_modrm_read_rm16
        jp      x86_exec_push_word

; PUSH helper: HL=value, decrements SP before writing low/high bytes to SS.
x86_exec_push_word:
        ld      (x86_exec_stack_value),hl
        ld      hl,(x86_reg_sp)
        dec     hl
        dec     hl
        ld      (x86_reg_sp),hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value+1)
        call    x86_guest_mem_write8
        ret

x86_exec_group45_save_cf:
        ld      a,(x86_reg_flags)
        and     1
        ld      (x86_exec_saved_cf),a
        ret

x86_exec_group45_restore_cf:
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     #FE
        ld      l,a
        ld      a,(x86_exec_saved_cf)
        or      l
        ld      l,a
        ld      (x86_reg_flags),hl
        ret

; 80/82 Group 1 byte immediate; 81 word immediate; 83 sign-extended
; byte immediate to word. ModR/M /0..7 select ADD/OR/ADC/SBB/AND/SUB/XOR/CMP.
x86_exec_group1_immediate:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_group1_opcode),a
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_modrm_reg)
        ld      (x86_exec_group1_ext),a
        cp      7
        jr      nz,.group1_not_cmp
        ld      a,1
        jr      .group1_cmp_set
.group1_not_cmp:
        xor     a
.group1_cmp_set:
        ld      (x86_exec_group1_is_cmp),a

        ld      a,(x86_exec_group1_opcode)
        cp      #81
        jr      z,.group1_word_immediate
        cp      #83
        jr      z,.group1_signext_immediate

        ; 80/82: byte immediate.
        call    x86_cpu_fetch8
        ret     c
        ld      (x86_exec_group1_imm8),a
        call    x86_modrm_read_rm8
        ld      (x86_exec_group1_lhs8),a
        ld      a,(x86_exec_group1_imm8)
        ld      c,a
        ld      a,(x86_exec_group1_lhs8)
        call    x86_exec_group1_apply8
        ld      a,(x86_exec_group1_is_cmp)
        or      a
        ret     nz
        jp      x86_modrm_write_rm8

.group1_word_immediate:
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_group1_imm16),hl
        jr      .group1_apply_word

.group1_signext_immediate:
        call    x86_cpu_fetch8
        ret     c
        ld      l,a
        ld      h,0
        bit     7,a
        jr      z,.group1_signext_ready
        ld      h,#FF
.group1_signext_ready:
        ld      (x86_exec_group1_imm16),hl

.group1_apply_word:
        call    x86_modrm_read_rm16
        ld      de,(x86_exec_group1_imm16)
        call    x86_exec_group1_apply16
        ld      a,(x86_exec_group1_is_cmp)
        or      a
        ret     nz
        jp      x86_modrm_write_rm16

; A=left, C=immediate; returns result in A and updates guest FLAGS.
x86_exec_group1_apply8:
        ld      (x86_exec_group1_lhs8),a
        ld      a,c
        ld      (x86_exec_group1_rhs8),a
        ld      a,(x86_exec_group1_ext)
        cp      0
        jp      z,.group1_add8
        cp      1
        jp      z,.group1_or8
        cp      2
        jp      z,.group1_adc8
        cp      3
        jp      z,.group1_sbb8
        cp      4
        jp      z,.group1_and8
        cp      5
        jp      z,.group1_sub8
        cp      6
        jp      z,.group1_xor8
        jr      .group1_cmp8
.group1_add8:
        ld      a,(x86_exec_group1_rhs8)
        ld      c,a
        ld      a,(x86_exec_group1_lhs8)
        jp      x86_alu_add8
.group1_or8:
        ld      a,(x86_exec_group1_rhs8)
        ld      c,a
        ld      a,(x86_exec_group1_lhs8)
        ld      b,0
        jp      x86_alu_logic8
.group1_adc8:
        ld      a,(x86_exec_group1_rhs8)
        ld      c,a
        ld      a,(x86_reg_flags)
        and     1
        ld      b,a
        ld      a,(x86_exec_group1_lhs8)
        jp      x86_alu_adc8
.group1_sbb8:
        ld      a,(x86_exec_group1_rhs8)
        ld      c,a
        ld      a,(x86_reg_flags)
        and     1
        ld      b,a
        ld      a,(x86_exec_group1_lhs8)
        jp      x86_alu_sbb8
.group1_and8:
        ld      a,(x86_exec_group1_rhs8)
        ld      c,a
        ld      a,(x86_exec_group1_lhs8)
        ld      b,1
        jp      x86_alu_logic8
.group1_sub8:
.group1_cmp8:
        ld      a,(x86_exec_group1_rhs8)
        ld      c,a
        ld      a,(x86_exec_group1_lhs8)
        jp      x86_alu_sub8
.group1_xor8:
        ld      a,(x86_exec_group1_rhs8)
        ld      c,a
        ld      a,(x86_exec_group1_lhs8)
        ld      b,2
        jp      x86_alu_logic8

; HL=left, DE=immediate; returns result in HL and updates guest FLAGS.
x86_exec_group1_apply16:
        ld      (x86_exec_group1_lhs16),hl
        ld      (x86_exec_group1_rhs16),de
        ld      a,(x86_exec_group1_ext)
        cp      0
        jp      z,.group1_add16
        cp      1
        jp      z,.group1_or16
        cp      2
        jp      z,.group1_adc16
        cp      3
        jp      z,.group1_sbb16
        cp      4
        jp      z,.group1_and16
        cp      5
        jp      z,.group1_sub16
        cp      6
        jp      z,.group1_xor16
        jr      .group1_cmp16
.group1_add16:
        ld      hl,(x86_exec_group1_lhs16)
        ld      de,(x86_exec_group1_rhs16)
        jp      x86_alu_add16
.group1_or16:
        ld      hl,(x86_exec_group1_lhs16)
        ld      de,(x86_exec_group1_rhs16)
        ld      b,0
        jp      x86_alu_logic16
.group1_adc16:
        ld      hl,(x86_exec_group1_lhs16)
        ld      de,(x86_exec_group1_rhs16)
        ld      a,(x86_reg_flags)
        and     1
        ld      b,a
        jp      x86_alu_adc16
.group1_sbb16:
        ld      hl,(x86_exec_group1_lhs16)
        ld      de,(x86_exec_group1_rhs16)
        ld      a,(x86_reg_flags)
        and     1
        ld      b,a
        jp      x86_alu_sbb16
.group1_and16:
        ld      hl,(x86_exec_group1_lhs16)
        ld      de,(x86_exec_group1_rhs16)
        ld      b,1
        jp      x86_alu_logic16
.group1_sub16:
.group1_cmp16:
        ld      hl,(x86_exec_group1_lhs16)
        ld      de,(x86_exec_group1_rhs16)
        jp      x86_alu_sub16
.group1_xor16:
        ld      hl,(x86_exec_group1_lhs16)
        ld      de,(x86_exec_group1_rhs16)
        ld      b,2
        jp      x86_alu_logic16

; OR 08-0D, AND 20-25, XOR 30-35, TEST 84-85.
; Each operation uses the shared logical ALU helpers, which clear CF/AF/OF
; and update SF/ZF/PF. TEST never writes its destination.
x86_exec_logic_family:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_alu_opcode),a
        cp      #20
        jr      c,.logic_is_or
        cp      #30
        jr      c,.logic_is_and
        cp      #36
        jr      nc,.logic_is_test
        ld      a,2
        jr      .logic_operation_ready
.logic_is_or:
        xor     a
        jr      .logic_operation_ready
.logic_is_and:
        ld      a,1
        jr      .logic_operation_ready
.logic_is_test:
        ld      a,1
.logic_operation_ready:
        ld      (x86_exec_alu_operation),a
        ld      a,(x86_exec_alu_opcode)
        cp      #84
        jp      z,.logic_test_rm_reg
        cp      #85
        jp      z,.logic_test_rm_reg
        bit     2,a
        jp      nz,.logic_accumulator_immediate

        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_exec_alu_opcode)
        bit     0,a
        jp      nz,.logic_word
        bit     1,a
        jr      nz,.logic_r8_from_rm8

        ; OR/AND/XOR r/m8,r8
        call    x86_modrm_read_rm8
        ld      (x86_exec_alu_lhs8),a
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      c,a
        ld      a,(x86_exec_alu_operation)
        ld      b,a
        ld      a,(x86_exec_alu_lhs8)
        call    x86_alu_logic8
        jp      x86_modrm_write_rm8

.logic_r8_from_rm8:
        ; OR/AND/XOR r8,r/m8
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      (x86_exec_alu_lhs8),a
        call    x86_modrm_read_rm8
        ld      c,a
        ld      a,(x86_exec_alu_operation)
        ld      b,a
        ld      a,(x86_exec_alu_lhs8)
        call    x86_alu_logic8
        ld      c,a
        ld      a,(x86_modrm_reg)
        jp      x86_modrm_write_reg8

.logic_word:
        bit     1,a
        jr      nz,.logic_r16_from_rm16

        ; OR/AND/XOR r/m16,r16
        call    x86_modrm_read_rm16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_reg16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        ld      a,(x86_exec_alu_operation)
        ld      b,a
        call    x86_alu_logic16
        jp      x86_modrm_write_rm16

.logic_r16_from_rm16:
        ; OR/AND/XOR r16,r/m16
        call    x86_modrm_read_reg16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_rm16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        ld      a,(x86_exec_alu_operation)
        ld      b,a
        call    x86_alu_logic16
        jp      x86_modrm_write_reg16

.logic_test_rm_reg:
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_exec_alu_opcode)
        bit     0,a
        jr      nz,.logic_test_word
        call    x86_modrm_read_rm8
        ld      (x86_exec_alu_lhs8),a
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      c,a
        ld      a,(x86_exec_alu_lhs8)
        ld      b,1
        call    x86_alu_logic8
        or      a
        ret
.logic_test_word:
        call    x86_modrm_read_rm16
        ld      (x86_exec_alu_lhs16),hl
        call    x86_modrm_read_reg16
        ex      de,hl
        ld      hl,(x86_exec_alu_lhs16)
        ld      b,1
        call    x86_alu_logic16
        or      a
        ret

.logic_accumulator_immediate:
        bit     0,a
        jr      nz,.logic_ax_immediate
        call    x86_cpu_fetch8
        ret     c
        ld      c,a
        ld      a,(x86_exec_alu_operation)
        ld      b,a
        ld      a,(x86_reg_ax)
        call    x86_alu_logic8
        ld      (x86_reg_ax),a
        or      a
        ret
.logic_ax_immediate:
        call    x86_cpu_fetch16
        ret     c
        ex      de,hl
        ld      hl,(x86_reg_ax)
        ld      a,(x86_exec_alu_operation)
        ld      b,a
        call    x86_alu_logic16
        ld      (x86_reg_ax),hl
        or      a
        ret

; 88/89 MOV r/m8/16,r8/16; 8A/8B MOV r8/16,r/m8/16.
; Every form uses the common 8086 ModR/M decoder and operand accessors.
x86_exec_mov_rm_reg:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_mov_opcode),a
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_exec_mov_opcode)
        bit     0,a
        jr      nz,.mov_word

        ; Byte transfer. Bit 1 selects direction.
        bit     1,a
        jr      nz,.mov_r8_from_rm8
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        jp      x86_modrm_write_rm8
.mov_r8_from_rm8:
        call    x86_modrm_read_rm8
        ld      c,a
        ld      a,(x86_modrm_reg)
        jp      x86_modrm_write_reg8

.mov_word:
        bit     1,a
        jr      nz,.mov_r16_from_rm16
        call    x86_modrm_read_reg16
        jp      x86_modrm_write_rm16
.mov_r16_from_rm16:
        call    x86_modrm_read_rm16
        jp      x86_modrm_write_reg16

; 8C MOV r/m16,Sreg; 8E MOV Sreg,r/m16.
; 8086 segment-register encoding: ES=0, CS=1, SS=2, DS=3.
; MOV into CS (/1 with opcode 8E) is invalid. Loading SS arms the
; one-instruction maskable-interrupt inhibition latch for interrupt logic.
x86_exec_mov_sreg_rm:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_sreg_opcode),a
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_modrm_reg)
        cp      4
        jr      nc,.mov_sreg_invalid
        ld      (x86_exec_sreg_index),a

        ld      a,(x86_exec_sreg_opcode)
        bit     1,a
        jr      nz,.mov_sreg_from_rm

        ; 8C: segment register -> r/m16.
        ld      a,(x86_exec_sreg_index)
        call    x86_exec_sreg_get_pointer
        ld      hl,(x86_exec_sreg_ptr)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        jp      x86_modrm_write_rm16

.mov_sreg_from_rm:
        ld      a,(x86_exec_sreg_index)
        cp      1
        jr      z,.mov_sreg_invalid
        call    x86_modrm_read_rm16
        ld      (x86_exec_sreg_value),hl
        ld      a,(x86_exec_sreg_index)
        call    x86_exec_sreg_get_pointer
        ld      hl,(x86_exec_sreg_ptr)
        ld      de,(x86_exec_sreg_value)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      a,(x86_exec_sreg_index)
        cp      2
        jr      nz,.mov_sreg_done
        ld      a,1
        ld      (x86_irq_inhibit),a
.mov_sreg_done:
        or      a
        ret

.mov_sreg_invalid:
        scf
        ret

; A=segment-register index, stores its pointer in x86_exec_sreg_ptr.
x86_exec_sreg_get_pointer:
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_exec_sreg_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (x86_exec_sreg_ptr),de
        ret

; 8F POP r/m16. Only ModR/M extension /0 is defined on the 8086.
; Resolve EA before advancing SP, then commit the popped word.
x86_exec_pop_rm16:
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_modrm_reg)
        or      a
        jr      nz,.pop_rm_invalid
        ld      hl,(x86_reg_sp)
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value),a
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value+1),a
        ld      hl,(x86_reg_sp)
        inc     hl
        inc     hl
        ld      (x86_reg_sp),hl
        ld      hl,(x86_exec_stack_value)
        jp      x86_modrm_write_rm16
.pop_rm_invalid:
        scf
        ret

; 86/87 XCHG r/m8/16,r8/16. FLAGS are not modified.
; Memory forms use the same guest-memory accessors as MOV.
x86_exec_xchg_rm_reg:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_xchg_opcode),a
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_exec_xchg_opcode)
        bit     0,a
        jr      nz,.xchg_word

        call    x86_modrm_read_rm8
        ld      (x86_exec_xchg_rm_byte),a
        ld      a,(x86_modrm_reg)
        call    x86_modrm_read_reg8
        ld      (x86_exec_xchg_reg_byte),a
        jp      x86_exec_xchg_commit8

.xchg_word:
        call    x86_modrm_read_rm16
        ld      (x86_exec_xchg_rm_word),hl
        call    x86_modrm_read_reg16
        ld      (x86_exec_xchg_reg_word),hl
        ld      hl,(x86_exec_xchg_reg_word)
        call    x86_modrm_write_rm16
        ld      hl,(x86_exec_xchg_rm_word)
        jp      x86_modrm_write_reg16

x86_exec_xchg_commit8:
        ld      a,(x86_exec_xchg_reg_byte)
        call    x86_modrm_write_rm8
        ld      a,(x86_exec_xchg_rm_byte)
        ld      c,a
        ld      a,(x86_modrm_reg)
        jp      x86_modrm_write_reg8

; 8D LEA r16,m. The source must be a memory effective address;
; the segment is not used and no memory read is performed.
x86_exec_lea:
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_ea_is_reg)
        or      a
        jr      nz,.lea_invalid
        ld      hl,(x86_ea_offset)
        jp      x86_modrm_write_reg16
.lea_invalid:
        scf
        ret

; C4 LES r16,m16:16; C5 LDS r16,m16:16.
; ModR/M must select memory. The first word is the offset, followed by
; the segment word at EA+2 (16-bit offset wrap).
x86_exec_les_lds:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_les_lds_opcode),a
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_ea_is_reg)
        or      a
        jr      nz,.les_lds_invalid

        call    x86_modrm_read_rm16
        ld      (x86_exec_les_lds_offset),hl
        ld      hl,(x86_ea_offset)
        inc     hl
        inc     hl
        ld      (x86_ea_offset),hl
        call    x86_modrm_read_rm16
        ld      (x86_exec_les_lds_segment),hl

        ld      hl,(x86_exec_les_lds_offset)
        call    x86_modrm_write_reg16
        ld      a,(x86_exec_les_lds_opcode)
        cp      #C4
        jr      nz,.les_lds_to_ds
        ld      hl,(x86_exec_les_lds_segment)
        ld      (x86_reg_es),hl
        or      a
        ret
.les_lds_to_ds:
        ld      hl,(x86_exec_les_lds_segment)
        ld      (x86_reg_ds),hl
        or      a
        ret
.les_lds_invalid:
        scf
        ret

; C6/C7 MOV r/m8/16, immediate. The ModR/M extension field must be /0.
x86_exec_mov_imm_rm:
        call    x86_decode_modrm16
        ret     c
        ld      a,(x86_modrm_reg)
        or      a
        jr      nz,.mov_imm_rm_invalid
        ld      a,(x86_exec_opcode)
        bit     0,a
        jr      nz,.mov_imm_rm_word
        call    x86_cpu_fetch8
        ret     c
        jp      x86_modrm_write_rm8
.mov_imm_rm_word:
        call    x86_cpu_fetch16
        ret     c
        jp      x86_modrm_write_rm16
.mov_imm_rm_invalid:
        scf
        ret

; 9A CALL FAR ptr16:16. The return IP is the address after both immediates.
; Stack layout after the call is [SS:SP]=return IP, [SS:SP+2]=old CS.
x86_exec_call_far_imm:
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_target_ip),hl
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_target_cs),hl

        ld      hl,(x86_reg_sp)
        ld      de,4
        or      a
        sbc     hl,de
        ld      (x86_exec_stack_offset),hl
        ld      (x86_exec_stack_new_sp),hl

        ; Store return IP at new SS:SP.
        ld      hl,(x86_reg_ip)
        ld      (x86_exec_stack_value),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value+1)
        call    x86_guest_mem_write8
        ret     c

        ; Store old CS at new SS:SP+2.
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        ld      hl,(x86_reg_cs)
        ld      (x86_exec_stack_value),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value+1)
        call    x86_guest_mem_write8
        ret     c

        ld      hl,(x86_exec_stack_new_sp)
        ld      (x86_reg_sp),hl
        ld      hl,(x86_exec_target_cs)
        ld      (x86_reg_cs),hl
        ld      hl,(x86_exec_target_ip)
        ld      (x86_reg_ip),hl
        or      a
        ret

; 9B WAIT is a no-op on the PCem 8086 path (no external 8087 device).
x86_exec_wait:
        or      a
        ret

; C1/C3 RET near aliases; C2 RET near imm16.
; Return IP is read from SS:SP, then SP advances by 2 plus optional cleanup.
x86_exec_ret_near:
        ld      a,(x86_exec_opcode)
        cp      #C2
        jr      nz,.ret_near_no_adjust
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_ret_adjust),hl
        jr      .ret_near_read
.ret_near_no_adjust:
        ld      hl,0
        ld      (x86_exec_ret_adjust),hl
.ret_near_read:
        ld      hl,(x86_reg_sp)
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value),a
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value+1),a
        ld      hl,(x86_exec_stack_value)
        ld      (x86_reg_ip),hl
        ld      hl,(x86_reg_sp)
        inc     hl
        inc     hl
        ld      de,(x86_exec_ret_adjust)
        add     hl,de
        ld      (x86_reg_sp),hl
        or      a
        ret

; C8/C9 RETF aliases; CA RETF imm16; CB RETF.
; Stack contains return IP followed by return CS.
x86_exec_ret_far:
        ld      a,(x86_exec_opcode)
        cp      #CA
        jr      nz,.ret_far_no_adjust
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_ret_adjust),hl
        jr      .ret_far_read
.ret_far_no_adjust:
        ld      hl,0
        ld      (x86_exec_ret_adjust),hl
.ret_far_read:
        ld      hl,(x86_reg_sp)
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value),a
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value+1),a

        ld      hl,(x86_reg_sp)
        inc     hl
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_target_cs),a
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_target_cs+1),a

        ld      hl,(x86_exec_stack_value)
        ld      (x86_reg_ip),hl
        ld      hl,(x86_exec_target_cs)
        ld      (x86_reg_cs),hl
        ld      hl,(x86_reg_sp)
        ld      de,4
        add     hl,de
        ld      de,(x86_exec_ret_adjust)
        add     hl,de
        ld      (x86_reg_sp),hl
        or      a
        ret

; 98 CBW: sign-extend AL into AH. 99 CWD: sign-extend AX into DX.
x86_exec_cbw:
        ld      a,(x86_reg_ax)
        rlca
        sbc     a,a
        ld      (x86_reg_ax+1),a
        or      a
        ret

x86_exec_cwd:
        ld      hl,(x86_reg_ax)
        bit     7,h
        jr      z,.cwd_zero
        ld      hl,#FFFF
        jr      .cwd_store
.cwd_zero:
        ld      hl,0
.cwd_store:
        ld      (x86_reg_dx),hl
        or      a
        ret

; PUSHF / POPF follow the PCem 8086 implementation:
; PUSHF stores FLAGS|F000 at SS:(SP-2); POPF loads word&0FFF from SS:SP.
x86_exec_pushf:
        ld      hl,(x86_reg_sp)
        dec     hl
        dec     hl
        ld      (x86_reg_sp),hl
        ld      (x86_exec_stack_offset),hl
        ; Set the high reserved bits without changing the guest flags.
        ld      hl,(x86_reg_flags)
        ld      a,h
        or      #F0
        ld      h,a
        ld      (x86_exec_stack_value),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value+1)
        call    x86_guest_mem_write8
        ret

x86_exec_popf:
        ld      hl,(x86_reg_sp)
        ld      (x86_exec_stack_offset),hl
        inc     hl
        inc     hl
        ld      (x86_reg_sp),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value),a
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value+1),a
        ld      hl,(x86_exec_stack_value)
        ld      a,h
        and     #0F
        ld      h,a
        ld      (x86_reg_flags),hl
        or      a
        ret

; SAHF copies AH into FLAGS[7:0]; LAHF copies FLAGS[7:0] into AH.
x86_exec_sahf:
        ld      hl,(x86_reg_flags)
        ld      a,(x86_reg_ax+1)
        ld      l,a
        ld      (x86_reg_flags),hl
        or      a
        ret

x86_exec_lahf:
        ld      hl,(x86_reg_flags)
        ld      a,l
        ld      (x86_reg_ax+1),a
        or      a
        ret

; D7 XLAT: AL = byte at DS:(BX+AL), with 16-bit offset wrap.
x86_exec_xlat:
        ld      hl,(x86_reg_bx)
        ld      a,(x86_reg_ax)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (x86_exec_moffs_offset),hl
        call    x86_exec_moffs_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_reg_ax),a
        or      a
        ret

; F5 CMC and F8-FD CLC/STC/CLI/STI/CLD/STD.
; CF=FLAGS bit 0, IF=bit 9, DF=bit 10.
x86_exec_cmc:
        ld      hl,(x86_reg_flags)
        ld      a,l
        xor     1
        ld      l,a
        ld      (x86_reg_flags),hl
        or      a
        ret

x86_exec_flag_control:
        ld      a,(x86_exec_opcode)
        ld      hl,(x86_reg_flags)
        cp      #F8
        jr      z,.flag_clc
        cp      #F9
        jr      z,.flag_stc
        cp      #FA
        jr      z,.flag_cli
        cp      #FB
        jr      z,.flag_sti
        cp      #FC
        jr      z,.flag_cld
        ; FD STD
        set     2,h
        jr      .flag_store
.flag_clc:
        res     0,l
        jr      .flag_store
.flag_stc:
        set     0,l
        jr      .flag_store
.flag_cli:
        res     1,h
        jr      .flag_store
.flag_sti:
        set     1,h
        jr      .flag_store
.flag_cld:
        res     2,h
.flag_store:
        ld      (x86_reg_flags),hl
        or      a
        ret

; A8 TEST AL,imm8; A9 TEST AX,imm16.
; TEST updates SF/ZF/PF and clears CF/OF/AF; operands are not modified.
x86_exec_test_al_imm:
        call    x86_cpu_fetch8
        ret     c
        ld      c,a
        ld      a,(x86_reg_ax)
        and     c
        ld      (x86_exec_test_result),a
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     #2A
        ld      l,a
        ld      a,h
        and     #F7
        ld      h,a
        set     1,l
        ld      a,(x86_exec_test_result)
        and     a
        jr      nz,.test8_nonzero
        set     6,l
.test8_nonzero:
        bit     7,a
        jr      z,.test8_sign_done
        set     7,l
.test8_sign_done:
        ld      a,(x86_exec_test_result)
        and     a
        jp      po,.test8_parity_done
        set     2,l
.test8_parity_done:
        ld      (x86_reg_flags),hl
        or      a
        ret

x86_exec_test_ax_imm:
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_test_immediate),hl
        ld      hl,(x86_reg_ax)
        ld      de,(x86_exec_test_immediate)
        ld      a,l
        and     e
        ld      (x86_exec_test_result),a
        ld      a,h
        and     d
        ld      (x86_exec_test_result+1),a

        ld      hl,(x86_reg_flags)
        ld      a,l
        and     #2A
        ld      l,a
        ld      a,h
        and     #F7
        ld      h,a
        set     1,l

        ld      a,(x86_exec_test_result)
        and     a
        jp      po,.test16_no_parity
        set     2,l
.test16_no_parity:
        ld      a,(x86_exec_test_result+1)
        bit     7,a
        jr      z,.test16_no_sign
        set     7,l
.test16_no_sign:
        ld      a,(x86_exec_test_result)
        ld      b,a
        ld      a,(x86_exec_test_result+1)
        or      b
        jr      nz,.test16_no_zero
        set     6,l
.test16_no_zero:
        ld      (x86_reg_flags),hl
        or      a
        ret

; 60-6F are the undocumented conditional-branch aliases used by PCem's
; 8086 execution path; 70-7F are the documented Jcc encodings.
; All forms consume a signed 8-bit displacement, whether taken or not.
x86_exec_jcc:
        ld      a,(x86_exec_opcode)
        and     #0F
        ld      (x86_exec_jcc_condition),a
        call    x86_cpu_fetch8
        ret     c
        ld      (x86_exec_jcc_displacement),a
        call    x86_exec_jcc_test
        or      a
        ret     z

        ld      a,(x86_exec_jcc_displacement)
        ld      e,a
        ld      d,0
        bit     7,e
        jr      z,.jcc_add
        dec     d
.jcc_add:
        ld      hl,(x86_reg_ip)
        add     hl,de
        ld      (x86_reg_ip),hl
        or      a
        ret

; A=condition nibble; returns A=1 when the condition is true, else A=0.
x86_exec_jcc_test:
        ld      hl,(x86_reg_flags)
        ld      a,(x86_exec_jcc_condition)
        cp      0
        jr      nz,.jcc_check1
        bit     3,h
        jp nz,.jcc_yes
        jp      .jcc_false
.jcc_check1:
        ld      a,(x86_exec_jcc_condition)
        cp      1
        jr      nz,.jcc_b
        bit     3,h
        jp z,.jcc_yes
        jp .jcc_false
.jcc_b:
        cp      2
        jr      nz,.jcc_ae
        bit     0,l
        jp nz,.jcc_yes
        jp .jcc_false
.jcc_ae:
        cp      3
        jr      nz,.jcc_e
        bit     0,l
        jp z,.jcc_yes
        jp .jcc_false
.jcc_e:
        cp      4
        jr      nz,.jcc_ne
        bit     6,l
        jp nz,.jcc_yes
        jp .jcc_false
.jcc_ne:
        cp      5
        jr      nz,.jcc_be
        bit     6,l
        jp z,.jcc_yes
        jp .jcc_false
.jcc_be:
        cp      6
        jr      nz,.jcc_a
        bit     0,l
        jp nz,.jcc_yes
        bit     6,l
        jp nz,.jcc_yes
        jp .jcc_false
.jcc_a:
        cp      7
        jr      nz,.jcc_s
        bit     0,l
        jp nz,.jcc_false
        bit     6,l
        jp z,.jcc_yes
        jp .jcc_false
.jcc_s:
        cp      8
        jr      nz,.jcc_ns
        bit     7,l
        jp nz,.jcc_yes
        jp .jcc_false
.jcc_ns:
        cp      9
        jr      nz,.jcc_p
        bit     7,l
        jp z,.jcc_yes
        jp .jcc_false
.jcc_p:
        cp      10
        jr      nz,.jcc_np
        bit     2,l
        jp nz,.jcc_yes
        jp .jcc_false
.jcc_np:
        cp      11
        jr      nz,.jcc_l
        bit     2,l
        jp z,.jcc_yes
        jp .jcc_false
.jcc_l:
        cp      12
        jr      nz,.jcc_ge
        bit     7,l
        jr      nz,.jcc_l_sf1
        bit     3,h
        jp nz,.jcc_yes
        jp .jcc_false
.jcc_l_sf1:
        bit     3,h
        jp z,.jcc_yes
        jp .jcc_false
.jcc_ge:
        cp      13
        jr      nz,.jcc_le
        bit     7,l
        jr      nz,.jcc_ge_sf1
        bit     3,h
        jp z,.jcc_yes
        jp .jcc_false
.jcc_ge_sf1:
        bit     3,h
        jp nz,.jcc_yes
        jp .jcc_false
.jcc_le:
        cp      14
        jr      nz,.jcc_g
        bit     6,l
        jp nz,.jcc_yes
        bit     7,l
        jr      nz,.jcc_le_sf1
        bit     3,h
        jp nz,.jcc_yes
        jp .jcc_false
.jcc_le_sf1:
        bit     3,h
        jp z,.jcc_yes
        jp .jcc_false
.jcc_g:
        ; JG = !ZF && (SF == OF).
        bit     6,l
        jp nz,.jcc_false
        bit     7,l
        jr      nz,.jcc_g_sf1
        bit     3,h
        jp z,.jcc_yes
        jp .jcc_false
.jcc_g_sf1:
        bit     3,h
        jp nz,.jcc_yes
.jcc_false:
        xor     a
        ret
.jcc_yes:
        ld      a,1
        ret

; 50-57 PUSH r16, 58-5F POP r16.
; Stack words use SS:SP and 16-bit offset wrap. PCem's 8086 path decrements
; SP before reading the PUSH source, and increments SP before resolving POP;
; this preserves the original 8086 PUSH SP / POP SP behavior.
x86_exec_push_pop_reg:
        ld      a,(x86_exec_opcode)
        and     #08
        ld      (x86_exec_stack_is_pop),a
        ld      a,(x86_exec_opcode)
        and     #07
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_exec_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (x86_exec_reg_ptr),de

        ld      hl,(x86_reg_sp)
        ld      a,(x86_exec_stack_is_pop)
        or      a
        jr      nz,.pop_word

        ; PUSH: decrement SP first, then read the source register. For PUSH SP
        ; this intentionally stores the decremented SP value (8086 behavior).
        dec     hl
        dec     hl
        ld      (x86_reg_sp),hl
        ld      (x86_exec_stack_offset),hl
        ld      de,(x86_exec_reg_ptr)
        ex      de,hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (x86_exec_stack_value),de

        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value+1)
        call    x86_guest_mem_write8
        ret
.pop_word:
        ; POP: address is old SP, then SP is advanced before destination
        ; commit. POP SP finally overwrites that incremented value.
        ld      (x86_exec_stack_offset),hl
        inc     hl
        inc     hl
        ld      (x86_reg_sp),hl

        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value),a
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_stack_value+1),a

        ld      hl,(x86_exec_reg_ptr)
        ld      a,(x86_exec_stack_value)
        ld      (hl),a
        inc     hl
        ld      a,(x86_exec_stack_value+1)
        ld      (hl),a
        or      a
        ret

; Build the current SS:stack_offset address through the Project126 mapper.
x86_exec_stack_make_address:
        ld      hl,(x86_reg_ss)
        ld      de,(x86_exec_stack_offset)
        jp      x86_cpu_calc_phys

; A0-A3: MOV AL/AX <-> DS:[moffs16].
; Segment override prefixes are handled by the prefix layer, not yet present.
x86_exec_moffs:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_moffs_opcode),a
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_moffs_offset),hl

        ld      a,(x86_exec_moffs_opcode)
        bit     1,a
        jr      nz,.store_to_memory
        ; A0/A1: load AL/AX from memory.
        bit     0,a
        jr      nz,.load_word

        call    x86_exec_moffs_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_reg_ax),a
        or      a
        ret

.load_word:
        call    x86_exec_moffs_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_moffs_value),a
        ld      hl,(x86_exec_moffs_offset)
        inc     hl
        ld      (x86_exec_moffs_offset),hl
        call    x86_exec_moffs_make_address
        call    x86_guest_mem_read8
        ret     c
        ld      (x86_exec_moffs_value+1),a
        ld      hl,(x86_exec_moffs_value)
        ld      (x86_reg_ax),hl
        or      a
        ret

.store_to_memory:
        ; A2/A3: store AL/AX to memory.
        bit     0,a
        jr      nz,.store_word

        ld      a,(x86_reg_ax)
        ld      (x86_exec_moffs_value),a
        call    x86_exec_moffs_make_address
        ld      a,(x86_exec_moffs_value)
        call    x86_guest_mem_write8
        ret

.store_word:
        ld      hl,(x86_reg_ax)
        ld      (x86_exec_moffs_value),hl
        call    x86_exec_moffs_make_address
        ld      a,(x86_exec_moffs_value)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_exec_moffs_offset)
        inc     hl
        ld      (x86_exec_moffs_offset),hl
        call    x86_exec_moffs_make_address
        ld      a,(x86_exec_moffs_value+1)
        call    x86_guest_mem_write8
        ret

; Convert DS:offset into the Project126 physical-address scratch triple.
x86_exec_moffs_make_address:
        ld      hl,(x86_reg_ds)
        ld      de,(x86_exec_moffs_offset)
        jp      x86_cpu_calc_phys

; 91-97: exchange AX with the selected 16-bit general register.
; XCHG does not modify FLAGS. Opcode 90 is dispatched separately as NOP.
x86_exec_xchg_ax_reg:
        ld      a,(x86_exec_opcode)
        sub     #90
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_exec_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (x86_exec_reg_ptr),de

        ld      hl,(x86_reg_ax)
        ld      (x86_exec_result_word),hl
        ld      hl,(x86_exec_reg_ptr)
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ld      (x86_reg_ax),bc

        ld      hl,(x86_exec_reg_ptr)
        ld      de,(x86_exec_result_word)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        or      a
        ret

; 40-47 INC r16, 48-4F DEC r16. Uses the common 16-bit ALU flag
; calculation, then restores CF because INC/DEC leave CF unchanged.
x86_exec_incdec_reg:
        ld      a,(x86_exec_opcode)
        and     #08
        ld      (x86_exec_is_dec),a
        ld      a,(x86_exec_opcode)
        and     #07
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_exec_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (x86_exec_reg_ptr),de

        ; Save CF before loading the arithmetic operand.
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     1
        ld      (x86_exec_saved_cf),a

        ; Read the selected guest word register into HL.
        ex      de,hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl

        ; Run the 16-bit add/subtract-by-one flag calculation.
        ld      de,1
        ld      a,(x86_exec_is_dec)
        or      a
        jr      nz,.do_dec
        call    x86_alu_add16
        jr      .alu_done
.do_dec:
        call    x86_alu_sub16
.alu_done:
        ld      (x86_exec_result_word),hl

        ; Restore the original carry flag.
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     #FE
        ld      l,a
        ld      a,(x86_exec_saved_cf)
        or      l
        ld      l,a
        ld      (x86_reg_flags),hl

        ; Commit the arithmetic result to the selected register.
        ld      de,(x86_exec_reg_ptr)
        ex      de,hl
        ld      de,(x86_exec_result_word)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        or      a
        ret

; B0-B7: MOV r8,imm8. Byte-register encoding is AL,CL,DL,BL,AH,CH,DH,BH.
; B8-BF: MOV r16,imm16. Register encoding is AX,CX,DX,BX,SP,BP,SI,DI.
; The table maps the byte-register high half back to AX/CX/DX/BX.
x86_exec_mov_imm_reg:
        ld      a,(x86_exec_opcode)
        cp      #B8
        jr      nc,.word_register

        sub     #B0
        ld      b,a
        call    x86_cpu_fetch8
        ret     c
        ld      c,a

        ld      a,b
        and     #03
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_exec_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)

        ld      a,b
        cp      4
        jr      c,.byte_store
        inc     de
.byte_store:
        ld      a,c
        ld      (de),a
        or      a
        ret

.word_register:
        sub     #B8
        ld      b,a
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_imm_word),hl

        ld      a,b
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_exec_reg16_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)

        ld      hl,(x86_exec_imm_word)
        ex      de,hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        or      a
        ret

; EA ptr16:16 — JMP FAR immediate. Offset precedes segment in the stream.
; PCem's 808x far-jump path loads CS:IP from this immediate pointer.
x86_exec_jmp_far_imm:
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_target_ip),hl
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_reg_cs),hl
        ld      hl,(x86_exec_target_ip)
        ld      (x86_reg_ip),hl
        or      a
        ret

; E0 LOOPNE, E1 LOOPE, E2 LOOP, E3 JCXZ.
; CX decrement does not modify FLAGS. All forms consume signed rel8.
x86_exec_loop_family:
        ld      a,(x86_exec_opcode)
        ld      (x86_exec_loop_opcode),a
        call    x86_cpu_fetch8
        ret     c
        ld      (x86_exec_jcc_displacement),a

        ld      a,(x86_exec_loop_opcode)
        cp      #E3
        jr      z,.loop_test_cx
        ld      hl,(x86_reg_cx)
        dec     hl
        ld      (x86_reg_cx),hl
        ld      a,h
        or      l
        jr      z,.loop_not_taken

        ld      a,(x86_exec_loop_opcode)
        cp      #E0
        jr      z,.loop_test_zf_clear
        cp      #E1
        jr      z,.loop_test_zf_set
        ; E2 LOOP only requires CX != 0.
        jr      .loop_taken

.loop_test_cx:
        ld      hl,(x86_reg_cx)
        ld      a,h
        or      l
        jr      nz,.loop_not_taken
        jr      .loop_taken

.loop_test_zf_clear:
        ld      hl,(x86_reg_flags)
        bit     6,l
        jr      nz,.loop_not_taken
        jr      .loop_taken

.loop_test_zf_set:
        ld      hl,(x86_reg_flags)
        bit     6,l
        jr      z,.loop_not_taken

.loop_taken:
        ld      a,(x86_exec_jcc_displacement)
        ld      e,a
        ld      d,0
        bit     7,e
        jr      z,.loop_add
        dec     d
.loop_add:
        ld      hl,(x86_reg_ip)
        add     hl,de
        ld      (x86_reg_ip),hl
.loop_not_taken:
        or      a
        ret

; E8 CALL rel16. Push the post-displacement IP to SS:SP-2,
; then branch relative to the post-displacement IP.
x86_exec_call_near_rel16:
        call    x86_cpu_fetch16
        ret     c
        ld      (x86_exec_call_displacement),hl
        ld      hl,(x86_reg_sp)
        dec     hl
        dec     hl
        ld      (x86_reg_sp),hl
        ld      (x86_exec_stack_offset),hl
        ld      hl,(x86_reg_ip)
        ld      (x86_exec_stack_value),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_exec_stack_offset)
        inc     hl
        ld      (x86_exec_stack_offset),hl
        call    x86_exec_stack_make_address
        ld      a,(x86_exec_stack_value+1)
        call    x86_guest_mem_write8
        ret     c
        ld      hl,(x86_reg_ip)
        ld      de,(x86_exec_call_displacement)
        add     hl,de
        ld      (x86_reg_ip),hl
        or      a
        ret

; E9 cw — JMP near relative, signed displacement added to post-fetch IP.
x86_exec_jmp_near_rel16:
        call    x86_cpu_fetch16
        ret     c
        ld      de,(x86_reg_ip)
        add     hl,de
        ld      (x86_reg_ip),hl
        or      a
        ret

; EB cb — JMP short relative, sign-extended 8-bit displacement.
x86_exec_jmp_short_rel8:
        call    x86_cpu_fetch8
        ret     c
        ld      e,a
        ld      d,0
        bit     7,e
        jr      z,.short_add
        dec     d
.short_add:
        ld      hl,(x86_reg_ip)
        add     hl,de
        ld      (x86_reg_ip),hl
        or      a
        ret

x86_exec_nop:
        or      a
        ret

x86_exec_hlt:
        ld      a,1
        ld      (x86_halted),a
        or      a
        ret

x86_exec_fetch_byte: db 0
x86_exec_imm_low: db 0
x86_exec_opcode: db 0
x86_exec_target_ip: dw 0
x86_exec_imm_word: dw 0
x86_exec_reg_ptr: dw 0
x86_exec_result_word: dw 0
x86_exec_saved_cf: db 0
x86_exec_is_dec: db 0
x86_exec_stack_is_pop: db 0
x86_exec_stack_offset: dw 0
x86_exec_stack_value: dw 0
x86_exec_stack_new_sp: dw 0
x86_exec_target_cs: dw 0
x86_exec_ret_adjust: dw 0
x86_exec_call_displacement: dw 0
x86_exec_loop_opcode: db 0
x86_exec_test_result: db 0,0
x86_exec_test_immediate: dw 0
x86_exec_mov_opcode: db 0
x86_exec_alu_opcode: db 0
x86_exec_alu_lhs8: db 0
x86_exec_alu_lhs16: dw 0
x86_exec_alu_result8: db 0
x86_exec_alu_result16: dw 0
x86_exec_alu_is_cmp: db 0
x86_exec_alu_operation: db 0
x86_exec_alu_is_sbb: db 0
x86_exec_segment_pop_opcode: db 0
x86_exec_group3_opcode: db 0
x86_exec_group3_ext: db 0
x86_exec_group3_imm8: db 0
x86_exec_group3_imm16: dw 0
x86_exec_group3_value8: db 0
x86_exec_group45_opcode: db 0
x86_exec_group45_ext: db 0
x86_exec_group45_value8: db 0
x86_exec_group45_value16: dw 0
x86_exec_group1_opcode: db 0
x86_exec_group1_ext: db 0
x86_exec_group1_is_cmp: db 0
x86_exec_group1_imm8: db 0
x86_exec_group1_imm16: dw 0
x86_exec_group1_lhs8: db 0
x86_exec_group1_rhs8: db 0
x86_exec_group1_lhs16: dw 0
x86_exec_group1_rhs16: dw 0
x86_exec_adc_sbb_lhs8: db 0
x86_exec_adc_sbb_lhs16: dw 0
x86_exec_mov_byte: db 0
x86_exec_sreg_opcode: db 0
x86_exec_sreg_index: db 0
x86_exec_sreg_ptr: dw 0
x86_exec_sreg_value: dw 0
x86_exec_les_lds_opcode: db 0
x86_exec_les_lds_offset: dw 0
x86_exec_les_lds_segment: dw 0
x86_exec_sreg_table:
        dw x86_reg_es,x86_reg_cs,x86_reg_ss,x86_reg_ds
x86_exec_xchg_opcode: db 0
x86_exec_xchg_rm_byte: db 0
x86_exec_xchg_reg_byte: db 0
x86_exec_xchg_rm_word: dw 0
x86_exec_xchg_reg_word: dw 0
x86_exec_jcc_condition: db 0
x86_exec_jcc_displacement: db 0
x86_exec_moffs_opcode: db 0
x86_exec_moffs_offset: dw 0
x86_exec_moffs_value: dw 0
x86_exec_reg16_table:
        dw x86_reg_ax,x86_reg_cx,x86_reg_dx,x86_reg_bx
        dw x86_reg_sp,x86_reg_bp,x86_reg_si,x86_reg_di
