; =========================================================================
; PROJECT126 — ATM / NeoGS IPC public interface
; Version: P126_ATM_IPC_API v0.2.0
;
; Include this file in ATM-side Z80 modules that call neogs_ipc.asm.
; Physical transport: GSCOM/GSSTAT (#BB), GSDAT (#B3), GSCTR (#33).
; The ATM-side driver never accesses NeoGS-local DMA registers.
; =========================================================================
        INCLUDE "shared/p126_ipc_protocol.inc"

P126_GSCOM          EQU #BB
P126_GSSTAT         EQU #BB
P126_GSDAT          EQU #B3
P126_GSCTR          EQU #33

P126_CBIT           EQU 0
P126_DBIT           EQU 7
P126_M_CBIT         EQU #01
P126_M_DBIT         EQU #80

P126_GS_RESET       EQU #80
P126_GS_NMI         EQU #40
P126_GS_LED         EQU #20

; Driver result convention:
;   Carry clear = operation completed.
;   Carry set   = timeout.
;   A           = last observed GSSTAT on timeout / final status on wait.
;   p126_ipc_last_status always contains the last sampled GSSTAT byte.

; Public entry points (see docs/ATM_HOST_INTERFACE.md):
;   p126_ipc_read_status
;   p126_ipc_wait_cbit_clear
;   p126_ipc_wait_dbit_clear
;   p126_ipc_wait_dbit_set
;   p126_ipc_send_command       A=command
;   p126_ipc_send_argument      A=argument; preloads GSDAT before GSCOM
;   p126_ipc_send_byte          A=data; waits for consumption
;   p126_ipc_receive_byte       returns A=data
;   p126_ipc_emit_version
;   p126_ipc_validate_frame HL=frame, BC=size; carry/A=status
;   p126_ipc_dma_send_frame HL=frame, BC=size; carry/A=status
;   p126_ipc_dma_receive_test returns carry clear only after reverse-DMA CRC/pattern PASS
; ABI 1.0 constants are imported from shared/p126_ipc_protocol.inc.

P126_IPC_TIMEOUT    EQU #FFFF
