; PROJECT126 / X86_CPU_STATE v0.1.0
; PCem references: PCem/808x.c resetx86(), PCem/cpu.h CPU_8086.
; Intel 8086 Real Mode architectural state and 20-bit physical address helper.
; This module does not decide the still-open guest memory-region map.
;
; API:
;   x86_cpu_reset       Reset vector FFFF:0000, FLAGS=0002h.
;   x86_cpu_calc_phys   IN HL=segment, DE=offset.
;                       OUT x86_phys_addr[0..2], little endian; A=high nibble.
;                       Physical address wraps at 1 MiB (8086 bus, no A20).
;   x86_cpu_emit_version Emits the executing component version to NeoGS #EF.
;   x86_cpu_state_selftest Carry clear=pass, set=fail. Destructive reset test.

X86_FLAGS_RESET EQU #0002

x86_cpu_reset:
        ld      hl,0
        ld      (x86_reg_ax),hl
        ld      (x86_reg_cx),hl
        ld      (x86_reg_dx),hl
        ld      (x86_reg_bx),hl
        ld      (x86_reg_sp),hl
        ld      (x86_reg_bp),hl
        ld      (x86_reg_si),hl
        ld      (x86_reg_di),hl
        ld      (x86_reg_es),hl
        ld      (x86_reg_ss),hl
        ld      (x86_reg_ds),hl
        ld      (x86_reg_ip),hl
        ld      hl,#FFFF
        ld      (x86_reg_cs),hl
        ld      hl,X86_FLAGS_RESET
        ld      (x86_reg_flags),hl
        xor     a
        ld      (x86_halted),a
        ld      (x86_pending_irq),a
        ld      (x86_pending_nmi),a
        ret

; physical = ((segment << 4) + offset) & 0FFFFFh
x86_cpu_calc_phys:
        push    bc
        ; low byte of segment<<4
        ld      a,l
        and     #0F
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      (x86_phys_addr),a
        ; middle byte = (segment.high<<4) | (segment.low>>4)
        ld      a,l
        rrca
        rrca
        rrca
        rrca
        and     #0F
        ld      b,a
        ld      a,h
        and     #0F
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      b
        ld      (x86_phys_addr+1),a
        ; high nibble
        ld      a,h
        rrca
        rrca
        rrca
        rrca
        and     #0F
        ld      (x86_phys_addr+2),a
        ; add 16-bit offset
        ld      a,(x86_phys_addr)
        add     a,e
        ld      (x86_phys_addr),a
        ld      a,(x86_phys_addr+1)
        adc     a,d
        ld      (x86_phys_addr+1),a
        ld      a,(x86_phys_addr+2)
        adc     a,0
        and     #0F
        ld      (x86_phys_addr+2),a
        pop     bc
        ld      a,(x86_phys_addr+2)
        or      a                       ; return carry clear
        ret

; Emit a runtime identity, not merely an assembler-time banner.
x86_cpu_emit_version:
        push    af
        push    hl
        ld      hl,x86_cpu_version_text
.loop:
        ld      a,(hl)
        or      a
        jr      z,.done
        out     (#EF),a
        inc     hl
        jr      .loop
.done:
        pop     hl
        pop     af
        ret

x86_cpu_version_text:
        defb    "[P126 X86_CPU_STATE v0.1.0]",13,10,0

; Executable target-side test vectors. Does not require BIOS, VGA or a
; selected memory-region map. It must be run before marking BUILD/HARDWARE PASS.
x86_cpu_state_selftest:
        push    af
        push    bc
        push    de
        push    hl
        call    x86_cpu_reset

        ld      hl,(x86_reg_cs)
        ld      de,#FFFF
        or      a
        sbc     hl,de
        jr      nz,.fail
        ld      hl,(x86_reg_ip)
        ld      de,0
        or      a
        sbc     hl,de
        jr      nz,.fail
        ld      hl,(x86_reg_flags)
        ld      de,X86_FLAGS_RESET
        or      a
        sbc     hl,de
        jr      nz,.fail

        ; 0000:0000 = 00000h
        ld      hl,0
        ld      de,0
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_zero
        call    x86_cpu_check_phys
        jr      nz,.fail

        ; FFFF:000F = FFFFFh
        ld      hl,#FFFF
        ld      de,#000F
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_fffff
        call    x86_cpu_check_phys
        jr      nz,.fail

        ; FFFF:0010 wraps to 00000h on the 20-bit bus.
        ld      hl,#FFFF
        ld      de,#0010
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_zero
        call    x86_cpu_check_phys
        jr      nz,.fail

        ; 1234:5678 = 179B8h
        ld      hl,#1234
        ld      de,#5678
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_179b8
        call    x86_cpu_check_phys
        jr      nz,.fail

        ; F000:FFF0 = FFFF0h, the reset-vector physical address.
        ld      hl,#F000
        ld      de,#FFF0
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_ffff0
        call    x86_cpu_check_phys
        jr      nz,.fail

        pop     hl
        pop     de
        pop     bc
        pop     af
        or      a
        ret
.fail:
        pop     hl
        pop     de
        pop     bc
        pop     af
        scf
        ret

; IN HL=expected address bytes. Z set iff all three bytes match.
x86_cpu_check_phys:
        push    bc
        push    de
        ex      de,hl
        ld      hl,x86_phys_addr
        ld      b,3
.check:
        ld      a,(de)
        cp      (hl)
        jr      nz,.done
        inc     de
        inc     hl
        djnz    .check
.done:
        pop     de
        pop     bc
        ret

; Stable register names for subsequent instruction-decoder modules.
x86_reg_ax:    dw 0
x86_reg_cx:    dw 0
x86_reg_dx:    dw 0
x86_reg_bx:    dw 0
x86_reg_sp:    dw 0
x86_reg_bp:    dw 0
x86_reg_si:    dw 0
x86_reg_di:    dw 0
x86_reg_es:    dw 0
x86_reg_cs:    dw 0
x86_reg_ss:    dw 0
x86_reg_ds:    dw 0
x86_reg_ip:    dw 0
x86_reg_flags: dw X86_FLAGS_RESET
x86_halted:      db 0
x86_pending_irq: db 0
x86_pending_nmi: db 0
x86_phys_addr: db 0,0,0

x86_expected_zero:  db 0,0,0
x86_expected_fffff: db #FF,#FF,#0F
x86_expected_179b8: db #B8,#79,#01
x86_expected_ffff0: db #F0,#FF,#0F
