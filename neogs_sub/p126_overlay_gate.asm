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
; The request selector, entry and caller HL are copied/restored before module entry, so
; nested calls may safely reuse the resident scratch bytes/words.
; Host Z80 interrupts remain disabled by the resident execution contract.
; =========================================================================

P126_OVERLAY_MAX_CALL_DEPTH EQU 8

p126_overlay_call:
        ld      (p126_overlay_gate_entry),ix
        ld      (p126_overlay_gate_saved_hl),hl
        ex      af,af'                   ; keep caller AF while using A
        ld      a,(p126_overlay_call_depth)
        cp      P126_OVERLAY_MAX_CALL_DEPTH
        jr      nc,p126_overlay_depth_rejected
        inc     a
        ld      (p126_overlay_call_depth),a
        ; Record the requested page for active-page release protection.
        push    de
        ld      ix,p126_overlay_call_pages
        dec     a
        ld      e,a
        ld      d,0
        add     ix,de
        ld      a,(p126_overlay_request_selector)
        ld      (ix+0),a
        pop     de
        ld      a,(p126_overlay_current_selector)
        push    af                       ; per-call previous-selector frame
        ld      a,(p126_overlay_request_selector)
        ld      (p126_overlay_current_selector),a
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ld      hl,p126_overlay_gate_return
        push    hl                       ; overlay RET enters resident WIN0
        ld      ix,(p126_overlay_gate_entry)
        ld      hl,(p126_overlay_gate_saved_hl)
        ex      af,af'                   ; restore caller AF for module
        jp      (ix)

p126_overlay_gate_return:
        ex      af,af'                   ; preserve module return AF
        pop     af                       ; restore previous WIN2 selector
        ld      (p126_overlay_current_selector),a
        out     (P126_NGS_OVERLAY_WINDOW_PORT),a
        ; Clear this active-page slot before decrementing the frame depth.
        push    de
        ld      a,(p126_overlay_call_depth)
        dec     a
        ld      e,a
        ld      d,0
        ld      ix,p126_overlay_call_pages
        add     ix,de
        xor     a
        ld      (ix+0),a
        pop     de
        ld      a,(p126_overlay_call_depth)
        dec     a
        ld      (p126_overlay_call_depth),a
        ex      af,af'                   ; restore module return AF
        ret

p126_overlay_depth_rejected:
        ; No selector change or stack frame is made on overflow.
        ld      hl,(p126_overlay_gate_saved_hl)
        ex      af,af'                   ; restore the caller's alternate AF
        ld      a,P126_STATUS_BUSY
        scf
        ret

; -------------------------------------------------------------------------
; Physical overlay-page allocator.
; Pool: physical pages 08h..0Fh. Pages 04h/05h/06h/07h are pinned to X86IO/X86ALU/X86DEV/X86EXEC;
; pages 00h..03h are never allocator-owned. WIN3 is not used here.
;
; p126_overlay_allocate_page:
;   OUT A=physical page 07h..0Fh, carry clear; A=0/carry set if exhausted.
;   Clobbers BC, IX.
;
; p126_overlay_release_page:
;   IN A=physical page. Carry clear on release; carry set with A=status on
;   invalid, already-free, currently mapped, or actively executing page.
;   Clobbers BC, DE, HL, IX.
; -------------------------------------------------------------------------
p126_overlay_allocate_page:
        ld      ix,p126_overlay_alloc_state+1
        ld      b,8
        ld      c,8
.allocate_scan:
        ld      a,(ix+0)
        or      a
        jr      z,.allocate_found
        inc     ix
        inc     c
        djnz    .allocate_scan
        xor     a
        scf
        ret
.allocate_found:
        ld      a,1
        ld      (ix+0),a
        ld      a,c
        or      a
        ret

p126_overlay_release_page:
        cp      8
        jp      c,.release_range_error
        cp      16
        jp      nc,.release_range_error
        push    af
        rrca
        ld      c,a                       ; physical page -> WIN2 selector
        ld      a,(p126_overlay_current_selector)
        cp      c
        jr      z,.release_busy
        ld      a,(p126_overlay_call_depth)
        ld      b,a
        ld      ix,p126_overlay_call_pages
