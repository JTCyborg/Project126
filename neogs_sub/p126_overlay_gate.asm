; =========================================================================
; PROJECT126 — resident WIN2 overlay call gate
;
; API:
;   A  = overlay physical-page selector (ROR8(page), MPAG port 00h)
;   IX = entry address in the 8000h-BFFFh overlay window
;   CALL p126_overlay_call
;
; The gate preserves AF, BC, DE, HL, IY and the caller's stack. IX is consumed
; as the entry pointer. The selected page is restored before the original
; caller return address is popped. Nested calls are supported because each
; invocation saves its previous selector on the WIN1 stack.
;
; Request selector and entry are copied to resident scratch before entering
; the module; nested invocations may safely overwrite that scratch.
; Host Z80 interrupts remain disabled by the resident execution contract.
; =========================================================================

p126_overlay_call:
        ld      (p126_overlay_gate_entry),ix
        ld      (p126_overlay_request_selector),a
        ex      af,af'                   ; preserve guest-independent caller AF
        ld      a,(p126_overlay_current_selector)
        push    af                       ; nested frame: previous WIN2 selector
        ld      a,(p126_overlay_request_selector)
        ld      (p126_overlay_current_selector),a
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ld      hl,p126_overlay_gate_return
        push    hl                       ; module RET lands in resident code
        ld      ix,(p126_overlay_gate_entry)
        ex      af,af'                   ; restore caller AF for module entry
        jp      (ix)

p126_overlay_gate_return:
        pop     af                       ; restore previous WIN2 selector
        ld      (p126_overlay_current_selector),a
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ret

; Stable resident entry points. Each wrapper sets the X86IO page selector,
; then enters the common gate. IX is preserved for the CPU executor.
x86_io_reset:
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      ix,x86_io_reset_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_keyboard_push:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      ix,x86_io_keyboard_push_impl
        ; Preserve the scan code in AF while selecting the overlay.
        ; The request selector is stored separately by the common gate.
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_keyboard_push_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_read8:
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      ix,x86_io_read8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_read16:
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      ix,x86_io_read16_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_write8:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_write8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_write16:
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      ix,x86_io_write16_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_log_access:
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      ix,x86_io_log_access_impl
        call    p126_overlay_call
        pop     ix
        ret

p126_overlay_current_selector: db #80
p126_overlay_request_selector: db #80
p126_overlay_gate_entry:       dw 0
