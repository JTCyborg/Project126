; =========================================================================
; PROJECT126 — ATM-side TR-DOS directory browser
; Reads the native TR-DOS catalogue and allows cursor navigation.
; The directory is read from track 0 into the page-0 buffer at #C800.
; =========================================================================

P126_CATALOG_BUFFER       EQU #C800
P126_CATALOG_ENTRY_COUNT  EQU 128
P126_CATALOG_ENTRY_SIZE   EQU 16
P126_CATALOG_VISIBLE_ROWS EQU 9
P126_CATALOG_FIRST_ROW    EQU 2

; Called after ATM video, RTC and console initialization.
; Disk I/O has already been completed during the legacy TR-DOS boot phase.
p126_catalog_initialize::
        ld      hl, p126_log_catalog_enter
        call    p126_catalog_log
        xor     a
        ld      (p126_catalog_enabled), a
        ld      (p126_catalog_selected), a
        ld      (p126_catalog_scroll), a

        ld      a, (p126_catalog_preloaded)
        or      a
        jr      nz, .catalog_data_preloaded
        ; Defensive fallback for standalone callers; normal startup preloads
        ; the directory before ATM video initialization.
        call    p126_catalog_read_disk
        ld      a, 1
        ld      (p126_catalog_preloaded), a

.catalog_data_preloaded:
        ld      a, (p126_catalog_io_result)
        or      a
        jr      nz, .catalog_read_failed

        ld      hl, p126_log_read_ok
        call    p126_catalog_log
        call    p126_catalog_count_files
        ld      hl, p126_log_count_done
        call    p126_catalog_log
        ld      a, (p126_catalog_total)
        call    p126_host_debug_hex_byte
        push    bc
        ld      bc,#00EF
        ld      a,13
        out     (c),a
        ld      a,10
        out     (c),a
        pop     bc
        ld      a, 1
        ld      (p126_catalog_enabled), a
        ld      hl, p126_log_draw_begin
        call    p126_catalog_log
        call    p126_catalog_draw
        ld      hl, p126_log_draw_done
        call    p126_catalog_log
        ret

.catalog_read_failed:
        ld      hl, p126_log_read_failed
        call    p126_catalog_log
        ld      hl, p126_catalog_error_text
        ld      a, P126_CATALOG_FIRST_ROW
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        ret

; One key press produces one movement. Holding a key does not run the
; selection continuously: the routine waits for its release before returning.
p126_catalog_poll_keyboard::
        ld      a, (p126_catalog_enabled)
        or      a
        ret     z

        call    p126_catalog_scan_keys
        or      a
        ret     z
        ld      (p126_catalog_key), a
        ld      hl, p126_log_key_seen
        call    p126_catalog_log
        call    p126_catalog_wait_release

        ld      a, (p126_catalog_key)
        bit     4, a
        jr      nz,.catalog_confirm
        bit     2, a
        jp      nz,.catalog_page_up
        bit     3, a
        jp      nz,.catalog_page_down
        bit     0, a
        jp      nz, .catalog_move_up
        bit     1, a
        jp      nz, .catalog_move_down
        ret

.catalog_page_up:
        ; CAPS SHIFT+5 (left): move one complete visible page up.
        ld      a,(p126_catalog_selected)
        cp      P126_CATALOG_VISIBLE_ROWS
        jr      nc,.catalog_page_up_subtract
        xor     a
        jr      .catalog_page_up_store
.catalog_page_up_subtract:
        sub     P126_CATALOG_VISIBLE_ROWS
.catalog_page_up_store:
        ld      (p126_catalog_selected),a
        ; Keep the selected entry at the top after a page jump.
        ld      (p126_catalog_scroll),a
        call    p126_catalog_draw
        ret

.catalog_page_down:
        ; CAPS SHIFT+8 (right): move one visible page down, clamped to last file.
        ld      a,(p126_catalog_total)
        or      a
        ret     z
        dec     a
        ld      b,a
        ld      a,(p126_catalog_selected)
        add     a,P126_CATALOG_VISIBLE_ROWS
        jr      c,.catalog_page_down_clamp
        cp      b
        jr      c,.catalog_page_down_store
        jr      z,.catalog_page_down_store
