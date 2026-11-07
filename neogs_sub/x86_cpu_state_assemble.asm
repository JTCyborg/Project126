; PROJECT126 / X86 ASSEMBLY UNIT v0.8.0
; Address-space audit unit, assembled at logical image origin 0000h.
; The listing and symbol map are mandatory build products.
; These offsets describe the assembled module image, not yet the final
; physical NeoGS load address (runtime placement remains a separate stage).

        ORG     0

; Physical NeoGS and guest x86 memory allocation contracts.
        INCLUDE "shared/p126_x86_machine_map.inc"
        INCLUDE "shared/p126_neogs_memory_map.inc"

        DISPLAY "P126_X86_RAM_BYTES=", /H, P126_X86_RAM_BACKING_SIZE
        DISPLAY "P126_X86_VGA_APERTURE=", /H, P126_X86_VGA_APERTURE_BASE
        DISPLAY "P126_X86_VGABIOS=", /H, P126_X86_VGABIOS_BASE
        DISPLAY "P126_X86_RAM_HIGH=", /H, P126_X86_RAM_HIGH_BASE
        DISPLAY "P126_X86_SYSBIOS=", /H, P126_X86_SYSBIOS_BASE
        DISPLAY "P126_NGS_BANK_WINDOW_BASE=", /H, P126_NGS_BANK_WINDOW_BASE
        DISPLAY "P126_NGS_BANK_WINDOW_PORT=", /H, P126_NGS_BANK_WINDOW_PORT
        DISPLAY "P126_NGS_GUEST_RAM_PAGE_BASE=", /H, P126_NGS_GUEST_RAM_PAGE_BASE
        DISPLAY "P126_NGS_RAM_BYTES=", /H, P126_NGS_RAM_SIZE
        DISPLAY "P126_NGS_KERNEL_BASE=", /H, P126_NGS_KERNEL_BASE
        DISPLAY "P126_NGS_SYSBIOS_BASE=", /H, P126_NGS_SYSBIOS_BASE
        DISPLAY "P126_NGS_VGABIOS_BASE=", /H, P126_NGS_VGABIOS_BASE
        DISPLAY "P126_NGS_VRAM_BASE=", /H, P126_NGS_VRAM_BASE
        DISPLAY "P126_NGS_FRAME_BASE=", /H, P126_NGS_FRAME_BASE
        DISPLAY "P126_NGS_DMA_BASE=", /H, P126_NGS_DMA_BASE
        DISPLAY "P126_NGS_IPC_BASE=", /H, P126_NGS_IPC_BASE
        DISPLAY "P126_NGS_GUEST_RAM_BASE=", /H, P126_NGS_GUEST_RAM_BASE
        DISPLAY "P126_NGS_RESERVED_BASE=", /H, P126_NGS_RESERVED_BASE

; =========================================================================
; Project126 resident Z80 entry. Stage-0 copies this image to physical page
; 00. WIN1/page 03 owns the resident stack; WIN3 is the banked aperture.
; =========================================================================
p126_ngs_resident_entry_vector:
        jp      p126_ngs_resident_start
        BLOCK   5,0

