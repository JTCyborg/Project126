; =========================================================================
; PROJECT126 — IBM VGA adapter overlay
; Behavior source: Project126/PCem/vid_vga.c and vid_svga.c.
; Dynamic module ID05 / physical page08, logical ORG 8000h.
; VRAM backing: physical pages30h..3Fh (256 KiB), accessed later via WIN3.
;
; Stage 1 implements the PCem VGA/SVGA register-file and port semantics.
; Aperture latches/planes and scanout are deliberately separate stages.
; =========================================================================
X86_VGA_MODULE_ID       EQU 5
X86_VGA_PHYS_PAGE       EQU #08
X86_VGA_VRAM_BYTES      EQU #40000
X86_VGA_VRAM_PAGE_FIRST EQU #30
X86_VGA_VRAM_PAGE_COUNT EQU #10

x86_vga_overlay_probe:
        ld      hl,#A55A
        ld      a,#56
        ret

; Reset the register state to the standard VGA initialization used by
; PCem vga_init(): 256 KiB VRAM, 8bpp SVGA core, colour CRTC selected.
x86_vga_reset_impl:
        xor     a
        ld      (x86_vga_miscout),a
        ld      (x86_vga_crtcreg),a
        ld      (x86_vga_seqaddr),a
        ld      (x86_vga_gdcaddr),a
        ld      (x86_vga_attraddr),a
        ld      (x86_vga_attrff),a
        ld      (x86_vga_attr_palette_enable),a
        ld      (x86_vga_dac_status),a
        ld      (x86_vga_dac_read),a
        ld      (x86_vga_dac_write),a
        ld      (x86_vga_dac_pos),a
        ld      (x86_vga_cgastat),a
        ld      (x86_vga_crtc),a
        ld      hl,x86_vga_crtc
        ld      de,x86_vga_crtc+1
        ld      bc,127
        ldir
        ld      hl,x86_vga_gdc
        ld      de,x86_vga_gdc+1
        ld      bc,63
        ld      (hl),a
        ldir
        ld      hl,x86_vga_attr
        ld      de,x86_vga_attr+1
        ld      bc,31
        ld      (hl),a
        ldir
        ld      hl,x86_vga_seq
        ld      de,x86_vga_seq+1
        ld      bc,63
        ld      (hl),a
        ldir
        ld      hl,x86_vga_dac
        ld      de,x86_vga_dac+1
        ld      bc,767
        ld      (hl),a
        ldir
        ld      a,#FF
        ld      (x86_vga_dac_mask),a
        xor     a
        ld      (x86_vga_writemask),a
        ld      a,8
        ld      (x86_vga_bpp),a
        ld      a,1
        ld      (x86_vga_miscout),a
        xor     a
        ld      (x86_vga_chain4),a
        ld      (x86_vga_chain2_write),a
        ld      (x86_vga_chain2_read),a
        ld      (x86_vga_readmode),a
        ld      (x86_vga_writemode),a
        ld      (x86_vga_readplane),a
        ld      (x86_vga_colourcompare),a
        ld      (x86_vga_colournocare),a
        ld      (x86_vga_plane_mask),a
        ld      (x86_vga_dac_r),a
        ld      (x86_vga_dac_g),a
        ld      (x86_vga_write_value),a
        ret

; IN HL=guest I/O port. OUT A=read value, carry clear if VGA decoded it.
; The caller dispatches unhandled ports to the remaining software devices.
x86_vga_io_read8_impl:
        ld      (x86_vga_port),hl
        call    x86_vga_normalize_port
        ret     c
        ld      hl,(x86_vga_port)
        ld      a,l
        cp      #C0
        jr      z,.read_attr_address
        cp      #C1
        jr      z,.read_attr_data
        cp      #C2
        jr      z,.read_input_status0
        cp      #C4
        jr      z,.read_seq_address
        cp      #C5
        jr      z,.read_seq_data
        cp      #C6
        jr      z,.read_dac_mask
        cp      #C7
        jr      z,.read_dac_state
        cp      #C8
        jr      z,.read_dac_write_index
        cp      #C9
        jr      z,.read_dac_data
        cp      #CC
        jr      z,.read_misc_output
        cp      #CE
        jr      z,.read_gdc_address
        cp      #CF
        jr      z,.read_gdc_data
        cp      #D4
        jr      z,.read_crtc_address
        cp      #D5
        jr      z,.read_crtc_data
        cp      #DA
        jr      z,.read_input_status1
        ld      a,#FF
        or      a
        ret
