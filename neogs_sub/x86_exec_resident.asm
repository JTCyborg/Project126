; PROJECT126 / X86_EXEC_RESIDENT v0.2.0
; Permanently mapped fetch API, dispatcher call gate and shared trace state.

; PROJECT126 / X86_EXEC v0.1.0
; Intel 8086 Real Mode instruction execution core.
; Semantics cross-checked against PCem/808x.c (FETCH, EA opcode and JMP paths).
; The primary opcode map is dispatched; PCem 8086 forms and edge cases
; remain under source-level semantic review. Unreviewed forms fail closed.
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
        ld      a,P126_NGS_X86EXEC_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        ld      ix,#8000
        call    p126_overlay_call
        ret

x86_exec_get_data_segment:
        ld      a,(x86_exec_prefix_seg)
        or      a
        jr      nz,.segment_override
        ld      hl,(x86_reg_ds)
        ret
.segment_override:
        dec     a
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_exec_segment_table
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret

; PCem's 8086 switch has no 0F case: the fetched byte is ignored.

x86_exec_instruction_start_cs: dw 0
x86_exec_instruction_start_ip: dw 0
x86_exec_prefix_seg: db 0
x86_exec_prefix_rep: db 0
x86_exec_prefix_lock: db 0
x86_exec_segment_table:
        dw x86_reg_es,x86_reg_cs,x86_reg_ss,x86_reg_ds
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
x86_exec_interrupt_vector: db 0
x86_exec_ivt_offset: dw 0
x86_exec_ivt_value: dw 0
x86_exec_io_opcode: db 0
x86_exec_segment_pop_opcode: db 0
x86_exec_string_opcode: db 0
x86_exec_string_width: db 0
x86_exec_string_rep: db 0
x86_exec_string_remaining: db 0
x86_exec_string_value: db 0
x86_exec_string_word: dw 0
x86_exec_string_temp_offset: dw 0
x86_exec_adjust_base: db 0
x86_exec_szp8_value: db 0
x86_exec_shift_opcode: db 0
x86_exec_shift_operation: db 0
x86_exec_shift_count: db 0
x86_exec_shift_value8: db 0
x86_exec_shift_original8: db 0
x86_exec_shift_value16: dw 0
x86_exec_shift_original16: dw 0
x86_exec_shift_cf: db 0
x86_exec_shift_of: db 0
x86_exec_group3_opcode: db 0
x86_exec_group3_operand16: dw 0
x86_exec_group3_original_ax: dw 0
x86_exec_mul16_multiplier: dw 0
x86_exec_mul16_multiplicand_low: dw 0
x86_exec_mul16_multiplicand_high: dw 0
x86_exec_mul16_product_low: dw 0
x86_exec_mul16_product_high: dw 0
x86_exec_dividend32_low: dw 0
x86_exec_dividend32_high: dw 0
x86_exec_remainder32_low: dw 0
x86_exec_remainder32_high: dw 0
x86_exec_group3_operand8: db 0
x86_exec_group3_original_al: db 0
x86_exec_group3_abs_al: db 0
x86_exec_group3_sign_dividend: db 0
x86_exec_group3_sign_quotient: db 0
x86_exec_mul8_lhs: db 0
x86_exec_mul8_multiplier: db 0
x86_exec_mul8_multiplicand: dw 0
x86_exec_mul8_product: dw 0
x86_exec_dividend16: dw 0
x86_exec_divisor8: db 0
x86_exec_divisor16: dw 0
x86_exec_remainder16: dw 0
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
