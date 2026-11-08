; =========================================================================
; PROJECT126 — ATM Turbo 2+ host application
; Version: P126_ATM_HOST v0.2.0
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
        ; First instruction-level proof that BASIC USR reached 6009h.
        ; Keep this before display/paging setup so the marker is independent
        ; of the ATM text renderer and its memory-map changes.
        ld      bc, #00EF
        ld      a, '>'
        out     (c), a

        di
        ld      sp, P126_HOST_STACK_TOP

        ; Match Project125's proven TR-DOS startup mapping exactly.
        ; All disk access must finish before ATM shadow-port/video setup.
        ld      a, #10
        ld      bc, #7FFD
        out     (c), a
        ld      (#5C3B), a
        xor     a
        ld      bc, #EFF7
        out     (c), a

        ; Start NeoGS and transfer its resident/overlay images first.
        ; TR-DOS file operations may alter shared disk/ROM workspace, so
        ; the catalogue buffer is populated only after all image transfers.
        ld      hl, p126_log_ngs_begin
        call    p126_host_debug_string
        call    p126_neogs_startup
        jp      c,p126_host_ngs_start_failed
        ld      a,1
        ld      (p126_host_ngs_ready),a
        ld      hl,p126_log_ngs_ready
        call    p126_host_debug_string
        jp      p126_host_ngs_start_done
p126_host_ngs_start_failed:
        ld      hl,p126_log_ngs_failed
        call    p126_host_debug_string
        call    p126_host_log_prefix
        ld      bc,#00EF
        ld      a,'['
        out     (c),a
        ld      a,'B'
        out     (c),a
        ld      a,'O'
        out     (c),a
        ld      a,'O'
        out     (c),a
        ld      a,'T'
        out     (c),a
        ld      a,']'
        out     (c),a
        ld      a,' '
        out     (c),a
        ld      a,'N'
        out     (c),a
        ld      a,'G'
        out     (c),a
        ld      a,'S'
        out     (c),a
        ld      a,' '
        out     (c),a
        ld      a,'F'
        out     (c),a
        ld      a,'A'
        out     (c),a
        ld      a,'I'
        out     (c),a
        ld      a,'L'
        out     (c),a
        ld      a,' '
        out     (c),a
        ld      a,'S'
        out     (c),a
        ld      a,'T'
        out     (c),a
        ld      a,'A'
        out     (c),a
        ld      a,'G'
        out     (c),a
        ld      a,'E'
        out     (c),a
        ld      a,'='
        out     (c),a
        ld      a,(p126_neogs_startup_stage)
        out     (c),a
        ; Include the manifest descriptor length and loader error in the
        ; failure line. Stage V means the file opened but was not 55 bytes.
        ld      a,' '
        out     (c),a
        ld      a,'L'
        out     (c),a
        ld      a,'E'
        out     (c),a
        ld      a,'N'
        out     (c),a
        ld      a,'='
        out     (c),a
        ld      a,(p126_neogs_file_length+1)
        call    p126_host_debug_hex_byte
        ld      a,(p126_neogs_file_length)
        call    p126_host_debug_hex_byte
        ld      a,' '
        out     (c),a
        ld      a,'E'
        out     (c),a
        ld      a,'R'
        out     (c),a
        ld      a,'R'
        out     (c),a
        ld      a,'='
        out     (c),a
        ld      a,(p126_neogs_startup_error)
        call    p126_host_debug_hex_byte
        ; Identify the exact manifest record currently being validated.
        ld      a,' '
        out     (c),a
        ld      a,'R'
        out     (c),a
        ld      a,'I'
        out     (c),a
        ld      a,'D'
        out     (c),a
        ld      a,'='
        out     (c),a
        ld      a,(p126_neogs_manifest_record_index)
        call    p126_host_debug_hex_byte
        ld      a,' '
        out     (c),a
        ld      a,'R'
        out     (c),a
        ld      a,'S'
        out     (c),a
        ld      a,'='
        out     (c),a
        ld      a,(p126_neogs_manifest_record_size+1)
        call    p126_host_debug_hex_byte
        ld      a,(p126_neogs_manifest_record_size)
        call    p126_host_debug_hex_byte
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a
p126_host_ngs_start_done:
        ; Read the complete directory LAST, after all TR-DOS file operations
        ; used by the NeoGS loader. Keep this before ATM video/paging setup.
        ld      hl, p126_log_trdos_begin
        call    p126_host_debug_string
        call    p126_catalog_read_disk
        ld      a, 1
        ld      (p126_catalog_preloaded), a
        ld      hl, p126_log_trdos_done
        call    p126_host_debug_string

        ld      hl, p126_log_video_begin
        call    p126_host_debug_string
        call    p126_atm_video_init
        ld      hl, p126_log_video_done
        call    p126_host_debug_string

        ; Probe the Project125 DS12887 RTC backend only after shadow-port
        ; decoding is active.

        call    DS12887_PROBE
        ld      hl, p126_log_rtc_done
        call    p126_host_debug_string

        ; RTC gate close restores DOSEN through the ROM trampoline, which
        ; can leave the ATM windows on a different page selection. Reassert
        ; the host code page and page-0 IPC staging buffer before building
        ; the first frame at #C000.
        call    p126_screen_restore_host_pages

        ; Publish the actual host video mode to NeoGS before the converter
        ; is allowed to produce an ATM-native frame.
        call    p126_neogs_send_video_mode
        jr      nc,p126_host_video_mode_sent
        ld      hl,p126_log_video_mode_failed
        call    p126_host_debug_string
        jr      p126_host_video_mode_done
p126_host_video_mode_sent:
        ld      hl,p126_log_video_mode_sent
        call    p126_host_debug_string
p126_host_video_mode_done:
        ld      hl, p126_host_version_text
        call    p126_host_debug_string
        call    p126_host_log_prefix
        call    p126_ipc_emit_version

        ld      hl, p126_log_console_begin
        call    p126_host_debug_string
        call    BIOS_DebugConsole_Init
        call    BIOS_DebugConsole_Clear
        call    BIOS_DebugConsole_DrawInterface
        ld      a,1
        ld      (p126_host_console_ready),a
        ld      hl, p126_host_ui_log
        call    p126_host_console_string
        ld      hl, p126_log_console_done
        call    p126_host_debug_string
        call    p126_catalog_initialize
        ld      hl, p126_log_catalog_return
        call    p126_host_debug_string

        ; The 16 KiB DMA smoke-test buffers overlap the TR-DOS directory
        ; buffer at #C800. Keep destructive DMA diagnostics out of the normal
        ; catalogue session; run them only in the dedicated DMA test build.

p126_host_idle:
        call    p126_catalog_poll_keyboard
        call    p126_host_poll_x86_keyboard
        ld      a,(p126_atm_video_enabled)
        or      a
        jr      z,.host_idle_continue
        ld      a,(p126_host_video_poll_counter)
        inc     a
        ld      (p126_host_video_poll_counter),a
        cp      64
        jr      nz,.host_idle_continue
        xor     a
        ld      (p126_host_video_poll_counter),a

        ; E1 is also the BIOS execution scheduler: NeoGS runs the next
        ; bounded 64-instruction slice before returning its stop/status frame.
        ; Polling VIDEO alone leaves the guest frozen after the first slice.
        call    p126_ipc_dma_receive_debug_frame
        jr      c,.host_idle_continue

        ; E2 converts the current VGA state. F2 ("not in a supported text
        ; mode yet") is a normal pending result; keep polling until BIOS
        ; actually produces a renderable frame.
        call    p126_ipc_dma_receive_video_frame
        jr      nc,.host_idle_continue
        ; A transport/validation failure is fatal to the current video poll.
        xor     a
        ld      (p126_atm_video_enabled),a
.host_idle_continue:
        jr      p126_host_idle

; Set only after the screen has been initialized and mapped.
p126_host_console_ready: db 0

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
        db "NeoGS BOOTSTRAP LOADER ENABLED",13,10
        db "8086 execution: NOT STARTED",13,10,0

; ATM debug output is independent of NeoGS debug output.
p126_host_debug_string:
        ; Mirror ATM-originated diagnostic text to the on-screen console.
        ; Keep the #EF stream intact for emulator logs.
        push    hl
        push    af
        ld      a,(p126_host_console_ready)
        or      a
        jr      z,.host_debug_no_console
        pop     af
        push    af
        call    p126_host_console_string
.host_debug_no_console:
        pop     af
        pop     hl
        call    p126_host_log_prefix
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


; Prefix every ATM-originated #EF message with the host RTC timestamp.
; NeoGS output must bypass this routine and use the independent [NGS] path.
p126_host_log_prefix:
        push    af
        push    bc
        push    hl
        ld      bc, #00EF
        ld      a, '['
        out     (c), a
        ld      a, (ds12887_available)
        or      a
        jr      z, .p126_time_unknown
        call    READ_CURRENT_TIME
        ld      a, (txt_hour)
        out     (c), a
        ld      a, (txt_hour+1)
        out     (c), a
        ld      a, ':'
        out     (c), a
        ld      a, (txt_min)
        out     (c), a
        ld      a, (txt_min+1)
        out     (c), a
        ld      a, ':'
        out     (c), a
        ld      a, (txt_sec)
        out     (c), a
        ld      a, (txt_sec+1)
        out     (c), a
        jr     .p126_time_close
.p126_time_unknown:
        ld      a, '?'
        out     (c), a
        out     (c), a
        out     (c), a
        out     (c), a
        out     (c), a
        out     (c), a
        out     (c), a
        out     (c), a
.p126_time_close:
        ld      a, ']'
        out     (c), a
        ; ATM tag is emitted as individual bytes below.
        ld      a, '['
        out     (c), a
        ld      a, 'A'
        out     (c), a
        ld      a, 'T'
        out     (c), a
        ld      a, 'M'
        out     (c), a
        ld      a, ']'
        out     (c), a
        ld      a, ' '
        out     (c), a
        pop     hl
        pop     bc
        pop     af
        ret

; Print A as two hexadecimal digits to ATM's independent #EF stream.
p126_host_debug_hex_byte:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    p126_host_debug_hex_nibble
        pop     af
        jp      p126_host_debug_hex_nibble

p126_host_debug_hex_nibble:
        and     #0F
        add     a,'0'
        cp      '9'+1
        jr      c,.p126_host_hex_emit
        add     a,7
.p126_host_hex_emit:
        push    bc
        ld      bc,#00EF
        out     (c),a
        pop     bc
        ret

p126_host_ngs_ready: db 0

p126_log_ngs_begin: db "[BOOT] NEOGS RESIDENT START BEGIN",13,10,0
p126_log_ngs_ready: db "[BOOT] NEOGS RESIDENT READY",13,10,0
p126_log_ngs_failed: db "[BOOT] NEOGS RESIDENT START FAILED",13,10,0
p126_log_trdos_begin:   db "[BOOT] TRDOS DIRECTORY READ BEGIN",13,10,0
p126_log_trdos_done:    db "[BOOT] TRDOS DIRECTORY READ RETURN",13,10,0
p126_log_video_begin:   db "[BOOT] ATM VIDEO INIT BEGIN",13,10,0
p126_log_video_done:    db "[BOOT] ATM VIDEO INIT DONE",13,10,0
p126_log_rtc_done:      db "[BOOT] RTC PROBE RETURN",13,10,0
p126_log_video_mode_sent: db "[BOOT] ATM VIDEO MODE SENT TO NEOGS",13,10,0
p126_log_video_mode_failed: db "[BOOT] ATM VIDEO MODE SEND FAILED",13,10,0
p126_host_video_poll_counter: db 0
p126_log_console_begin: db "[BOOT] CONSOLE INIT BEGIN",13,10,0
p126_log_console_done:  db "[BOOT] CONSOLE INIT DONE",13,10,0
p126_log_catalog_return: db "[BOOT] CATALOG INIT RETURN",13,10,0

p126_host_version_text:
        db "[P126 ATM HOST v0.2.0]", 13, 10, 0

        INCLUDE "atm_host/ds12887_rtc.asm"
        INCLUDE "atm_host/neogs_ipc.asm"
        INCLUDE "atm_host/p126_disk_catalog.asm"
        INCLUDE "atm_host/p126_neogs_loader.asm"
        INCLUDE "atm_host/p126_bios_loader.asm"

; Project125-derived ATM-native text console, relocated to window 2.
; Its renderer maps video pages only for each write and restores host pages.
        PAGE 0
        ORG #A000
        INCLUDE "atm_host/p126_screen_console.asm"

p126_host_program_end:
        ASSERT p126_host_program_start = P126_HOST_LOAD_ADDRESS
        ASSERT p126_host_entry = P126_HOST_ENTRY_POINT
        ASSERT p126_host_program_end <= #A800
