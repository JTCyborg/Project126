; =========================================================================
; PROJECT126 — ATM host IPC assembly translation unit v0.1.0
; ORG 0000h is a relocatable image offset, not the final ATM load address.
; The module placement is exported to ATM.lst / ATM.map for audit.
; =========================================================================

        ORG     0

p126_atm_ipc_module_start:
        INCLUDE "atm_host/neogs_ipc.asm"
p126_atm_ipc_module_end:

    DISPLAY "P126_ATM_IPC_START=", /H, p126_atm_ipc_module_start
    DISPLAY "P126_ATM_IPC_END=", /H, p126_atm_ipc_module_end
    DISPLAY "P126_ATM_IPC_SIZE=", /D, p126_atm_ipc_module_end-p126_atm_ipc_module_start

    ASSERT p126_atm_ipc_module_end > p126_atm_ipc_module_start
    ASSERT p126_atm_ipc_module_end <= #10000
