; PROJECT126 / X86 ASSEMBLY UNIT v0.6.0
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

x86_cpu_state_module_start:
        INCLUDE "neogs_sub/x86_cpu_state.asm"
x86_cpu_state_module_end:

x86_alu_module_start:
        INCLUDE "neogs_sub/x86_alu.asm"
x86_alu_module_end:

; Export explicit boundaries for build/map inspection.
    DISPLAY "P126_X86_STATE_START=", /H, x86_cpu_state_module_start
    DISPLAY "P126_X86_STATE_END=", /H, x86_cpu_state_module_end
    DISPLAY "P126_X86_STATE_SIZE=", /D, x86_cpu_state_module_end-x86_cpu_state_module_start
    DISPLAY "P126_X86_ALU_START=", /H, x86_alu_module_start
    DISPLAY "P126_X86_ALU_END=", /H, x86_alu_module_end
    DISPLAY "P126_X86_ALU_SIZE=", /D, x86_alu_module_end-x86_alu_module_start
    DISPLAY "P126_X86_IMAGE_END=", /H, x86_alu_module_end
    DISPLAY "P126_X86_IMAGE_SIZE=", /D, x86_alu_module_end

    ASSERT x86_cpu_state_module_end > x86_cpu_state_module_start
    ASSERT x86_alu_module_end > x86_alu_module_start
    ASSERT x86_alu_module_start = x86_cpu_state_module_end
    ASSERT x86_alu_module_end <= #40000
