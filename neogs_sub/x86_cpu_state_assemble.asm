; PROJECT126 / X86_CPU_STATE ASSEMBLY UNIT v0.1.0
; Build-only translation unit.
; It validates that the current x86 architectural-state module is accepted
; by the repository-pinned SjASMPlus assembler.
; This is NOT a runtime image and defines no NeoGS load address or entrypoint.

        ORG     0
        INCLUDE "neogs_sub/x86_cpu_state.asm"