.release_active_scan:
        ld      a,b
        or      a
        jr      z,.release_not_active
        ld      a,(ix+0)
        cp      c
        jr      z,.release_busy
        inc     ix
        djnz    .release_active_scan
.release_not_active:
        pop     af
        sub     7
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_alloc_state
        add     hl,de
        ld      a,(hl)
        or      a
        jr      z,.release_range_error
        xor     a
        ld      (hl),a
        or      a
        ret
.release_busy:
        pop     af
        ld      a,P126_STATUS_BUSY
        scf
        ret
.release_range_error:
        ld      a,P126_STATUS_ADDRESS_RANGE
        scf
        ret

; Startup regression for the dynamic page allocator. Page07 is pinned to
; X86EXEC; only pages08..0F are available for dynamic allocation.
; OUT: carry clear on pass; carry set on failure. Startup halts on failure.
p126_overlay_allocator_selftest:
        push    bc
        push    de
        push    hl
        push    ix
        ld      hl,p126_overlay_allocator_test_pages
        ld      b,8
        ld      c,8
.allocator_test_allocate:
        push    bc
        call    p126_overlay_allocate_page
        pop     bc
        jp      c,.allocator_test_failed
        cp      c
        jp      nz,.allocator_test_failed
        ld      (hl),a
        inc     hl
        inc     c
        djnz    .allocator_test_allocate

        ; All eight dynamic pages must now be reserved.
        push    bc
        call    p126_overlay_allocate_page
        pop     bc
        jr      nc,.allocator_test_failed
        or      a
        jr      nz,.allocator_test_failed

        ; Release every page in reverse order.
        ld      hl,p126_overlay_allocator_test_pages+7
        ld      b,8
.allocator_test_release:
        ld      a,(hl)
        push    bc
        push    hl
        call    p126_overlay_release_page
        pop     hl
        pop     bc
        jr      c,.allocator_test_failed
        dec     hl
        djnz    .allocator_test_release

        ; First-fit reuse must return page08; page07 remains pinned.
        push    bc
        call    p126_overlay_allocate_page
        pop     bc
        jr      c,.allocator_test_failed
        cp      8
        jr      nz,.allocator_test_failed
        call    p126_overlay_release_page
        jr      c,.allocator_test_failed

        pop     ix
        pop     hl
        pop     de
        pop     bc
        xor     a
        ret
.allocator_test_failed:
        pop     ix
        pop     hl
        pop     de
        pop     bc
        ld      a,P126_STATUS_BAD_FRAME
        scf
        ret

; -------------------------------------------------------------------------
; Resident module registry for dynamically placed overlays.
; IDs 1..4 are pinned (X86IO/X86ALU/X86DEV/X86EXEC). IDs 5..15 may own
; one allocator page in 08h..0Fh. The registry stores physical page numbers;
; call dispatch derives the WIN2 selector only at the point of use.
;
; p126_overlay_register_dynamic: IN A=module ID (5..15), B=physical page (08..0F).
; p126_overlay_unregister_dynamic: IN A=module ID (5..15).
; p126_overlay_call_module: IN A=loaded module ID, IX=entry in 8000h..BFFFh.
; -------------------------------------------------------------------------
p126_overlay_register_dynamic:
        cp      5
        jp      c,.module_register_range_error
        cp      16
        jp      nc,.module_register_range_error
        ld      (p126_overlay_manager_id),a
        ld      a,b
        cp      8
        jp      c,.module_register_range_error
        cp      16
        jp      nc,.module_register_range_error
        ld      (p126_overlay_manager_page),a

        ; Reject an already-registered module ID.
        ld      a,(p126_overlay_manager_id)
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_module_page_table
        add     hl,de
        ld      a,(hl)
        or      a
        jr      nz,.module_register_busy

        ; Claim the exact physical page in the existing allocator bitmap.
        ld      a,(p126_overlay_manager_page)
        sub     7
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_alloc_state
        add     hl,de
        ld      a,(hl)
        or      a
        jr      nz,.module_register_busy
        ld      a,1
        ld      (hl),a

        ; Publish the registry entry only after the allocator claim succeeds.
        ld      a,(p126_overlay_manager_id)
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_module_page_table
        add     hl,de
        ld      a,(p126_overlay_manager_page)
        ld      (hl),a
        xor     a
        ret