.read_attr_address:
        ld      a,(x86_vga_attraddr)
        ld      b,a
        ld      a,(x86_vga_attr_palette_enable)
        or      b
        or      a
        ret
.read_attr_data:
        ld      a,(x86_vga_attraddr)
        and     #1F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_attr
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.read_input_status0:
        ; PCem returns the feature/status-0 bit according to DAC palette 0.
        ; Palette RAM is zero after reset, therefore bit4 is set.
        ld      a,#10
        or      a
        ret
.read_seq_address:
        ld      a,(x86_vga_seqaddr)
        or      a
        ret
.read_seq_data:
        ld      a,(x86_vga_seqaddr)
        and     #0F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_seq
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.read_dac_mask:
        ld      a,(x86_vga_dac_mask)
        or      a
        ret
.read_dac_state:
        ld      a,(x86_vga_dac_status)
        or      a
        ret
.read_dac_write_index:
        ld      a,(x86_vga_dac_write)
        or      a
        ret
.read_dac_data:
        call    x86_vga_dac_read_component
        or      a
        ret
.read_misc_output:
        ld      a,(x86_vga_miscout)
        or      a
        ret
.read_gdc_address:
        ld      a,(x86_vga_gdcaddr)
        or      a
        ret
.read_gdc_data:
        ld      a,(x86_vga_gdcaddr)
        and     #0F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_gdc
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.read_crtc_address:
        ld      a,(x86_vga_crtcreg)
        or      a
        ret
.read_crtc_data:
        ld      a,(x86_vga_crtcreg)
        bit     5,a
        jr      nz,.read_crtc_open_bus
        and     #7F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_crtc
        add     hl,de
        ld      a,(hl)
        or      a
        ret
.read_crtc_open_bus:
        ld      a,#FF
        or      a
        ret
.read_input_status1:
        xor     a
        ld      (x86_vga_attrff),a
        ld      a,(x86_vga_cgastat)
        bit     0,a
        jr      nz,.status_clear_blink
        xor     #30
        ld      (x86_vga_cgastat),a
        or      a
        ret
.status_clear_blink:
        and     #CF
        ld      (x86_vga_cgastat),a
        or      a
        ret

; IN HL=guest I/O port, A=value. OUT carry clear if handled.
x86_vga_io_write8_impl:
        ld      (x86_vga_write_value),a
        ld      (x86_vga_port),hl
        call    x86_vga_normalize_port
        ret     c
        ld      hl,(x86_vga_port)
        ld      a,l
        cp      #C0
        jp      z,.write_attr
        cp      #C2
        jp      z,.write_misc_output
        cp      #C4
        jp      z,.write_seq_address
        cp      #C5
        jp      z,.write_seq_data
        cp      #C6
        jp      z,.write_dac_mask
        cp      #C7
        jp      z,.write_dac_read_index
        cp      #C8
        jp      z,.write_dac_write_index
        cp      #C9
        jp      z,.write_dac_data
        cp      #CE
        jp      z,.write_gdc_address
        cp      #CF
        jp      z,.write_gdc_data
        cp      #D4
        jp      z,.write_crtc_address
        cp      #D5
        jp      z,.write_crtc_data
        or      a
        ret

.write_attr:
        ld      a,(x86_vga_attrff)
        or      a
        jp      nz,.write_attr_data
        ld      a,(x86_vga_write_value)
        and     #1F
        ld      (x86_vga_attraddr),a
        ld      a,(x86_vga_write_value)
        and     #20
        ld      (x86_vga_attr_palette_enable),a
        ld      a,1
        ld      (x86_vga_attrff),a
        or      a
        ret
