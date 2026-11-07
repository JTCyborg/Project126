; =========================================================================
; PROJECT126 — resident WIN2 overlay call gate
;
; API:
;   p126_overlay_request_selector = ROR8(physical overlay page)
;   IX = entry address in 8000h-BFFFh
;   CALL p126_overlay_call
;
; AF, BC, DE, HL and IY are preserved at module entry; IX is consumed as
; the entry pointer. The module returns with RET. The resident trampoline
; restores the previous selector before returning to the original caller.
; Each nesting level stores its previous selector on the WIN1 stack.
;
; The request selector and entry are copied before the module is entered, so
; nested calls may safely reuse both resident scratch bytes/words.
; Host Z80 interrupts remain disabled by the resident execution contract.
; =========================================================================

p126_overlay_call:
        ld      (p126_overlay_gate_entry),ix
        ex      af,af'                   ; keep caller AF while using A
        ld      a,(p126_overlay_current_selector)
        push    af                       ; per-call previous-selector frame
        ld      a,(p126_overlay_request_selector)
        ld      (p126_overlay_current_selector),a
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ld      hl,p126_overlay_gate_return
        push    hl                       ; overlay RET enters resident WIN0
        ld      ix,(p126_overlay_gate_entry)
        ex      af,af'                   ; restore caller AF for module
        jp      (ix)

p126_overlay_gate_return:
        ex      af,af'                   ; preserve module return AF
        pop     af                       ; restore previous WIN2 selector
        ld      (p126_overlay_current_selector),a
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ex      af,af'                   ; restore module return AF
        ret

; Compatibility entry points for the existing X86IO ABI. All use the same
; gate, so X86IO remains callable while another overlay owns WIN2.
x86_io_reset:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_reset_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_keyboard_push:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_keyboard_push_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_read8:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_read8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_read16:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
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
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_write16_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_io_log_access:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_log_access_impl
        call    p126_overlay_call
        pop     ix
        ret

p126_overlay_current_selector: db #80
p126_overlay_request_selector: db #80
p126_overlay_gate_entry:       dw 0
