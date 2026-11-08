; =========================================================================
; PROJECT126 — NeoGS IPC protocol primitive assembly unit v0.1.0
; Relocatable image offsets only; no final NeoGS RAM placement is implied.
; =========================================================================

        ORG 0

        INCLUDE "shared/p126_neogs_memory_map.inc"

p126_ngs_ipc_module_start:
        INCLUDE "neogs_sub/p126_ipc.asm"
p126_ngs_ipc_module_end:

; Standalone IPC audit unit: the production image links these symbols from
; x86_cpu_state.asm. Keep local audit-only storage and a no-op trace entry so
; this translation unit can be assembled independently without duplicating
; or replacing the production CPU implementation.
; The production resident image defines this in p126_overlay_gate.asm.
p126_overlay_current_selector: db #80
p126_overlay_request_selector: db #80

; Audit-only gate and X86EXEC probe symbols. Production links the real
; resident WIN2 gate and page-07 dispatcher from the main NeoGS assembly.
p126_overlay_call:
        ret

x86_exec_overlay_probe:
        ld      a,#E7
        ret

; Standalone IPC assembly substitutes a local no-op for the production gate target.
x86_io_reset:
        ret

; Standalone IPC audit substitutes the fixed-origin X86DEV reset entry.
x86_dev_reset:
        ret

; Standalone IPC audit substitutes the fixed-origin ALU probe entry.
x86_alu_overlay_probe:
        ld      a,#A5
        ret

x86_bios_trace_event_status: db 0
x86_bios_trace_event_cs:     dw 0
x86_bios_trace_event_ip:     dw 0
x86_bios_image_diag:
        ret

x86_bios_startup_trace:
        ret

    DISPLAY "P126_NGS_IPC_START=", /H, p126_ngs_ipc_module_start
    DISPLAY "P126_NGS_IPC_END=", /H, p126_ngs_ipc_module_end
    DISPLAY "P126_NGS_IPC_SIZE=", /D, p126_ngs_ipc_module_end-p126_ngs_ipc_module_start

    ASSERT p126_ngs_ipc_module_end > p126_ngs_ipc_module_start
    ASSERT p126_ngs_ipc_module_end <= #10000