.write_attr_data:
        ld      a,(x86_vga_attraddr)
        and     #1F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_attr
        add     hl,de
        ld      a,(x86_vga_write_value)
        ld      (hl),a
        xor     a
        ld      (x86_vga_attrff),a
        ld      a,(x86_vga_attraddr)
        cp      #12
        jr      nz,.write_attr_palette
        ld      a,(x86_vga_write_value)
        and     #0F
        ld      (x86_vga_plane_mask),a
.write_attr_palette:
        ld      a,(x86_vga_attraddr)
        cp      #10
        jr      z,.write_attr_rebuild_palette
        cp      #14
        jr      z,.write_attr_rebuild_palette
        cp      #10
        jr      c,.write_attr_rebuild_palette
        or      a
        ret
.write_attr_rebuild_palette:
        call    x86_vga_rebuild_attr_palette
        or      a
        ret

.write_misc_output:
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_miscout),a
        or      a
        ret
.write_seq_address:
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_seqaddr),a
        or      a
        ret
.write_seq_data:
        ld      a,(x86_vga_seqaddr)
        cp      #10
        jr      nc,.write_seq_ignored
        and     #0F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_seq
        add     hl,de
        ld      a,(x86_vga_write_value)
        ld      (hl),a
        ld      a,(x86_vga_seqaddr)
        and     #0F
        cp      2
        jr      nz,.write_seq_not_mapmask
        ld      a,(x86_vga_write_value)
        and     #0F
        ld      (x86_vga_writemask),a
        jr      .write_seq_ignored
.write_seq_not_mapmask:
        cp      4
        jr      nz,.write_seq_ignored
        ld      a,(x86_vga_write_value)
        bit     3,a
        jr      z,.write_seq_no_chain4
        ld      a,1
        jr      .write_seq_chain4
.write_seq_no_chain4:
        xor     a
.write_seq_chain4:
        ld      (x86_vga_chain4),a
        ld      a,(x86_vga_write_value)
        bit     2,a
        jr      z,.write_seq_chain2_on
        xor     a
        jr      .write_seq_chain2_store
.write_seq_chain2_on:
        ld      a,1
.write_seq_chain2_store:
        ld      (x86_vga_chain2_write),a
.write_seq_ignored:
        or      a
        ret
.write_dac_mask:
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_dac_mask),a
        or      a
        ret
.write_dac_read_index:
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_dac_read),a
        xor     a
        ld      (x86_vga_dac_pos),a
        or      a
        ret
.write_dac_write_index:
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_dac_write),a
        dec     a
        ld      (x86_vga_dac_read),a
        xor     a
        ld      (x86_vga_dac_pos),a
        or      a
        ret
.write_dac_data:
        call    x86_vga_dac_write_component
        or      a
        ret
.write_gdc_address:
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_gdcaddr),a
        or      a
        ret
.write_gdc_data:
        ld      a,(x86_vga_gdcaddr)
        and     #0F
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_gdc
        add     hl,de
        ld      a,(hl)
        ld      (x86_vga_old_register),a
        ld      a,(x86_vga_write_value)
        ld      (hl),a
        ld      a,(x86_vga_gdcaddr)
        and     #0F
        cp      2
        jr      nz,.write_gdc_not_compare
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_colourcompare),a
        jr      .write_gdc_done
.write_gdc_not_compare:
        cp      4
        jr      nz,.write_gdc_not_readplane
        ld      a,(x86_vga_write_value)
        and     3
        ld      (x86_vga_readplane),a
        jr      .write_gdc_done
.write_gdc_not_readplane:
        cp      5
        jr      nz,.write_gdc_not_mode
        ld      a,(x86_vga_write_value)
        and     3
        ld      (x86_vga_writemode),a
        ld      a,(x86_vga_write_value)
        and     8
        ld      (x86_vga_readmode),a
        ld      a,(x86_vga_write_value)
        and     #10
        ld      (x86_vga_chain2_read),a
        jr      .write_gdc_done
