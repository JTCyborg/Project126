; =========================================================================
; PROJECT126 — NeoGS IPC protocol primitive assembly unit v0.1.0
; Relocatable image offsets only; no final NeoGS RAM placement is implied.
; =========================================================================

        ORG 0

p126_ngs_ipc_module_start:
        INCLUDE "neogs_sub/p126_ipc.asm"
p126_ngs_ipc_module_end:

    DISPLAY "P126_NGS_IPC_START=", /H, p126_ngs_ipc_module_start
    DISPLAY "P126_NGS_IPC_END=", /H, p126_ngs_ipc_module_end
    DISPLAY "P126_NGS_IPC_SIZE=", /D, p126_ngs_ipc_module_end-p126_ngs_ipc_module_start

    ASSERT p126_ngs_ipc_module_end > p126_ngs_ipc_module_start
    ASSERT p126_ngs_ipc_module_end <= #10000