.catalog_page_down_clamp:
        ld      a,b
.catalog_page_down_store:
        ld      (p126_catalog_selected),a
        ; Place the selected entry on the last visible row where possible.
        cp      P126_CATALOG_VISIBLE_ROWS-1
        jr      nc,.catalog_page_down_scroll
        xor     a
        jr      .catalog_page_down_scroll_store
.catalog_page_down_scroll:
        ; For a complete page jump, put the new selection at the top.
        ; Only the final partial page is bottom-aligned to keep the last
        ; directory entries visible without drawing beyond the catalogue.
        ld      a,(p126_catalog_total)
        sub     P126_CATALOG_VISIBLE_ROWS
        ld      b,a
        ld      a,(p126_catalog_selected)
        cp      b
        jr      c,.catalog_page_down_use_selected
        ld      a,b
        jr      .catalog_page_down_scroll_store
.catalog_page_down_use_selected:
        ld      a,(p126_catalog_selected)
.catalog_page_down_scroll_store:
        ld      (p126_catalog_scroll),a
        call    p126_catalog_draw
        ret

.catalog_confirm:
        ld      hl,p126_log_enter_confirmed
        call    p126_catalog_log
        call    p126_bios_load_selected
        jr      c,.catalog_bios_load_failed
        xor     a
        ld      (p126_catalog_enabled),a
        ld      a,1
        ld      (p126_catalog_bios_loaded),a
        ; The catalogue is a one-shot boot UI. Clear it, then request the
        ; bounded BIOS stop record over the established reverse-DMA path.
        ; The resident executes the pending BIOS slice before answering E1.
        call    BIOS_DebugConsole_Clear
        call    p126_ipc_dma_receive_debug_frame
        ld      hl,p126_log_bios_loaded
        call    p126_catalog_log
        ret

.catalog_bios_load_failed:
        ld      hl,p126_log_bios_failed
        call    p126_catalog_log
        call    p126_catalog_draw
        ret

.catalog_move_up:
        ld      a, (p126_catalog_selected)
        or      a
        ret     z
        dec     a
        ld      (p126_catalog_selected), a

        ld      b, a
        ld      a, (p126_catalog_scroll)
        cp      b
        jr      c, .catalog_redraw
        jr      z, .catalog_redraw
        dec     a
        ld      (p126_catalog_scroll), a
        jr      .catalog_redraw

.catalog_move_down:
        ld      a, (p126_catalog_selected)
        inc     a
        ld      b, a
        ld      a, (p126_catalog_total)
        cp      b
        ret     z
        ret     c

        ld      a, b
        ld      (p126_catalog_selected), a

        ; The last visible index is scroll + 8. This cannot overflow because
        ; the catalogue contains at most 128 entries (indices 0..127).
        ld      a, (p126_catalog_scroll)
        add     a, P126_CATALOG_VISIBLE_ROWS-1
        ld      b, a
        ld      a, (p126_catalog_selected)
        cp      b
        jr      c, .catalog_redraw
        jr      z, .catalog_redraw
        ld      a, (p126_catalog_scroll)
        inc     a
        ld      (p126_catalog_scroll), a

.catalog_redraw:
        call    p126_catalog_draw
        ret

; -------------------------------------------------------------------------
; Spectrum/ATM keyboard matrix cursor mapping:
; CAPS SHIFT+7 = up, CAPS SHIFT+6 = down.
; CAPS SHIFT+5 and CAPS SHIFT+8 are also sampled for left/right, although
; this vertical file list only consumes up/down.
; -------------------------------------------------------------------------
p126_catalog_scan_keys:
        push    bc
        push    de
        push    hl

        xor     a
        ld      (p126_catalog_scan_result), a

        ; ENTER is bit 0 of row #BFFE and is accepted without CAPS SHIFT.
        ld      bc,#BFFE
        in      a,(c)
        bit     0,a
        jr      nz,.catalog_check_caps
        ld      a,16
        ld      (p126_catalog_scan_result),a

