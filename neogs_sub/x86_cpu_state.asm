; PROJECT126 / X86_CPU_STATE v0.2.0
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


; Classify the 20-bit physical address already stored in x86_phys_addr.
; IN:  x86_phys_addr = low byte, middle byte, high nibble.
; OUT: A = P126_X86_MEM_* region ID.
; The 8086 address helper masks to 20 bits, so all inputs are in range.
x86_mem_classify:
        ld      a,(x86_phys_addr+2)
        cp      #0A
        jr      c,.ram_low
        cp      #0C
        jr      c,.vga_aperture
        cp      #0D
        jr      z,.segment_c
        cp      #0F
        jr      c,.ram_high
        jr      z,.segment_f
        ; Defensive fallback; unreachable for a valid 20-bit address.
        ld      a,P126_X86_MEM_RAM_LOW
        ret
.segment_c:
        ld      a,(x86_phys_addr+1)
        cp      #80
        jr      c,.vga_bios
        jr      .ram_high
.segment_f:
        ld      a,(x86_phys_addr+1)
        cp      #E0
        jr      c,.ram_high
        ld      a,P126_X86_MEM_SYSBIOS
        ret
.ram_low:
        ld      a,P126_X86_MEM_RAM_LOW
        ret
.vga_aperture:
        ld      a,P126_X86_MEM_VGA_APERTURE
        ret
.vga_bios:
        ld      a,P126_X86_MEM_VGABIOS
        ret
.ram_high:
        ld      a,P126_X86_MEM_RAM_HIGH
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
        jp      nz,.fail
        ld      hl,(x86_reg_ip)
        ld      de,0
        or      a
        sbc     hl,de
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        ld      de,X86_FLAGS_RESET
        or      a
        sbc     hl,de
        jp      nz,.fail

        ; 0000:0000 = 00000h
        ld      hl,0
        ld      de,0
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_zero
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; FFFF:000F = FFFFFh
        ld      hl,#FFFF
        ld      de,#000F
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_fffff
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; FFFF:0010 wraps to 00000h on the 20-bit bus.
        ld      hl,#FFFF
        ld      de,#0010
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_zero
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; 1234:5678 = 179B8h
        ld      hl,#1234
        ld      de,#5678
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_179b8
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; F000:FFF0 = FFFF0h, the reset-vector physical address.
        ld      hl,#F000
        ld      de,#FFF0
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_ffff0
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; Guest memory decode boundary tests.
        ld      hl,x86_test_9ffff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_LOW
        jp      nz,.fail

        ld      hl,x86_test_a0000
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_VGA_APERTURE
        jp      nz,.fail

        ld      hl,x86_test_bffff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_VGA_APERTURE
        jp      nz,.fail

        ld      hl,x86_test_c0000
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_VGABIOS
        jp      nz,.fail

        ld      hl,x86_test_c7fff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_VGABIOS
        jp      nz,.fail

        ld      hl,x86_test_c8000
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_HIGH
        jp      nz,.fail

        ld      hl,x86_test_fdfff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_HIGH
        jp      nz,.fail

        ld      hl,x86_test_fe000
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_SYSBIOS
        jp      nz,.fail

        ld      hl,x86_test_fffff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_SYSBIOS
        jp      nz,.fail

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

; Physical address boundary vectors: low, middle, high-nibble bytes.
x86_test_9ffff:  db #FF,#FF,#09
x86_test_a0000:  db #00,#00,#0A
x86_test_bffff:  db #FF,#FF,#0B
x86_test_c0000:  db #00,#00,#0C
x86_test_c7fff:  db #FF,#7F,#0C
x86_test_c8000:  db #00,#80,#0C
x86_test_fdfff:  db #FF,#DF,#0F
x86_test_fe000:  db #00,#E0,#0F
x86_test_fffff:  db #FF,#FF,#0F