.module_register_busy:
        ld      a,P126_STATUS_BUSY
        scf
        ret
.module_register_range_error:
        ld      a,P126_STATUS_ADDRESS_RANGE
        scf
        ret

p126_overlay_unregister_dynamic:
        cp      5
        jr      c,.module_unregister_range_error
        cp      16
        jr      nc,.module_unregister_range_error
        ld      (p126_overlay_manager_id),a
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_module_page_table
        add     hl,de
        ld      a,(hl)
        or      a
        jr      z,.module_unregister_not_loaded
        call    p126_overlay_release_page
        ret     c

        ; Clear the registry only after the allocator confirms release.
        ld      a,(p126_overlay_manager_id)
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_module_page_table
        add     hl,de
        xor     a
        ld      (hl),a
        ret
.module_unregister_not_loaded:
        ld      a,P126_STATUS_NO_SERVICE
        scf
        ret
.module_unregister_range_error:
        ld      a,P126_STATUS_ADDRESS_RANGE
        scf
        ret

p126_overlay_call_module:
        cp      1
        jr      c,.module_call_not_loaded
        cp      16
        jr      nc,.module_call_not_loaded
        ld      (p126_overlay_manager_id),a
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_module_page_table
        add     hl,de
        ld      a,(hl)
        or      a
        jr      z,.module_call_not_loaded
        rrca
        ld      (p126_overlay_request_selector),a
        ld      a,(p126_overlay_manager_id)
        jp      p126_overlay_call
.module_call_not_loaded:
        ld      a,P126_STATUS_NO_SERVICE
        scf
        ret

; Startup regression: use an actually unused dynamic module ID and page,
; verify registration/lookup/unregister, then prove immediate page reuse.
p126_overlay_manager_selftest:
        ; Select a genuinely free physical page. Other startup steps may
        ; already have loaded X86VGA/X86VID on pages08h+.
        ld      a,1
        ld      (p126_overlay_manager_test_stage),a
        call    p126_overlay_allocate_page
        jp      c,.module_manager_test_bad
        ld      (p126_overlay_manager_page),a
        ld      a,2
        ld      (p126_overlay_manager_test_stage),a
        ld      a,(p126_overlay_manager_page)
        call    p126_overlay_release_page
        jp      c,.module_manager_test_bad

        ; IDs05..0F are dynamic. Find a free registry slot instead of
        ; assuming ID05 is unused (X86VGA/X86VID may already own it).
        ld      a,3
        ld      (p126_overlay_manager_test_stage),a
        ld      hl,p126_overlay_module_page_table+15
        ld      b,11
        ld      c,15
.module_manager_find_free_id:
        ld      a,(hl)
        or      a
        jr      z,.module_manager_free_id_found
        dec     hl
        dec     c
        djnz    .module_manager_find_free_id
        jp      .module_manager_test_bad
