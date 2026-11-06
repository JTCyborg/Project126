; =========================================================================
; PROJECT126 — ATM Turbo 2+ host application
; Version: P126_ATM_HOST v0.1.0
;
; Loaded by boot.B from TR-DOS as PROJ126.C at 6000h.
; This is the initial host shell: it identifies the running ATM module and
; exposes the ATM-side NeoGS IPC driver. Application service protocol and
; NeoGS firmware upload/start are separate implementation stages.
; =========================================================================

        DEVICE ZXSPECTRUM128

P126_HOST_LOAD_ADDRESS EQU 24576
P126_HOST_ENTRY_POINT  EQU P126_HOST_LOAD_ADDRESS+9
P126_HOST_STACK_TOP    EQU #AFFF

        PAGE 0
        ORG P126_HOST_LOAD_ADDRESS

p126_host_program_start:
        jp      p126_host_entry
        BLOCK   6, 0

p126_host_entry:
        di
        ld      sp, P126_HOST_STACK_TOP

        ld      hl, p126_host_version_text
        call    p126_host_debug_string
        call    p126_ipc_emit_version

p126_host_idle:
        halt
        jr      p126_host_idle

; ATM debug output is independent of NeoGS debug output.
p126_host_debug_string:
        push    af
        push    bc
        ld      bc, #00EF
.p126_host_debug_loop:
        ld      a, (hl)
        inc     hl
        or      a
        jr      z, .p126_host_debug_done
        out     (c), a
        jr      .p126_host_debug_loop
.p126_host_debug_done:
        pop     bc
        pop     af
        ret

p126_host_version_text:
        db "[P126 ATM HOST v0.1.0]", 13, 10, 0

        INCLUDE "atm_host/neogs_ipc.asm"

p126_host_program_end:
        ASSERT p126_host_program_start = P126_HOST_LOAD_ADDRESS
        ASSERT p126_host_entry = P126_HOST_ENTRY_POINT
        ASSERT p126_host_program_end <= #A800
