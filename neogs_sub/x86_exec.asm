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

        cp      #EA
        jp      z,x86_exec_jmp_far_imm
        cp      #E9
        jp      z,x86_exec_jmp_near_rel16
        cp      #EB
        jp      z,x86_exec_jmp_short_rel8
        cp      #90
        jp      z,x86_exec_nop
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

        ; Read the selected guest word register.
        ex      de,hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl

        ; Save CF, run the 16-bit add/subtract-by-one flag calculation.
        ld      de,1
        ld      hl,(x86_reg_flags)
        ld      a,l
        and     1
        ld      (x86_exec_saved_cf),a
        ld      a,(x86_exec_is_dec)
        or      a
        call    nz,x86_alu_sub16
        call    z,x86_alu_add16

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
        ld      (x86_exec_result_word),hl
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
x86_exec_reg16_table:
        dw x86_reg_ax,x86_reg_cx,x86_reg_dx,x86_reg_bx
        dw x86_reg_sp,x86_reg_bp,x86_reg_si,x86_reg_di