.module_manager_free_id_found:
        ld      a,c
        ld      (p126_overlay_manager_test_id),a

        ; Register the selected ID on the released page.
        ld      a,(p126_overlay_manager_page)
        ld      b,a
        ld      a,(p126_overlay_manager_test_id)
        call    p126_overlay_register_dynamic
        jp      c,.module_manager_test_bad

        ; Verify the exact registry slot.
        ld      a,4
        ld      (p126_overlay_manager_test_stage),a
        ld      a,(p126_overlay_manager_test_id)
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_module_page_table
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(p126_overlay_manager_page)
        cp      b
        jp      nz,.module_manager_test_bad

        ; Unregister the test module and verify its slot is cleared.
        ld      a,5
        ld      (p126_overlay_manager_test_stage),a
        ld      a,(p126_overlay_manager_test_id)
        call    p126_overlay_unregister_dynamic
        jp      c,.module_manager_test_bad
        ld      a,6
        ld      (p126_overlay_manager_test_stage),a
        ld      a,(p126_overlay_manager_test_id)
        ld      e,a
        ld      d,0
        ld      hl,p126_overlay_module_page_table
        add     hl,de
        ld      a,(hl)
        or      a
        jp      nz,.module_manager_test_bad

        ; The just-unregistered physical page must be immediately reusable.
        ld      a,7
        ld      (p126_overlay_manager_test_stage),a
        call    p126_overlay_allocate_page
        jp      c,.module_manager_test_bad
        ld      b,a
        ld      a,(p126_overlay_manager_page)
        cp      b
        jp      nz,.module_manager_test_bad
        ld      a,8
        ld      (p126_overlay_manager_test_stage),a
        ld      a,b
        call    p126_overlay_release_page
        jp      c,.module_manager_test_bad
        or      a
        ret
.module_manager_test_bad:
        ld      a,(p126_overlay_manager_test_stage)
        cp      1
        ld      hl,p126_overlay_manager_stage1_log
        jr      z,.module_manager_test_log
        cp      2
        ld      hl,p126_overlay_manager_stage2_log
        jr      z,.module_manager_test_log
        cp      3
        ld      hl,p126_overlay_manager_stage3_log
        jr      z,.module_manager_test_log
        cp      4
        ld      hl,p126_overlay_manager_stage4_log
        jr      z,.module_manager_test_log
        cp      5
        ld      hl,p126_overlay_manager_stage5_log
        jr      z,.module_manager_test_log
        cp      6
        ld      hl,p126_overlay_manager_stage6_log
        jr      z,.module_manager_test_log
        cp      7
        ld      hl,p126_overlay_manager_stage7_log
        jr      z,.module_manager_test_log
        ld      hl,p126_overlay_manager_stage8_log
.module_manager_test_log:
        call    p126_ngs_resident_log
        ld      a,P126_STATUS_BAD_FRAME
        scf
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

; Copy page04 I/O counters into resident X86CPU diagnostic storage.
; Direct reads from X86IO labels are invalid when WIN2 maps another overlay.
x86_io_snapshot_counters:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_snapshot_counters_impl
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

; One-shot BIOS watchdog memory dump through the fixed-origin X86IO overlay.
x86_io_dump_bios_table:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_dump_bios_table_impl
        call    p126_overlay_call
        pop     ix
        ret

; Master-PIC interrupt acknowledge. A=vector, carry set if no PIC request.
x86_io_pic_ack:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_pic_ack_impl
        call    p126_overlay_call
        pop     ix
        ret

; Nested-call regression entry: page04 X86IO -> page05 X86ALU.
; Returns A=08h when the page05 ADD8 implementation returned correctly.
x86_io_overlay_nested_gate_probe:
        push    af
        push    ix
        ld      a,P126_NGS_X86IO_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_io_overlay_nested_gate_probe_impl
        call    p126_overlay_call
        pop     ix
        ret

; DMA/PIT device overlay API; implementations live on physical page 06h.
; The public wrappers preserve the guest port/value ABI across WIN2 switching.
x86_dev_reset:
        push    af
        push    ix
        ld      a,P126_NGS_X86DEV_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_dev_reset_impl
        call    p126_overlay_call
        pop     ix
        ret

; IN: HL=guest port. OUT: A=value, carry set if X86DEV does not decode it.
x86_dev_read8:
        push    af
        push    ix
        ld      a,P126_NGS_X86DEV_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_dev_read8_impl
        call    p126_overlay_call
        pop     ix
        ret

; IN: HL=guest port, A=value. OUT: carry set if X86DEV does not decode it.
x86_dev_write8:
        push    af
        push    ix
        ld      a,P126_NGS_X86DEV_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_dev_write8_impl
        call    p126_overlay_call
        pop     ix
        ret

