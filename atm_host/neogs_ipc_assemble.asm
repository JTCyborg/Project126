; =========================================================================
; PROJECT126 — ATM host IPC assembly translation unit v0.2.0
; ORG 0000h is a relocatable image offset, not the final ATM load address.
; The module placement is exported to ATM.lst / ATM.map for audit.
; =========================================================================

        ORG     0

p126_atm_ipc_module_start:
        INCLUDE "atm_host/neogs_ipc.asm"
p126_atm_ipc_module_end:

; The standalone IPC audit unit does not link the ATM screen-console module.
; Provide audit-only renderer state/entry points so the IPC translation unit
; can be assembled independently. The production ATM application links the
; real definitions from p126_screen_console.asm.
p126_atm_video_mode:
        db P126_ATM_VIDEO_MODE_RG6_TEXT80X25

p126_screen_apply_text_frame:
        xor     a
        ret

BIOS_DebugConsole_PrintChar:
        ret

    DISPLAY "P126_ATM_IPC_START=", /H, p126_atm_ipc_module_start
    DISPLAY "P126_ATM_IPC_END=", /H, p126_atm_ipc_module_end
    DISPLAY "P126_ATM_IPC_SIZE=", /D, p126_atm_ipc_module_end-p126_atm_ipc_module_start

    ASSERT p126_atm_ipc_module_end > p126_atm_ipc_module_start
    ASSERT p126_atm_ipc_module_end <= #10000
