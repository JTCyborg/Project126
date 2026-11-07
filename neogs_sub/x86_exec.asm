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

        cp      #98
        jp      z,x86_exec_cbw
        cp      #99
        jp      z,x86_exec_cwd
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
x86_exec_jcc_condition: db 0
x86_exec_jcc_displacement: db 0
x86_exec_moffs_opcode: db 0
x86_exec_moffs_offset: dw 0
x86_exec_moffs_value: dw 0
x86_exec_reg16_table:
        dw x86_reg_ax,x86_reg_cx,x86_reg_dx,x86_reg_bx
        dw x86_reg_sp,x86_reg_bp,x86_reg_si,x86_reg_di
