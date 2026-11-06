; PROJECT126 / X86 ASSEMBLY UNIT v0.5.0
; Address-space audit unit, assembled at logical image origin 0000h.
; The listing and symbol map are mandatory build products.
; These offsets describe the assembled module image, not yet the final
; physical NeoGS load address (runtime placement remains a separate stage).

        ORG     0

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