; VGA register access API; X86VGA is dynamically registered on page08h.
; The selector is derived from the agreed physical page and all calls still
; pass through the resident nested overlay gate.
x86_vga_mem_read8:
        push    af
        push    ix
        ld      a,P126_NGS_X86VGA_OVERLAY_PAGE
        rrca
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_vga_mem_read8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_vga_mem_write8:
        push    af
        push    ix
        ld      a,P126_NGS_X86VGA_OVERLAY_PAGE
        rrca
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_vga_mem_write8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_video_convert:
        push    af
        push    ix
        ld      a,P126_NGS_X86VID_OVERLAY_PAGE
        rrca
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_video_convert_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_vga_get_text_snapshot:
        push    af
        push    ix
        ld      a,P126_NGS_X86VGA_OVERLAY_PAGE
        rrca
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_vga_get_text_snapshot_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_vga_read_text_cell:
        push    af
        push    ix
        ld      a,P126_NGS_X86VGA_OVERLAY_PAGE
        rrca
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_vga_read_text_cell_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_vga_reset:
        push    af
        push    ix
        ld      a,P126_NGS_X86VGA_OVERLAY_PAGE
        rrca
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_vga_reset_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_vga_io_read8:
        push    af
        push    ix
        ld      a,P126_NGS_X86VGA_OVERLAY_PAGE
        rrca
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_vga_io_read8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_vga_io_write8:
        push    af
        push    ix
        ld      a,P126_NGS_X86VGA_OVERLAY_PAGE
        rrca
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_vga_io_write8_impl
        call    p126_overlay_call
        pop     ix
        ret

; X86ALU public entry points; implementations live on physical page 05h.
x86_alu_add8:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_add8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_sub8:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_sub8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_add16:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_add16_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_sub16:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_sub16_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_adc8:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_adc8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_sbb8:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_sbb8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_adc16:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_adc16_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_sbb16:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_sbb16_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_logic8:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_logic8_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_logic16:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_logic16_impl
        call    p126_overlay_call
        pop     ix
        ret

x86_alu_overlay_probe:
        push    af
        push    ix
        ld      a,P126_NGS_ALU_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        pop     ix
        pop     af
        push    ix
        ld      ix,x86_alu_overlay_probe_impl
        call    p126_overlay_call
        pop     ix
        ret

p126_overlay_call_depth:      db 0
p126_overlay_current_selector: db #80
p126_overlay_request_selector: db #80
p126_overlay_gate_entry:       dw 0
p126_overlay_gate_saved_hl:    dw 0
p126_overlay_call_pages:       defs P126_OVERLAY_MAX_CALL_DEPTH,0
; Index is the module ID. IDs01..04 are permanently pinned to pages04..07.
p126_overlay_module_page_table:
        db 0,#04,#05,#06,#07
        defs 11,0
p126_overlay_manager_id:       db 0
p126_overlay_manager_page:     db 0
p126_overlay_manager_test_id:  db 0
p126_overlay_manager_test_stage: db 0
p126_overlay_manager_stage1_log: db "[NGS] MODULE MANAGER FAIL STAGE 01 ALLOCATE",13,10,0
p126_overlay_manager_stage2_log: db "[NGS] MODULE MANAGER FAIL STAGE 02 TEMP RELEASE",13,10,0
p126_overlay_manager_stage3_log: db "[NGS] MODULE MANAGER FAIL STAGE 03 REGISTER",13,10,0
p126_overlay_manager_stage4_log: db "[NGS] MODULE MANAGER FAIL STAGE 04 LOOKUP",13,10,0
p126_overlay_manager_stage5_log: db "[NGS] MODULE MANAGER FAIL STAGE 05 UNREGISTER",13,10,0
p126_overlay_manager_stage6_log: db "[NGS] MODULE MANAGER FAIL STAGE 06 CLEAR",13,10,0
p126_overlay_manager_stage7_log: db "[NGS] MODULE MANAGER FAIL STAGE 07 REUSE",13,10,0
p126_overlay_manager_stage8_log: db "[NGS] MODULE MANAGER FAIL STAGE 08 RELEASE",13,10,0
p126_overlay_alloc_state:      defs 9,0
p126_overlay_allocator_test_pages: defs 8,0