p126_ngs_resident_start:
        di
        in      a,(#0F)
        and     #CF
        or      #29                    ; 20 MHz + NOROM + EXPAG
        out     (#0F),a
        xor     a
        ld      bc,#0020
        out     (c),a                  ; WIN0 -> physical page 00
        ld      a,3
        ld      bc,#0021
        out     (c),a                  ; WIN1 -> physical page 03
        ld      a,#80
        out     (#00),a                ; WIN2 -> physical page 01
        ld      a,#01
        out     (#10),a                ; WIN3 -> physical page 02 until banked
        ld      sp,#7FFE

        ld      hl,p126_ngs_resident_banner
        call    p126_ngs_resident_log
        call    p126_ngs_ipc_crc16_selftest
        jr      c,p126_ngs_resident_crc_fail
        ld      hl,p126_ngs_resident_crc_ok
        call    p126_ngs_resident_log
        ld      a,#A2
        call    p126_ngs_resident_send_boot_ack
        jr      c,p126_ngs_resident_ack_fail

p126_ngs_resident_main_loop:
        call    p126_ngs_ipc_dispatch_once
        jr      c,p126_ngs_resident_frame_error
        or      a
        jr      z,.check_bios_ready
        ld      hl,p126_ngs_resident_frame_ok
        call    p126_ngs_resident_log
.check_bios_ready:
        ld      a,(p126_ngs_bios_image_ready)
        or      a
        jr      z,p126_ngs_resident_main_loop
        ; Consume the installation event before probing: one-shot transition.
        xor     a
        ld      (p126_ngs_bios_image_ready),a
        call    x86_bios_reset_vector_probe
        jr      p126_ngs_resident_main_loop

p126_ngs_resident_frame_error:
        push    af
        ld      hl,p126_ngs_resident_frame_bad
        call    p126_ngs_resident_log
        pop     af
        jr      p126_ngs_resident_main_loop
p126_ngs_resident_crc_fail:
        ld      hl,p126_ngs_resident_crc_bad
        call    p126_ngs_resident_log
        jr      p126_ngs_resident_halt
p126_ngs_resident_ack_fail:
        ld      hl,p126_ngs_resident_ack_bad
        call    p126_ngs_resident_log
p126_ngs_resident_halt:
        di
        halt
        jr      p126_ngs_resident_halt

p126_ngs_resident_log:
        push    af
        push    bc
        ld      bc,#00EF
.p126_ngs_resident_log_loop:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,.p126_ngs_resident_log_done
        out     (c),a
        jr      .p126_ngs_resident_log_loop
.p126_ngs_resident_log_done:
        pop     bc
        pop     af
        ret

p126_ngs_resident_send_boot_ack:
        ld      (p126_ngs_resident_tx),a
        ld      bc,#FFFF
.p126_ngs_resident_ack_wait_free:
        in      a,(#04)
        bit     7,a
        jr      z,.p126_ngs_resident_ack_free
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_ngs_resident_ack_wait_free
        scf
        ret
.p126_ngs_resident_ack_free:
        ld      a,(p126_ngs_resident_tx)
        out     (#03),a
        ld      bc,#FFFF
.p126_ngs_resident_ack_wait_read:
        in      a,(#04)
        bit     7,a
        jr      z,.p126_ngs_resident_ack_ok
        dec     bc
        ld      a,b
        or      c
        jr      nz,.p126_ngs_resident_ack_wait_read
        scf
        ret
.p126_ngs_resident_ack_ok:
        or      a
        ret

p126_ngs_resident_banner: db "[NGS] P126 RESIDENT v0.1.0",13,10,0
p126_ngs_resident_crc_ok: db "[NGS] ABI CRC16 PASS",13,10,0
p126_ngs_resident_crc_bad: db "[NGS] ABI CRC16 FAIL",13,10,0
p126_ngs_resident_ack_bad: db "[NGS] HOST READY ACK TIMEOUT",13,10,0
p126_ngs_resident_frame_ok: db "[NGS] DMA FRAME VALID",13,10,0
p126_ngs_resident_frame_bad: db "[NGS] DMA FRAME REJECTED",13,10,0
p126_ngs_resident_tx: db 0

x86_cpu_state_module_start:
        INCLUDE "neogs_sub/x86_cpu_state.asm"
x86_cpu_state_module_end:

x86_cpu_exec_module_start:
        INCLUDE "neogs_sub/x86_exec.asm"
x86_cpu_exec_module_end:

x86_modrm_module_start:
        INCLUDE "neogs_sub/x86_modrm.asm"
x86_modrm_module_end:

x86_alu_module_start:
        INCLUDE "neogs_sub/x86_alu.asm"
x86_alu_module_end:

x86_io_module_start:
        INCLUDE "neogs_sub/x86_io.asm"
x86_io_module_end:

; Link the ABI 1.0 DMA receiver/dispatcher into the core image.
; The final resident loader and main-loop placement remain separate work.
p126_ngs_ipc_module_start:
        INCLUDE "neogs_sub/p126_ipc.asm"
p126_ngs_ipc_module_end:

; Export explicit boundaries for build/map inspection.
    DISPLAY "P126_NGS_RESIDENT_START=", /H, p126_ngs_resident_entry_vector
    DISPLAY "P126_NGS_RESIDENT_END=", /H, x86_cpu_state_module_start
    DISPLAY "P126_NGS_RESIDENT_SIZE=", /D, x86_cpu_state_module_start-p126_ngs_resident_entry_vector
    DISPLAY "P126_X86_STATE_START=", /H, x86_cpu_state_module_start
    DISPLAY "P126_X86_STATE_END=", /H, x86_cpu_state_module_end
    DISPLAY "P126_X86_STATE_SIZE=", /D, x86_cpu_state_module_end-x86_cpu_state_module_start
    DISPLAY "P126_X86_EXEC_START=", /H, x86_cpu_exec_module_start
    DISPLAY "P126_X86_EXEC_END=", /H, x86_cpu_exec_module_end
    DISPLAY "P126_X86_EXEC_SIZE=", /D, x86_cpu_exec_module_end-x86_cpu_exec_module_start
    DISPLAY "P126_X86_MODRM_START=", /H, x86_modrm_module_start
    DISPLAY "P126_X86_MODRM_END=", /H, x86_modrm_module_end
    DISPLAY "P126_X86_MODRM_SIZE=", /D, x86_modrm_module_end-x86_modrm_module_start
    DISPLAY "P126_X86_ALU_START=", /H, x86_alu_module_start
    DISPLAY "P126_X86_ALU_END=", /H, x86_alu_module_end
    DISPLAY "P126_X86_ALU_SIZE=", /D, x86_alu_module_end-x86_alu_module_start
    DISPLAY "P126_X86_IO_START=", /H, x86_io_module_start
    DISPLAY "P126_X86_IO_END=", /H, x86_io_module_end
    DISPLAY "P126_X86_IO_SIZE=", /D, x86_io_module_end-x86_io_module_start
    DISPLAY "P126_NGS_IPC_START=", /H, p126_ngs_ipc_module_start
    DISPLAY "P126_NGS_IPC_END=", /H, p126_ngs_ipc_module_end
    DISPLAY "P126_NGS_IPC_SIZE=", /D, p126_ngs_ipc_module_end-p126_ngs_ipc_module_start
    DISPLAY "P126_X86_IMAGE_END=", /H, p126_ngs_ipc_module_end
    DISPLAY "P126_X86_IMAGE_SIZE=", /D, p126_ngs_ipc_module_end

    ASSERT p126_ngs_resident_entry_vector = 0
    ASSERT x86_cpu_state_module_start > p126_ngs_resident_entry_vector
    ASSERT x86_cpu_state_module_end > x86_cpu_state_module_start
    ASSERT x86_cpu_exec_module_end > x86_cpu_exec_module_start
    ASSERT x86_cpu_exec_module_start = x86_cpu_state_module_end
    ASSERT x86_modrm_module_end > x86_modrm_module_start
    ASSERT x86_modrm_module_start = x86_cpu_exec_module_end
    ASSERT x86_alu_module_start = x86_modrm_module_end
    ASSERT x86_alu_module_end > x86_alu_module_start
    ASSERT x86_io_module_end > x86_io_module_start
    ASSERT x86_io_module_start = x86_alu_module_end
    ASSERT p126_ngs_ipc_module_end > p126_ngs_ipc_module_start
    ASSERT p126_ngs_ipc_module_start = x86_io_module_end
    ASSERT p126_ngs_ipc_module_end <= #4000