.write_gdc_not_mode:
        cp      7
        jr      nz,.write_gdc_done
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_colournocare),a
.write_gdc_done:
        or      a
        ret
.write_crtc_address:
        ld      a,(x86_vga_write_value)
        and     #3F
        ld      (x86_vga_crtcreg),a
        or      a
        ret
.write_crtc_data:
        ld      a,(x86_vga_crtcreg)
        bit     5,a
        jr      nz,.write_crtc_ignored
        and     #7F
        ld      (x86_vga_index_temp),a
        cp      7
        jr      z,.write_crtc_overflow
        cp      7
        jr      nc,.write_crtc_store
        ld      a,(x86_vga_crtc+17)
        bit     7,a
        jr      nz,.write_crtc_ignored
        jr      .write_crtc_store
.write_crtc_overflow:
        ld      a,(x86_vga_crtc+17)
        bit     7,a
        jr      z,.write_crtc_store
        ld      a,(x86_vga_crtc+7)
        and     #EF
        ld      b,a
        ld      a,(x86_vga_write_value)
        and     #10
        or      b
        ld      (x86_vga_crtc+7),a
        or      a
        ret
.write_crtc_store:
        ld      a,(x86_vga_index_temp)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_crtc
        add     hl,de
        ld      a,(x86_vga_write_value)
        ld      (hl),a
.write_crtc_ignored:
        or      a
        ret

; VGA CRTC port aliasing from PCem vga_in/vga_out. With MiscOut bit0=0,
; 3B0..3BF aliases to 3D0..3DF; the inactive 3D0 bank is not decoded.
x86_vga_normalize_port:
        ld      a,h
        cp      3
        jr      nz,.port_bad
        ld      a,l
        cp      #C0
        jr      c,.port_mono_alias
        cp      #D0
        jr      c,.port_good
        cp      #E0
        jr      nc,.port_bad
        ld      a,(x86_vga_miscout)
        bit     0,a
        jr      z,.port_bad
        jr      .port_good
.port_mono_alias:
        ld      a,l
        cp      #B0
        jr      c,.port_bad
        ld      a,(x86_vga_miscout)
        bit     0,a
        jr      nz,.port_bad
        ld      a,l
        xor     #60
        ld      l,a
        ld      (x86_vga_port),hl
.port_good:
        or      a
        ret
.port_bad:
        scf
        ret

; Attribute palette derivation mirrors svga_out(): attr[0..15], mode
; control register 10h and colour-select register 14h feed the EGA palette.
x86_vga_rebuild_attr_palette:
        ld      a,(x86_vga_attr+16)
        bit     7,a
        jr      z,.attr_palette_6bit
        ld      a,(x86_vga_attr+20)
        and     #0F
        rlca
        rlca
        rlca
        rlca
        ld      (x86_vga_attr_palette_hi),a
        ld      b,16
        ld      c,0
.attr_palette_16bit_loop:
        ld      a,c
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_attr
        add     hl,de
        ld      a,(hl)
        and     #0F
        ld      (x86_vga_palette_temp),a
        ld      a,(x86_vga_attr_palette_hi)
        ld      e,a
        ld      a,(x86_vga_palette_temp)
        or      e
        ld      (x86_vga_palette_temp),a
        ld      a,c
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_egapal
        add     hl,de
        ld      a,(x86_vga_palette_temp)
        ld      (hl),a
        inc     c
        djnz    .attr_palette_16bit_loop
        ret
.attr_palette_6bit:
        ld      a,(x86_vga_attr+20)
        and     #0C
        rlca
        rlca
        rlca
        rlca
        ld      (x86_vga_attr_palette_hi),a
        ld      b,16
        ld      c,0
.attr_palette_6bit_loop:
        ld      a,c
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_attr
        add     hl,de
        ld      a,(hl)
        and     #3F
        ld      (x86_vga_palette_temp),a
        ld      a,(x86_vga_attr_palette_hi)
        ld      e,a
        ld      a,(x86_vga_palette_temp)
        or      e
        ld      (x86_vga_palette_temp),a
        ld      a,c
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_egapal
        add     hl,de
        ld      a,(x86_vga_palette_temp)
        ld      (hl),a
        inc     c
        djnz    .attr_palette_6bit_loop
        ret

