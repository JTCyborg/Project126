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

; Called after the ATM screen and DS12887 initialization.
p126_catalog_initialize::
        xor     a
        ld      (p126_catalog_enabled), a
        ld      (p126_catalog_selected), a
        ld      (p126_catalog_scroll), a

        call    p126_catalog_read_disk
        jr      c, .catalog_read_failed

        call    p126_catalog_count_files
        ld      a, 1
        ld      (p126_catalog_enabled), a
        call    p126_catalog_draw
        ret

.catalog_read_failed:
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
        call    p126_catalog_wait_release

        ld      a, (p126_catalog_key)
        bit     0, a
        jr      nz, .catalog_move_up
        bit     1, a
        jr      nz, .catalog_move_down
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

        ; CAPS SHIFT is bit 0 in the #FE row.
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
        ; Read the remaining cursor combinations to keep the matrix scan
        ; compatible with the Project125 ATM/Spectrum keyboard convention.
        ld      bc, #F7FE
        in      a, (c)
        bit     4, a
        jr      nz, .catalog_check_right
        ld      a, (p126_catalog_scan_result)
        or      4
        ld      (p126_catalog_scan_result), a

.catalog_check_right:
        ld      bc, #EFFE
        in      a, (c)
        bit     2, a
        jr      nz, .catalog_keys_done
        ld      a, (p126_catalog_scan_result)
        or      8
        ld      (p126_catalog_scan_result), a

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
; The ROM gateway is the same #3D13 API used by Project125:
;   C=1, B=0, A=drive number — select drive A.
;   C=5, B=8, D=0, E=0, HL=#C800 — read the 8 catalogue sectors.
; -------------------------------------------------------------------------
p126_catalog_read_disk:
        push    af
        push    bc
        push    de
        push    hl
        push    ix
        push    iy

        ; Preserve the alternate Z80 register banks across the TR-DOS ROM.
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
        ld      iy, #5C3A

        ; Select drive A and synchronize the TR-DOS system drive variables.
        xor     a
        ld      (#5D08), a
        ld      (#5D09), a
        ld      (#5D19), a
        ld      (#5CF6), a
        ld      (#5CF8), a
        ld      (#5CF9), a

        ; The Project125 TR-DOS driver configures the 80-track, double-sided
        ; geometry before issuing directory-sector reads.
        ld      a, #83
        ld      (#5CC8), a
        ld      a, #FF
        ld      (#5CD8), a
        xor     a
        ld      (#5CD6), a
        ld      (#5D0F), a
        ld      (#5D10), a

        ld      bc, #0001
        xor     a
        call    #3D13

        ld      a, (#5D0F)
        ld      b, a
        ld      a, (#5D10)
        or      b
        jp      nz, .catalog_io_error

        ; Read the complete 128-entry directory (8 x 256-byte sectors).
        ld      hl, P126_CATALOG_BUFFER
        ld      de, #0000
        ld      bc, #0805
        xor     a
        ld      (#5D0F), a
        ld      (#5D10), a
        ld      (#5D11), a
        call    #3D13

        ; Wait for the TR-DOS/VG93 command flag to return to idle.
        ld      bc, #FFFF
.catalog_wait_vg93:
        ld      a, (#5D11)
        or      a
        jr      z, .catalog_vg93_ready
        dec     bc
        ld      a, b
        or      c
        jr      nz, .catalog_wait_vg93
        jp      .catalog_io_error

.catalog_vg93_ready:
        ld      a, (#5D0F)
        ld      b, a
        ld      a, (#5D10)
        or      b
        jp      nz, .catalog_io_error

        xor     a
        ld      (p126_catalog_io_result), a
        jr      .catalog_restore_stack

.catalog_io_error:
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
        ret     z
        scf
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

p126_catalog_enabled:  db 0
p126_catalog_selected: db 0
p126_catalog_scroll:   db 0
p126_catalog_total:    db 0
p126_catalog_target:   db 0
p126_catalog_row:      db 0
p126_catalog_key:      db 0
p126_catalog_scan_result: db 0
p126_catalog_io_result: db 0
p126_catalog_saved_sp: dw 0
p126_catalog_line:     db "            ", 0
p126_catalog_empty_text: db "NO TR-DOS FILES", 0
p126_catalog_error_text: db "TR-DOS DIRECTORY READ ERROR", 0
