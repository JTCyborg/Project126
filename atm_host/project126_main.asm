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

        ; TR-DOS file access is complete. Bring up the ATM Turbo 2+ native
        ; 80x25 text display only now, after the BASIC/TR-DOS loader returned.
        call    p126_atm_video_init
        call    BIOS_DebugConsole_Init
        call    BIOS_DebugConsole_Clear
        call    BIOS_DebugConsole_DrawInterface
        ld      hl, p126_host_ui_log
        call    p126_host_console_string

p126_host_idle:
        halt
        jr      p126_host_idle

; IN: HL=zero-terminated string. Writes to the lower on-screen log.
p126_host_console_string:
        ld      a, (hl)
        or      a
        ret     z
        call    BIOS_DebugConsole_PrintChar
        inc     hl
        jr      p126_host_console_string

p126_host_ui_log:
        db "ATM HOST SHELL INITIALIZED", 13, 10
        db "NeoGS firmware upload: NOT IMPLEMENTED", 13, 10
        db "8086 execution: NOT STARTED", 13, 10, 0

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

; Project125-derived ATM-native text console, relocated to window 2.
; Its renderer maps video pages only for each write and restores host pages.
        PAGE 0
        ORG #A000
        INCLUDE "atm_host/p126_screen_console.asm"

p126_host_program_end:
        ASSERT p126_host_program_start = P126_HOST_LOAD_ADDRESS
        ASSERT p126_host_entry = P126_HOST_ENTRY_POINT
        ASSERT p126_host_program_end <= #A800
