; =========================================================================
; PROJECT126 — VGA text to ATM-native frame converter
; Module ID06, dynamic overlay page09.
; VGA behavior is obtained only through the X86VGA public gate API.
; Initial ATM target: RG6 80x25 text, compact frame layout:
;   bytes 0000..07CF = 2000 character codes
;   bytes 07D0..0F9F = 2000 attribute bytes
; The complete 4000-byte frame is stored in physical pages40h..41h.
; =========================================================================

x86_video_overlay_probe:
        ld      a,#56
        ld      hl,#A55A
        ret

; Convert one complete VGA text screen using the ATM mode descriptor
; received over the VIDEO service. OUT: A=0, HL=frame byte count, CF=0.
x86_video_convert_impl:
        xor     a
        ld      (x86_video_frame_ready),a
        ld      a,(p126_ngs_video_mode_ready)
        or      a
        jp      z,.video_convert_no_mode

        ; Revalidate the resident descriptor at the point of use.
        ld      a,(p126_ngs_video_mode_desc)
        cp      P126_VIDEO_DESC_VERSION
        jp      nz,.video_convert_bad_mode
        ld      a,(p126_ngs_video_mode_desc+1)
        cp      P126_ATM_MODE_RG6_TEXT80X25
        jp      nz,.video_convert_bad_mode
        ld      a,(p126_ngs_video_mode_desc+2)
        cp      P126_VIDEO_TEXT80_WIDTH
        jp      nz,.video_convert_bad_mode
        ld      a,(p126_ngs_video_mode_desc+3)
        cp      P126_VIDEO_TEXT80_HEIGHT
        jp      nz,.video_convert_bad_mode
        ld      a,(p126_ngs_video_mode_desc+4)
        cp      P126_VIDEO_FORMAT_TEXT80X25
        jp      nz,.video_convert_bad_mode
        ld      hl,(p126_ngs_video_mode_desc+6)
        ld      de,P126_VIDEO_TEXT80_FRAME_SIZE
        or      a
        sbc     hl,de
        jp      nz,.video_convert_bad_mode

        ; X86VGA returns the text aperture base, CRTC start and row stride
        ; calculated with the same MA units as PCem's text renderer.
        call    x86_vga_get_text_snapshot
        jp      c,.video_convert_unsupported
        ld      (x86_video_text_base_mid),a
        ld      (x86_video_row_offset),hl
        ld      (x86_video_stride),de

        ld      hl,0
        ld      (x86_video_frame_index),hl
        xor     a
        ld      (x86_video_row),a
.video_convert_row:
        ld      hl,(x86_video_row_offset)
        ld      (x86_video_cell_offset),hl
        xor     a
        ld      (x86_video_col),a
.video_convert_col:
        ld      a,(x86_video_text_base_mid)
        ld      hl,(x86_video_cell_offset)
        call    x86_vga_read_text_cell
        ld      (x86_video_char),a
        ld      (x86_video_attr),d

        ; Character plane followed by attribute plane.
        ld      hl,(x86_video_frame_index)
        ld      a,(x86_video_char)
        call    x86_video_write_frame_byte
        ld      hl,(x86_video_frame_index)
        ld      de,P126_VIDEO_TEXT80_WIDTH*P126_VIDEO_TEXT80_HEIGHT
        add     hl,de
        ld      a,(x86_video_attr)
        call    x86_video_write_frame_byte

        ld      hl,(x86_video_frame_index)
        inc     hl
        ld      (x86_video_frame_index),hl
        ld      hl,(x86_video_cell_offset)
        inc     hl
        inc     hl
        ld      (x86_video_cell_offset),hl
        ld      a,(x86_video_col)
        inc     a
        ld      (x86_video_col),a
        cp      P126_VIDEO_TEXT80_WIDTH
        jp      c,.video_convert_col

        ld      hl,(x86_video_row_offset)
        ld      de,(x86_video_stride)
        add     hl,de
        ld      (x86_video_row_offset),hl
        ld      a,(x86_video_row)
        inc     a
        ld      (x86_video_row),a
        cp      P126_VIDEO_TEXT80_HEIGHT
        jp      c,.video_convert_row

        ld      hl,(x86_video_frame_index)
        ld      de,P126_VIDEO_TEXT80_WIDTH*P126_VIDEO_TEXT80_HEIGHT
        or      a
        sbc     hl,de
        jp      nz,.video_convert_bad_mode
        ld      hl,P126_VIDEO_TEXT80_FRAME_SIZE
        ld      (x86_video_frame_size),hl
        ld      a,1
        ld      (x86_video_frame_ready),a
        ld      hl,P126_VIDEO_TEXT80_FRAME_SIZE
        xor     a
        ret

.video_convert_no_mode:
        ld      a,#F1
        scf
        ret
.video_convert_unsupported:
        ld      a,#F2
        scf
        ret
.video_convert_bad_mode:
        ld      a,#F3
        scf
        ret

; IN: HL=logical frame offset (0..7FFFh), A=byte.
; OUT: writes through WIN3 to physical pages40h..41h.
x86_video_write_frame_byte:
        ld      (x86_video_frame_data),a
        ld      (x86_video_frame_offset),hl
        ld      a,h
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        add     a,#40
        rrca
        out     (P126_NGS_BANK_WINDOW_PORT),a
        ld      hl,(x86_video_frame_offset)
        ld      a,h
        and     #3F
        or      #C0
        ld      h,a
        ld      a,(x86_video_frame_data)
        ld      (hl),a
        ret

x86_video_text_base_mid: db 0
x86_video_row_offset:    dw 0
x86_video_cell_offset:   dw 0
x86_video_stride:        dw 0
x86_video_frame_index:   dw 0
x86_video_frame_offset:  dw 0
x86_video_frame_size:    dw 0
x86_video_frame_data:    db 0
x86_video_frame_ready:   db 0
x86_video_row:           db 0
x86_video_col:           db 0
x86_video_char:          db 0
x86_video_attr:          db 0