.catalog_check_caps:
        ; CAPS SHIFT is bit 0 in the #FE row for cursor combinations.
        ld      bc, #FEFE
        in      a, (c)
        bit     0, a
        jr      nz, .catalog_keys_done

        ; Row #EF: key 7 (bit 3) = up, key 6 (bit 4) = down.
        ld      bc, #EFFE
        in      a, (c)
        bit     3, a
        jr      nz, .catalog_check_down
        ld      a, (p126_catalog_scan_result)
        or      1
        ld      (p126_catalog_scan_result), a

.catalog_check_down:
        ld      bc, #EFFE
        in      a, (c)
        bit     4, a
        jr      nz, .catalog_check_other_arrows
        ld      a, (p126_catalog_scan_result)
        or      2
        ld      (p126_catalog_scan_result), a

.catalog_check_other_arrows:
        ; CAPS SHIFT+5 = page up (row #F7FE, key bit 4).
        ld      bc,#F7FE
        in      a,(c)
        bit     4,a
        jr      nz,.catalog_check_page_down
        ld      a,(p126_catalog_scan_result)
        or      4
        ld      (p126_catalog_scan_result),a

.catalog_check_page_down:
        ; CAPS SHIFT+8 = page down (row #EFFE, key bit 2).
        ld      bc,#EFFE
        in      a,(c)
        bit     2,a
        jr      nz,.catalog_keys_done
        ld      a,(p126_catalog_scan_result)
        or      8
        ld      (p126_catalog_scan_result),a

.catalog_keys_done:
        ld      a, (p126_catalog_scan_result)
        pop     hl
        pop     de
        pop     bc
        ret

p126_catalog_wait_release:
        call    p126_catalog_scan_keys
        or      a
        jr      nz, p126_catalog_wait_release
        ret

; -------------------------------------------------------------------------
; TR-DOS directory read.
; Executed before p126_atm_video_init, using Project125's legacy mapping.
; C=5 reads exactly one 256-byte sector (B=1); eight calls stage the
; 2 KiB directory at #C800..#CFFF.
; -------------------------------------------------------------------------
p126_catalog_read_disk:
        ld      hl, p126_log_disk_enter
        call    p126_catalog_log
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy

        exx
        push    bc
        push    de
        push    hl
        exx
        ex      af, af'
        push    af
        ex      af, af'

        ld      (p126_catalog_saved_sp), sp
        ld      sp, #BFFF

        xor     a
        ld      (p126_catalog_io_result), a
        ld      (p126_catalog_sector_index), a
        ld      a, #C8
        ld      (p126_catalog_buffer_ptr+1), a
        xor     a
        ld      (p126_catalog_buffer_ptr), a

.catalog_read_sector:
        ld      a, (p126_catalog_sector_index)
        cp      8
        jr      nc, .catalog_sectors_complete

        ; #3D13 sector-read convention uses zero-based E. The ROM
        ; driver advances to physical sector E+1 internally. Therefore
        ; the eight directory sectors are requested as E=0..7.
        ld      a, (p126_catalog_sector_index)
        ld      e, a
        ld      d, 0
        ld      hl, (p126_catalog_buffer_ptr)
        ld      b, 1
        ld      c, 5
        xor     a
        ld      (#5D0F), a
        ld      (#5D10), a
        call    #3D13

        ld      a, (#5D0F)
        ld      b, a
        ld      a, (#5D10)
        or      b
        jr      nz, .catalog_sector_error

        ld      hl, (p126_catalog_buffer_ptr)
        ld      de, #0100
        add     hl, de
        ld      (p126_catalog_buffer_ptr), hl
        ld      a, (p126_catalog_sector_index)
        inc     a
        ld      (p126_catalog_sector_index), a
        jr      .catalog_read_sector

.catalog_sectors_complete:
        xor     a
        ld      (p126_catalog_io_result), a
        jr      .catalog_restore_stack

.catalog_sector_error:
        ld      a, 1
        ld      (p126_catalog_io_result), a

.catalog_restore_stack:
        ld      sp, (p126_catalog_saved_sp)

        ex      af, af'
        pop     af
        ex      af, af'
        exx
        pop     hl
        pop     de
        pop     bc
        exx

        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af

        ld      a, (p126_catalog_io_result)
        or      a
        jr      z, .catalog_read_return_ok
        ld      hl, p126_log_io_error
        call    p126_catalog_log
        scf
        ret
.catalog_read_return_ok:
        ld      hl, p126_log_io_success
        call    p126_catalog_log
        or      a
        ret

; -------------------------------------------------------------------------
; A directory descriptor is valid when its first byte is neither 00h nor
; 01h and its TR-DOS type byte is B, C, D or #.
; IN: HL=16-byte descriptor. OUT: carry clear if valid, set if unused.
; HL and BC are preserved.
; -------------------------------------------------------------------------
p126_catalog_entry_valid:
        ld      a, (hl)
        or      a
        jr      z, .catalog_entry_invalid
        cp      1
        jr      z, .catalog_entry_invalid

        push    hl
        ld      de, 8
        add     hl, de
        ld      a, (hl)
        pop     hl

        cp      'B'
        jr      z, .catalog_entry_valid
        cp      'C'
        jr      z, .catalog_entry_valid
        cp      'D'
        jr      z, .catalog_entry_valid
        cp      '#'
        jr      z, .catalog_entry_valid

.catalog_entry_invalid:
        scf
        ret

.catalog_entry_valid:
        or      a
        ret

; Count valid entries in the 128-entry TR-DOS directory.
p126_catalog_count_files:
        xor     a
        ld      (p126_catalog_total), a
        ld      hl, P126_CATALOG_BUFFER
        ld      b, P126_CATALOG_ENTRY_COUNT

.catalog_count_loop:
        call    p126_catalog_entry_valid
        jr      c, .catalog_count_next
        ld      a, (p126_catalog_total)
        inc     a
        ld      (p126_catalog_total), a

.catalog_count_next:
        ld      de, P126_CATALOG_ENTRY_SIZE
        add     hl, de
        djnz    .catalog_count_loop
        ret

; IN: A=zero-based index among valid files.
; OUT: HL=descriptor, carry clear; carry set when index is out of range.
p126_catalog_find_index:
        ld      (p126_catalog_target), a
        ld      hl, P126_CATALOG_BUFFER
        ld      b, P126_CATALOG_ENTRY_COUNT
        ld      c, 0

.catalog_find_loop:
        call    p126_catalog_entry_valid
        jr      c, .catalog_find_next

        ld      a, (p126_catalog_target)
        cp      c
        jr      z, .catalog_find_found
        inc     c

.catalog_find_next:
        ld      de, P126_CATALOG_ENTRY_SIZE
        add     hl, de
        djnz    .catalog_find_loop
        scf
        ret

.catalog_find_found:
        or      a
        ret

; Draw nine visible entries. A leading '>' marks the current selection.
p126_catalog_draw:
        push    af
        push    bc
        push    de
        push    hl

        ld      a, (p126_catalog_total)
        or      a
        jr      nz, .catalog_draw_rows
        ld      hl, p126_catalog_empty_text
        ld      a, P126_CATALOG_FIRST_ROW
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt
        jr      .catalog_draw_done

.catalog_draw_rows:
        xor     a
        ld      (p126_catalog_row), a

.catalog_draw_loop:
        ; Logical file index = scroll offset + visible row.
        ld      a, (p126_catalog_scroll)
        ld      b, a
        ld      a, (p126_catalog_row)
        add     a, b
        ld      (p126_catalog_target), a

        ; Start with a blank fixed-width line so old text is erased on scroll.
        ld      hl, p126_catalog_line
        ld      b, 12
        ld      a, ' '
.catalog_clear_line:
        ld      (hl), a
        inc     hl
        djnz    .catalog_clear_line
        xor     a
        ld      (hl), a
        ld      a, '.'
        ld      (p126_catalog_line+9), a

        ld      a, (p126_catalog_target)
        ld      b, a
        ld      a, (p126_catalog_total)
        cp      b
        jr      c, .catalog_print_line
        jr      z, .catalog_print_line

        ld      a, (p126_catalog_target)
        call    p126_catalog_find_index
        jr      c, .catalog_print_line

        ; Selection marker.
        ld      a, (p126_catalog_target)
        ld      b, a
        ld      a, (p126_catalog_selected)
        cp      b
        ld      a, ' '
        jr      nz, .catalog_store_marker
        ld      a, '>'
.catalog_store_marker:
        ld      (p126_catalog_line), a

        ; Copy the eight-character TR-DOS filename and its one-byte type.
        ld      de, p126_catalog_line+1
        ld      b, 8
.catalog_copy_name:
        ld      a, (hl)
        ld      (de), a
        inc     hl
        inc     de
        djnz    .catalog_copy_name
        ld      a, (hl)
        ld      (p126_catalog_line+10), a

.catalog_print_line:
        ld      hl, p126_catalog_line
        ld      a, (p126_catalog_row)
        add     a, P126_CATALOG_FIRST_ROW
        ld      c, 1
        call    BIOS_DebugConsole_PrintAt

        ld      a, (p126_catalog_row)
        inc     a
        ld      (p126_catalog_row), a
        cp      P126_CATALOG_VISIBLE_ROWS
        jp      nz, .catalog_draw_loop

.catalog_draw_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

p126_catalog_log:
        push    af
        push    bc
        push    de
        push    hl
        call    p126_host_debug_string
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

p126_log_catalog_enter:       db "[CAT] initialize ENTER",13,10,0
p126_log_read_begin:           db "[CAT] read_disk BEGIN",13,10,0
p126_log_disk_enter:           db "[CAT] TRDOS routine ENTER",13,10,0
p126_log_drive_selected:       db "[CAT] drive-select RETURN",13,10,0
p126_log_sector_read_call:     db "[CAT] directory READ CALL C=5 B=1",13,10,0
p126_log_sector_read_return:   db "[CAT] directory SECTOR RETURN",13,10,0
p126_log_vg93_idle:            db "[CAT] VG93 IDLE",13,10,0
p126_log_io_error:             db "[CAT] IO RESULT=ERROR",13,10,0
p126_log_io_success:           db "[CAT] IO RESULT=OK",13,10,0
p126_log_read_ok:              db "[CAT] read_disk OK",13,10,0
p126_log_read_failed:          db "[CAT] read_disk CARRY=1",13,10,0
p126_log_count_done:           db "[CAT] FILE COUNT=",0
p126_log_draw_begin:           db "[CAT] DRAW BEGIN",13,10,0
p126_log_draw_done:            db "[CAT] DRAW DONE",13,10,0
p126_log_key_seen:             db "[CAT] CURSOR KEY DETECTED",13,10,0
p126_log_enter_confirmed:      db "[CAT] ENTER CONFIRMED",13,10,0
p126_log_bios_loaded:          db "[CAT] IMAGE SEQUENCE SENT; CHECK NGS INSTALL RESULT",13,10,0
p126_log_bios_failed:          db "[CAT] SYSBIOS IMAGE TRANSFER FAILED",13,10,0

p126_catalog_enabled:  db 0
p126_catalog_selected: db 0
p126_catalog_scroll:   db 0
p126_catalog_total:    db 0
p126_catalog_target:   db 0
p126_catalog_row:      db 0
p126_catalog_key:      db 0
p126_catalog_scan_result: db 0
p126_catalog_bios_loaded: db 0
p126_catalog_io_result: db 0
p126_catalog_preloaded: db 0
p126_catalog_sector_index: db 0
p126_catalog_buffer_ptr: dw P126_CATALOG_BUFFER
p126_catalog_saved_sp: dw 0
p126_catalog_line:     db "            ", 0
p126_catalog_empty_text: db "NO TR-DOS FILES", 0
p126_catalog_error_text: db "TR-DOS DIRECTORY READ ERROR", 0
