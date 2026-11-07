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
        scf
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