; DAC data pointer = palette index*3 + component.
x86_vga_dac_read_component:
        ld      a,(x86_vga_dac_read)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_dac
        add     hl,de
        add     hl,de
        add     hl,de
        ld      a,(x86_vga_dac_pos)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(hl)
        and     #3F
        ld      b,a
        ld      a,(x86_vga_dac_pos)
        inc     a
        cp      3
        jr      c,.dac_read_next
        xor     a
        ld      (x86_vga_dac_pos),a
        ld      hl,x86_vga_dac_read
        inc     (hl)
        jr      .dac_read_return
.dac_read_next:
        ld      (x86_vga_dac_pos),a
.dac_read_return:
        ld      a,3
        ld      (x86_vga_dac_status),a
        ld      a,b
        ret

x86_vga_dac_write_component:
        ld      a,(x86_vga_dac_pos)
        cp      0
        jr      nz,.dac_write_green
        ld      a,(x86_vga_write_value)
        and     #3F
        ld      (x86_vga_dac_r),a
        ld      a,1
        ld      (x86_vga_dac_pos),a
        ret
.dac_write_green:
        cp      1
        jr      nz,.dac_write_blue
        ld      a,(x86_vga_write_value)
        and     #3F
        ld      (x86_vga_dac_g),a
        ld      a,2
        ld      (x86_vga_dac_pos),a
        ret
.dac_write_blue:
        ld      a,(x86_vga_dac_write)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_dac
        add     hl,de
        add     hl,de
        add     hl,de
        ld      a,(x86_vga_dac_r)
        ld      (hl),a
        inc     hl
        ld      a,(x86_vga_dac_g)
        ld      (hl),a
        inc     hl
        ld      a,(x86_vga_write_value)
        and     #3F
        ld      (hl),a
        xor     a
        ld      (x86_vga_dac_pos),a
        ld      hl,x86_vga_dac_write
        inc     (hl)
        ret

; VGA state. The 256 KiB VRAM is physically allocated separately and is not
; duplicated in this module's 16 KiB overlay page.
x86_vga_port:                  dw 0
x86_vga_write_value:           db 0
x86_vga_miscout:               db 1
x86_vga_crtcreg:               db 0
x86_vga_seqaddr:               db 0
x86_vga_gdcaddr:               db 0
x86_vga_attraddr:              db 0
x86_vga_attrff:                db 0
x86_vga_attr_palette_enable:   db 0
x86_vga_dac_mask:              db #FF
x86_vga_dac_status:            db 0
x86_vga_dac_read:              db 0
x86_vga_dac_write:             db 0
x86_vga_dac_pos:               db 0
x86_vga_dac_r:                 db 0
x86_vga_dac_g:                 db 0
x86_vga_bpp:                   db 8
x86_vga_cgastat:               db 0
x86_vga_writemask:             db #0F
x86_vga_chain4:                db 0
x86_vga_chain2_write:          db 0
x86_vga_chain2_read:           db 0
x86_vga_readmode:              db 0
x86_vga_writemode:             db 0
x86_vga_readplane:             db 0
x86_vga_colourcompare:         db 0
x86_vga_colournocare:          db 0
x86_vga_plane_mask:            db 0
x86_vga_old_register:          db 0
x86_vga_index_temp:            db 0
x86_vga_attr_palette_hi:       db 0
x86_vga_palette_temp:          db 0
x86_vga_crtc:                  defs 128,0
x86_vga_gdc:                   defs 64,0
x86_vga_attr:                  defs 32,0
x86_vga_seq:                   defs 64,0
x86_vga_dac:                   defs 768,0
x86_vga_egapal:                defs 16,0

        ASSERT X86_VGA_VRAM_BYTES = #40000
        ASSERT X86_VGA_VRAM_PAGE_COUNT*#4000 = X86_VGA_VRAM_BYTES
