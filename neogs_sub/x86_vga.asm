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
        ld      hl,x86_vga_egapal
        ld      de,x86_vga_egapal+1
        ld      bc,15
        ld      (hl),a
        ldir
        ld      hl,x86_vga_latches
        ld      de,x86_vga_latches+1
        ld      bc,3
        ld      (hl),a
        ldir
        ld      a,63
        ld      (x86_vga_crtc),a
        ld      a,#FF
        ld      (x86_vga_crtc+6),a
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
        jp      z,.read_attr_address
        cp      #C1
        jp      z,.read_attr_data
        cp      #C2
        jp      z,.read_input_status0
        cp      #C4
        jp      z,.read_seq_address
        cp      #C5
        jp      z,.read_seq_data
        cp      #C6
        jp      z,.read_dac_mask
        cp      #C7
        jp      z,.read_dac_state
        cp      #C8
        jp      z,.read_dac_write_index
        cp      #C9
        jp      z,.read_dac_data
        cp      #CC
        jp      z,.read_misc_output
        cp      #CE
        jp      z,.read_gdc_address
        cp      #CF
        jp      z,.read_gdc_data
        cp      #D4
        jp      z,.read_crtc_address
        cp      #D5
        jp      z,.read_crtc_data
        cp      #DA
        jp      z,.read_input_status1
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
        ; PCem reports bit4 when the sum of DAC palette entry zero is dark.
        ld      a,(x86_vga_dac)
        ld      b,a
        ld      a,(x86_vga_dac+1)
        add     a,b
        ld      b,a
        ld      a,(x86_vga_dac+2)
        add     a,b
        cp      #50
        jp      nc,.read_input_status0_bright
        ld      a,#10
        or      a
        ret
.read_input_status0_bright:
        xor     a
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
        jp      nz,.read_crtc_open_bus
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
        ; Match PCem svga_in(3DAh): when display-enable bit0 is clear,
        ; toggle the horizontal/vertical retrace bits (5:4). When bit0 is
        ; set, clear those bits. Do not synthesize an unrelated bit3 timer.
        ld      a,(x86_vga_cgastat)
        bit     0,a
        jp      nz,.status_clear_retrace
        xor     #30
        ld      (x86_vga_cgastat),a
        or      a
        ret
.status_clear_retrace:
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
        jp      nz,.write_attr_palette
        ld      a,(x86_vga_write_value)
        and     #0F
        ld      (x86_vga_plane_mask),a
.write_attr_palette:
        ld      a,(x86_vga_attraddr)
        cp      #10
        jp      z,.write_attr_rebuild_palette
        cp      #14
        jp      z,.write_attr_rebuild_palette
        cp      #10
        jp      c,.write_attr_rebuild_palette
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
        jp      nc,.write_seq_ignored
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
        jp      nz,.write_seq_not_mapmask
        ld      a,(x86_vga_write_value)
        and     #0F
        ld      (x86_vga_writemask),a
        jp      .write_seq_ignored
.write_seq_not_mapmask:
        cp      4
        jp      nz,.write_seq_ignored
        ld      a,(x86_vga_write_value)
        bit     3,a
        jp      z,.write_seq_no_chain4
        ld      a,1
        jp      .write_seq_chain4
.write_seq_no_chain4:
        xor     a
.write_seq_chain4:
        ld      (x86_vga_chain4),a
        ld      a,(x86_vga_write_value)
        bit     2,a
        jp      z,.write_seq_chain2_on
        xor     a
        jp      .write_seq_chain2_store
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
        xor     a
        ld      (x86_vga_dac_status),a
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
        jp      nz,.write_gdc_not_compare
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_colourcompare),a
        jp      .write_gdc_done
.write_gdc_not_compare:
        cp      4
        jp      nz,.write_gdc_not_readplane
        ld      a,(x86_vga_write_value)
        and     3
        ld      (x86_vga_readplane),a
        jp      .write_gdc_done
.write_gdc_not_readplane:
        cp      5
        jp      nz,.write_gdc_not_mode
        ld      a,(x86_vga_write_value)
        and     3
        ld      (x86_vga_writemode),a
        ld      a,(x86_vga_write_value)
        and     8
        ld      (x86_vga_readmode),a
        ld      a,(x86_vga_write_value)
        and     #10
        ld      (x86_vga_chain2_read),a
        jp      .write_gdc_done
.write_gdc_not_mode:
        cp      7
        jp      nz,.write_gdc_done
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
        jp      nz,.write_crtc_ignored
        and     #7F
        ld      (x86_vga_index_temp),a
        cp      7
        jp      z,.write_crtc_overflow
        cp      7
        jp      nc,.write_crtc_store
        ld      a,(x86_vga_crtc+17)
        bit     7,a
        jp      nz,.write_crtc_ignored
        jp      .write_crtc_store
.write_crtc_overflow:
        ld      a,(x86_vga_crtc+17)
        bit     7,a
        jp      z,.write_crtc_store
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
        jp      nz,.port_bad
        ld      a,l
        cp      #C0
        jp      c,.port_mono_alias
        cp      #D0
        jp      c,.port_good
        cp      #E0
        jp      nc,.port_bad
        ld      a,(x86_vga_miscout)
        bit     0,a
        jp      nz,.port_good
        ; The fixed 3D0-3DF handler remains installed; when mono is active
        ; this colour block aliases to the inactive 3B0-3BF range and reads
        ; as open bus / ignores writes, rather than falling through to a
        ; second software device.
        ld      a,l
        xor     #60
        ld      l,a
        ld      (x86_vga_port),hl
        jp      .port_good
.port_mono_alias:
        ld      a,l
        cp      #A0
        jp      c,.port_bad
        cp      #B0
        jp      nc,.port_mono_b_range
        ; PCem enables the full 3A0-3BF block in monochrome mode; 3A0-3AF
        ; are decoded as open bus by svga_in/svga_out.
        ld      a,(x86_vga_miscout)
        bit     0,a
        jp      nz,.port_bad
        jp      .port_good
.port_mono_b_range:
        ld      a,(x86_vga_miscout)
        bit     0,a
        jp      nz,.port_bad
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
        jp      z,.attr_palette_6bit
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
        jp      c,.dac_read_next
        xor     a
        ld      (x86_vga_dac_pos),a
        ld      hl,x86_vga_dac_read
        inc     (hl)
        jp      .dac_read_return
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
        jp      nz,.dac_write_green
        ld      a,(x86_vga_write_value)
        and     #3F
        ld      (x86_vga_dac_r),a
        ld      a,1
        ld      (x86_vga_dac_pos),a
        ret
.dac_write_green:
        cp      1
        jp      nz,.dac_write_blue
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

; -------------------------------------------------------------------------
; VGA aperture memory backend — PCem svga_read/svga_write model.
; IN: x86_phys_addr is the guest physical address; write takes A=value.
; VRAM is the separate 256 KiB physical allocation pages30h..3Fh.
; Every physical byte is accessed through WIN3/MPAGEX, never as a flat
; 128 KiB aperture mirror. The four VGA planes are interleaved in VRAM.
; -------------------------------------------------------------------------

x86_vga_mem_read8_impl:
        call    x86_vga_aperture_offset
        jp      nc,.mem_read_mapped
        ld      a,#FF
        or      a
        ret
.mem_read_mapped:
        ld      (x86_vga_guest_offset),hl
        ld      a,(x86_vga_chain4)
        or      a
        jp      nz,.mem_read_chain4
        ld      a,(x86_vga_chain2_read)
        or      a
        jp      nz,.mem_read_chain2

        ; Planar read: latch all four planes, then return selected plane or
        ; the colour-compare result according to GDC[5].3.
        call    x86_vga_make_planar_offset
        call    x86_vga_save_vram_base
        call    x86_vga_load_latches
        call    x86_vga_restore_vram_base
        ld      a,(x86_vga_readmode)
        or      a
        jp      nz,.mem_read_compare
        ld      a,(x86_vga_readplane)
        and     3
        call    x86_vga_add_plane_offset
        call    x86_vga_vram_read_at_offset
        or      a
        ret
.mem_read_compare:
        call    x86_vga_compare_latches
        or      a
        ret

.mem_read_chain2:
        ; Chain-2 read selects plane (readplane&2)|(address&1), while
        ; latches are loaded from the unmodified byte address.
        call    x86_vga_make_planar_offset
        call    x86_vga_save_vram_base
        call    x86_vga_load_latches
        ld      hl,(x86_vga_guest_offset)
        ld      a,l
        and     1
        ld      b,a
        ld      a,(x86_vga_readplane)
        and     2
        or      b
        ld      (x86_vga_selected_plane),a
        ld      hl,(x86_vga_guest_offset)
        ld      a,l
        and     #FE
        ld      l,a
        ld      (x86_vga_guest_offset),hl
        call    x86_vga_make_planar_offset
        ld      a,(x86_vga_selected_plane)
        call    x86_vga_add_plane_offset
        call    x86_vga_vram_read_at_offset
        or      a
        ret

.mem_read_chain4:
        ; Chain-4 reads return the packed byte directly, but still refresh
        ; the four latches from its aligned four-byte group.
        ld      hl,(x86_vga_guest_offset)
        ld      (x86_vga_guest_offset_saved),hl
        ld      a,l
        and     #FC
        ld      l,a
        ld      (x86_vga_guest_offset),hl
        call    x86_vga_make_direct_offset
        call    x86_vga_save_vram_base
        call    x86_vga_load_latches
        ld      hl,(x86_vga_guest_offset_saved)
        ld      (x86_vga_guest_offset),hl
        call    x86_vga_make_direct_offset
        call    x86_vga_vram_read_at_offset
        or      a
        ret

x86_vga_mem_write8_impl:
        ld      (x86_vga_write_value),a
        call    x86_vga_aperture_offset
        jp      nc,.mem_write_mapped
        or      a
        ret
.mem_write_mapped:
        ld      (x86_vga_guest_offset),hl
        ld      a,(x86_vga_chain4)
        or      a
        jp      nz,.mem_write_chain4
        ld      a,(x86_vga_chain2_write)
        or      a
        jp      nz,.mem_write_chain2

        ; Normal planar write uses Sequencer Map Mask.
        ld      a,(x86_vga_writemask)
        ld      (x86_vga_write_plane_mask),a
        call    x86_vga_make_planar_offset
        jp      .mem_write_base_ready

.mem_write_chain4:
        ; Chain-4 selects exactly one plane from address bits 1:0.
        ld      hl,(x86_vga_guest_offset)
        ld      a,l
        and     3
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_plane_bits
        add     hl,de
        ld      a,(hl)
        ld      (x86_vga_write_plane_mask),a
        ld      hl,(x86_vga_guest_offset)
        ld      a,l
        and     #FC
        ld      l,a
        ld      (x86_vga_guest_offset),hl
        call    x86_vga_make_direct_offset
        jp      .mem_write_base_ready

.mem_write_chain2:
        ; Chain-2 enables only planes 0/2 for even addresses and 1/3 for odd.
        ld      a,(x86_vga_writemask)
        and     #05
        ld      hl,(x86_vga_guest_offset)
        bit     0,l
        jp      z,.mem_write_chain2_mask_ready
        add     a,a
.mem_write_chain2_mask_ready:
        ld      (x86_vga_write_plane_mask),a
        ld      a,l
        and     #FE
        ld      l,a
        ld      (x86_vga_guest_offset),hl
        call    x86_vga_make_planar_offset

.mem_write_base_ready:
        call    x86_vga_save_vram_base
        call    x86_vga_rotate_cpu_value
        ld      a,(x86_vga_gdc+8)
        ld      (x86_vga_effective_mask),a
        ld      a,(x86_vga_writemode)
        cp      3
        jp      nz,.mem_write_mask_ready
        ld      a,(x86_vga_effective_mask)
        ld      b,a
        ld      a,(x86_vga_rotated_value)
        and     b
        ld      (x86_vga_effective_mask),a
.mem_write_mask_ready:
        xor     a
        ld      (x86_vga_plane_index),a
.mem_write_plane_loop:
        ld      a,(x86_vga_plane_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_plane_bits
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_vga_write_plane_mask)
        and     b
        jp      z,.mem_write_plane_skip
        call    x86_vga_calc_source
        ld      (x86_vga_source_value),a
        call    x86_vga_calc_write_plane_value
        ld      (x86_vga_vram_data),a
        call    x86_vga_restore_vram_base
        ld      a,(x86_vga_plane_index)
        call    x86_vga_add_plane_offset
        call    x86_vga_vram_write_at_offset
.mem_write_plane_skip:
        ld      a,(x86_vga_plane_index)
        inc     a
        ld      (x86_vga_plane_index),a
        cp      4
        jp      c,.mem_write_plane_loop
        or      a
        ret

; GDC[6] selects the actual VGA memory window, as in PCem svga_out().
; Returns HL=window-relative address and carry clear, or carry set if this
; physical address is outside the currently selected aperture.
x86_vga_aperture_offset:
        ld      a,(x86_vga_gdc+6)
        and     #0C
        cp      0
        jp      z,.aperture_128k
        cp      4
        jp      z,.aperture_64k
        cp      8
        jp      z,.aperture_b0000
        jp      .aperture_b8000
.aperture_128k:
        ld      a,(x86_phys_addr+2)
        cp      #0A
        jp      z,.aperture_base_a
        cp      #0B
        jp      nz,.aperture_bad
        jp      .aperture_base_a
.aperture_64k:
        ld      a,(x86_phys_addr+2)
        cp      #0A
        jp      nz,.aperture_bad
.aperture_base_a:
        ld      a,(x86_phys_addr+1)
        ld      h,a
        ld      a,(x86_phys_addr)
        ld      l,a
        or      a
        ret
.aperture_b0000:
        ld      a,(x86_phys_addr+2)
        cp      #0B
        jp      nz,.aperture_bad
        ld      a,(x86_phys_addr+1)
        cp      #80
        jp      nc,.aperture_bad
        ld      h,a
        ld      a,(x86_phys_addr)
        ld      l,a
        or      a
        ret
.aperture_b8000:
        ld      a,(x86_phys_addr+2)
        cp      #0B
        jp      nz,.aperture_bad
        ld      a,(x86_phys_addr+1)
        cp      #80
        jp      c,.aperture_bad
        sub     #80
        ld      h,a
        ld      a,(x86_phys_addr)
        ld      l,a
        or      a
        ret
.aperture_bad:
        scf
        ret

; Convert the 16-bit window-relative guest byte address to interleaved
; planar VRAM offset = guest_address * 4 (18-bit result).
x86_vga_make_planar_offset:
        ld      hl,(x86_vga_guest_offset)
        ld      a,l
        add     a,a
        add     a,a
        ld      (x86_vga_vram_offset),a
        ld      a,l
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        ld      b,a
        ld      a,h
        add     a,a
        add     a,a
        or      b
        ld      (x86_vga_vram_offset+1),a
        ld      a,h
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        ld      (x86_vga_vram_offset+2),a
        ret

; Convert the guest address directly to packed/chain-4 VRAM byte offset.
x86_vga_make_direct_offset:
        ld      hl,(x86_vga_guest_offset)
        ld      (x86_vga_vram_offset),hl
        xor     a
        ld      (x86_vga_vram_offset+2),a
        ret

x86_vga_save_vram_base:
        ld      hl,(x86_vga_vram_offset)
        ld      (x86_vga_vram_base),hl
        ld      a,(x86_vga_vram_offset+2)
        ld      (x86_vga_vram_base+2),a
        ret

x86_vga_restore_vram_base:
        ld      hl,(x86_vga_vram_base)
        ld      (x86_vga_vram_offset),hl
        ld      a,(x86_vga_vram_base+2)
        ld      (x86_vga_vram_offset+2),a
        ret

x86_vga_add_plane_offset:
        ld      e,a
        ld      d,0
        ld      hl,(x86_vga_vram_offset)
        add     hl,de
        ld      (x86_vga_vram_offset),hl
        ret

x86_vga_load_latches:
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_latches),a
        call    x86_vga_increment_vram_offset
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_latches+1),a
        call    x86_vga_increment_vram_offset
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_latches+2),a
        call    x86_vga_increment_vram_offset
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_latches+3),a
        ret

x86_vga_increment_vram_offset:
        ld      hl,(x86_vga_vram_offset)
        inc     hl
        ld      (x86_vga_vram_offset),hl
        ld      a,h
        or      l
        ret     nz
        ld      hl,x86_vga_vram_offset+2
        inc     (hl)
        ret

; Read/write one byte at x86_vga_vram_offset through physical pages30h..3Fh.
x86_vga_vram_read_at_offset:
        ld      a,(x86_vga_vram_offset+2)
        add     a,a
        add     a,a
        ld      b,a
        ld      a,(x86_vga_vram_offset+1)
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        and     3
        add     a,b
        add     a,#30
        rrca
        out     (P126_NGS_BANK_WINDOW_PORT),a
        ld      a,(x86_vga_vram_offset+1)
        and     #3F
        or      #C0
        ld      h,a
        ld      a,(x86_vga_vram_offset)
        ld      l,a
        ld      a,(hl)
        ret

x86_vga_vram_write_at_offset:
        ld      a,(x86_vga_vram_offset+2)
        add     a,a
        add     a,a
        ld      b,a
        ld      a,(x86_vga_vram_offset+1)
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        and     3
        add     a,b
        add     a,#30
        rrca
        out     (P126_NGS_BANK_WINDOW_PORT),a
        ld      a,(x86_vga_vram_offset+1)
        and     #3F
        or      #C0
        ld      h,a
        ld      a,(x86_vga_vram_offset)
        ld      l,a
        ld      a,(x86_vga_vram_data)
        ld      (hl),a
        ret

x86_vga_compare_latches:
        xor     a
        ld      (x86_vga_compare_accum),a
        ld      a,(x86_vga_colournocare)
        bit     0,a
        jp      z,.compare_plane1
        ld      a,(x86_vga_latches)
        ld      b,a
        ld      a,(x86_vga_colourcompare)
        bit     0,a
        jp      z,.compare_plane0_care
        ld      a,b
        cpl
        ld      b,a
.compare_plane0_care:
        ld      a,(x86_vga_compare_accum)
        or      b
        ld      (x86_vga_compare_accum),a
.compare_plane1:
        ld      a,(x86_vga_colournocare)
        bit     1,a
        jp      z,.compare_plane2
        ld      a,(x86_vga_latches+1)
        ld      b,a
        ld      a,(x86_vga_colourcompare)
        bit     1,a
        jp      z,.compare_plane1_care
        ld      a,b
        cpl
        ld      b,a
.compare_plane1_care:
        ld      a,(x86_vga_compare_accum)
        or      b
        ld      (x86_vga_compare_accum),a
.compare_plane2:
        ld      a,(x86_vga_colournocare)
        bit     2,a
        jp      z,.compare_plane3
        ld      a,(x86_vga_latches+2)
        ld      b,a
        ld      a,(x86_vga_colourcompare)
        bit     2,a
        jp      z,.compare_plane2_care
        ld      a,b
        cpl
        ld      b,a
.compare_plane2_care:
        ld      a,(x86_vga_compare_accum)
        or      b
        ld      (x86_vga_compare_accum),a
.compare_plane3:
        ld      a,(x86_vga_colournocare)
        bit     3,a
        jp      z,.compare_done
        ld      a,(x86_vga_latches+3)
        ld      b,a
        ld      a,(x86_vga_colourcompare)
        bit     3,a
        jp      z,.compare_plane3_care
        ld      a,b
        cpl
        ld      b,a
.compare_plane3_care:
        ld      a,(x86_vga_compare_accum)
        or      b
        ld      (x86_vga_compare_accum),a
.compare_done:
        ld      a,(x86_vga_compare_accum)
        cpl
        ret

; Rotate the CPU write byte right by GDC[3].2:0, matching svga_rotate[].
x86_vga_rotate_cpu_value:
        ld      a,(x86_vga_write_value)
        ld      (x86_vga_rotated_value),a
        ld      a,(x86_vga_gdc+3)
        and     7
        ld      b,a
.rotate_cpu_loop:
        ld      a,b
        or      a
        ret     z
        ld      a,(x86_vga_rotated_value)
        rrca
        ld      (x86_vga_rotated_value),a
        djnz    .rotate_cpu_loop
        ret

; Return the source byte for the current plane according to write mode 0..3.
x86_vga_calc_source:
        ld      a,(x86_vga_plane_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_plane_bits
        add     hl,de
        ld      b,(hl)
        ld      a,(x86_vga_writemode)
        cp      1
        jp      z,.source_latch
        cp      2
        jp      z,.source_mode2
        cp      3
        jp      z,.source_set_reset
        ; Mode 0: use Set/Reset only when the corresponding enable bit is set.
        ld      a,(x86_vga_gdc+1)
        and     b
        jp      z,.source_rotated
.source_set_reset:
        ld      a,(x86_vga_gdc)
        and     b
        jp      z,.source_zero
        ld      a,#FF
        ret
.source_zero:
        xor     a
        ret
.source_rotated:
        ld      a,(x86_vga_rotated_value)
        ret
.source_mode2:
        ld      a,(x86_vga_write_value)
        and     b
        jp      z,.source_zero
        ld      a,#FF
        ret
.source_latch:
        ld      a,(x86_vga_plane_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_latches
        add     hl,de
        ld      a,(hl)
        ret

; Apply GDC[3] logical operation and GDC[8] bit mask to one plane.
; Mode 1 writes the latch directly and bypasses the bit mask.
x86_vga_calc_write_plane_value:
        ld      a,(x86_vga_writemode)
        cp      1
        jp      nz,.write_plane_logic
        ld      a,(x86_vga_plane_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_latches
        add     hl,de
        ld      a,(hl)
        ret
.write_plane_logic:
        ld      a,(x86_vga_source_value)
        ld      (x86_vga_logical_result),a
        ld      a,(x86_vga_plane_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_vga_latches
        add     hl,de
        ld      a,(hl)
        ld      (x86_vga_latch_temp),a
        ld      a,(x86_vga_gdc+3)
        and     #18
        cp      8
        jp      z,.write_plane_and
        cp      #10
        jp      z,.write_plane_or
        cp      #18
        jp      z,.write_plane_xor
        jp      .write_plane_mask
.write_plane_and:
        ld      a,(x86_vga_logical_result)
        ld      b,a
        ld      a,(x86_vga_latch_temp)
        and     b
        ld      (x86_vga_logical_result),a
        jp      .write_plane_mask
.write_plane_or:
        ld      a,(x86_vga_logical_result)
        ld      b,a
        ld      a,(x86_vga_latch_temp)
        or      b
        ld      (x86_vga_logical_result),a
        jp      .write_plane_mask
.write_plane_xor:
        ld      a,(x86_vga_logical_result)
        ld      b,a
        ld      a,(x86_vga_latch_temp)
        xor     b
        ld      (x86_vga_logical_result),a
.write_plane_mask:
        ld      a,(x86_vga_effective_mask)
        ld      b,a
        ld      a,(x86_vga_logical_result)
        and     b
        ld      c,a
        ld      a,(x86_vga_effective_mask)
        cpl
        ld      b,a
        ld      a,(x86_vga_latch_temp)
        and     b
        or      c
        ret

; Text-mode snapshot and cell API used by the ATM frame converter.
; Snapshot OUT: A=text aperture middle byte (00h mono / 80h colour),
; HL=start byte address, DE=row stride in bytes; carry set if not text aperture.
x86_vga_get_text_snapshot_impl:
        ld      a,(x86_vga_gdc+6)
        bit     0,a
        jp      nz,.text_snapshot_bad
        ld      a,(x86_vga_attr+#10)
        bit     0,a
        jp      nz,.text_snapshot_bad
        ld      a,(x86_vga_gdc+6)
        and     #0C
        cp      0
        jp      z,.text_snapshot_colour
        cp      8
        jp      z,.text_snapshot_mono
        cp      #0C
        jp      z,.text_snapshot_colour
        scf
        ret
.text_snapshot_colour:
        ld      a,#80
        jp      .text_snapshot_base
.text_snapshot_mono:
        xor     a
.text_snapshot_base:
        ld      (x86_vga_text_base_mid),a
        ld      a,(x86_vga_chain4)
        or      a
        jp      nz,.text_snapshot_bad
        ; VGA text memory must use odd/even addressing on both the host
        ; write path (Sequencer Memory Mode) and the host read path
        ; (Graphics Controller Mode). Do not reinterpret a planar/linear
        ; graphics aperture as character/attribute pairs.
        ld      a,(x86_vga_chain2_write)
        or      a
        jp      z,.text_snapshot_bad
        ld      a,(x86_vga_chain2_read)
        or      a
        jp      z,.text_snapshot_bad
        ld      a,(x86_vga_gdc+5)
        and     #6B
        jp      nz,.text_snapshot_bad
        ; PCem selects the 40-column text renderer from Sequencer Clocking
        ; Mode bit3. This ATM text descriptor is 80 columns.
        ld      a,(x86_vga_seq+1)
        bit     3,a
        jp      nz,.text_snapshot_bad

        ; Match PCem svga_poll()/svga_render_text_80():
        ; ma_latch = CRTC[0Ch:0Dh] + ((CRTC[08h]&60h)>>5)
        ; frame MA adds ((CRTC[05h]&60h)>>5), then renderer scales MA<<2.
        ; The CPU text aperture byte address is frame_MA<<1;
        ; row stride is CRTC[13h]<<2 bytes.
        ld      a,(x86_vga_crtc+12)
        ld      h,a
        ld      a,(x86_vga_crtc+13)
        ld      l,a
        ld      a,(x86_vga_crtc+8)
        and     #60
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        ld      e,a
        ld      d,0
        add     hl,de
        ; Horizontal blank end contributes the second MA start adjustment.
        ld      a,(x86_vga_crtc+5)
        and     #60
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        ld      e,a
        ld      d,0
        add     hl,de
        add     hl,hl
        ld      (x86_vga_text_start),hl
        ; PCem advances ma by rowoffset<<3; convert ma units to CPU bytes.
        ld      a,(x86_vga_crtc+19)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        ex      de,hl
        ld      hl,(x86_vga_text_start)
        ld      a,(x86_vga_text_base_mid)
        or      a
        ret
.text_snapshot_bad:
        scf
        ret

; IN: A=aperture middle byte (00h B0000 / 80h B8000), HL=byte offset.
; OUT: A=character, D=attribute. Uses chain-2 read semantics temporarily.
x86_vga_read_text_cell_impl:
        ld      (x86_vga_text_base_mid),a
        ld      (x86_vga_text_offset),hl
        ld      hl,(x86_phys_addr)
        ld      (x86_vga_text_saved_phys),hl
        ld      a,(x86_phys_addr+2)
        ld      (x86_vga_text_saved_phys+2),a
        ld      a,(x86_vga_chain2_read)
        ld      (x86_vga_text_saved_chain2),a
        ld      a,(x86_vga_readplane)
        ld      (x86_vga_text_saved_readplane),a
        ld      hl,x86_vga_latches
        ld      de,x86_vga_text_saved_latches
        ld      bc,4
        ldir

        ld      a,1
        ld      (x86_vga_chain2_read),a
        xor     a
        ld      (x86_vga_readplane),a
        call    x86_vga_set_text_phys_addr
        call    x86_vga_mem_read8_impl
        ld      (x86_vga_text_char),a

        ld      hl,(x86_vga_text_offset)
        inc     hl
        ld      (x86_vga_text_offset),hl
        call    x86_vga_set_text_phys_addr
        call    x86_vga_mem_read8_impl
        ld      (x86_vga_text_attr),a

        ld      hl,(x86_vga_text_saved_phys)
        ld      (x86_phys_addr),hl
        ld      a,(x86_vga_text_saved_phys+2)
        ld      (x86_phys_addr+2),a
        ld      a,(x86_vga_text_saved_chain2)
        ld      (x86_vga_chain2_read),a
        ld      a,(x86_vga_text_saved_readplane)
        ld      (x86_vga_readplane),a
        ld      hl,x86_vga_text_saved_latches
        ld      de,x86_vga_latches
        ld      bc,4
        ldir
        ld      a,(x86_vga_text_attr)
        ld      d,a
        ld      a,(x86_vga_text_char)
        or      a
        ret

x86_vga_set_text_phys_addr:
        ld      hl,(x86_vga_text_offset)
        ld      a,(x86_vga_text_base_mid)
        add     a,h
        ld      (x86_phys_addr+1),a
        ld      a,#0B
        adc     a,0
        ld      (x86_phys_addr+2),a
        ld      a,l
        ld      (x86_phys_addr),a
        ret

; Save/restore-safe aperture regression. It tests planar writes to all four
; interleaved planes, selected-plane reads, then chain-4 packed access at the
; final 64 KiB aperture byte (AFFFFh -> packed VRAM offset 0FFFFh; planar path reaches 3FFFCh).
x86_vga_aperture_selftest_impl:
        ld      hl,(x86_phys_addr)
        ld      (x86_vga_test_saved_phys),hl
        ld      a,(x86_phys_addr+2)
        ld      (x86_vga_test_saved_phys+2),a

        ld      hl,#FFFC
        ld      (x86_vga_vram_offset),hl
        ld      a,3
        ld      (x86_vga_vram_offset+2),a
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_test_saved_vram),a
        call    x86_vga_increment_vram_offset
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_test_saved_vram+1),a
        call    x86_vga_increment_vram_offset
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_test_saved_vram+2),a
        call    x86_vga_increment_vram_offset
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_test_saved_vram+3),a
        ; Chain-4 addresses the packed byte offset directly (FFFFh), so
        ; preserve that byte separately from the planar 3FFFCh..3FFFFh group.
        ld      hl,#FFFF
        ld      (x86_vga_vram_offset),hl
        xor     a
        ld      (x86_vga_vram_offset+2),a
        call    x86_vga_vram_read_at_offset
        ld      (x86_vga_test_saved_vram+4),a

        ; Select guest AFFFFh and standard planar write mode 0.
        ld      hl,#FFFF
        ld      (x86_phys_addr),hl
        ld      a,#0A
        ld      (x86_phys_addr+2),a
        ld      a,4
        ld      (x86_vga_gdc+6),a
        xor     a
        ld      (x86_vga_chain4),a
        ld      (x86_vga_chain2_write),a
        ld      (x86_vga_chain2_read),a
        ld      (x86_vga_writemode),a
        ld      (x86_vga_readmode),a
        ld      (x86_vga_gdc+3),a
        ld      (x86_vga_gdc+1),a
        ld      (x86_vga_gdc),a
        ld      (x86_vga_readplane),a
        ld      a,#0F
        ld      (x86_vga_writemask),a
        ld      a,#FF
        ld      (x86_vga_gdc+8),a

        ld      a,#5A
        call    x86_vga_mem_write8_impl
        ld      a,0
        ld      (x86_vga_readplane),a
        call    x86_vga_mem_read8_impl
        cp      #5A
        jp      nz,.aperture_test_failed
        ld      a,1
        ld      (x86_vga_readplane),a
        call    x86_vga_mem_read8_impl
        cp      #5A
        jp      nz,.aperture_test_failed
        ld      a,2
        ld      (x86_vga_readplane),a
        call    x86_vga_mem_read8_impl
        cp      #5A
        jp      nz,.aperture_test_failed
        ld      a,3
        ld      (x86_vga_readplane),a
        call    x86_vga_mem_read8_impl
        cp      #5A
        jp      nz,.aperture_test_failed

        ; Chain-4 uses the same aperture address as a packed byte offset.
        ld      a,1
        ld      (x86_vga_chain4),a
        ld      a,#A5
        call    x86_vga_mem_write8_impl
        call    x86_vga_mem_read8_impl
        cp      #A5
        jp      nz,.aperture_test_failed

        xor     a
        ld      (x86_vga_test_failed),a
        jp      .aperture_test_restore
.aperture_test_failed:
        ld      a,1
        ld      (x86_vga_test_failed),a
.aperture_test_restore:
        ; Restore all four bytes of physical VRAM at 3FFFCh..3FFFFh.
        ld      hl,#FFFC
        ld      (x86_vga_vram_offset),hl
        ld      a,3
        ld      (x86_vga_vram_offset+2),a
        ld      a,(x86_vga_test_saved_vram)
        ld      (x86_vga_vram_data),a
        call    x86_vga_vram_write_at_offset
        call    x86_vga_increment_vram_offset
        ld      a,(x86_vga_test_saved_vram+1)
        ld      (x86_vga_vram_data),a
        call    x86_vga_vram_write_at_offset
        call    x86_vga_increment_vram_offset
        ld      a,(x86_vga_test_saved_vram+2)
        ld      (x86_vga_vram_data),a
        call    x86_vga_vram_write_at_offset
        call    x86_vga_increment_vram_offset
        ld      a,(x86_vga_test_saved_vram+3)
        ld      (x86_vga_vram_data),a
        call    x86_vga_vram_write_at_offset
        ld      hl,#FFFF
        ld      (x86_vga_vram_offset),hl
        xor     a
        ld      (x86_vga_vram_offset+2),a
        ld      a,(x86_vga_test_saved_vram+4)
        ld      (x86_vga_vram_data),a
        call    x86_vga_vram_write_at_offset

        ld      hl,(x86_vga_test_saved_phys)
        ld      (x86_phys_addr),hl
        ld      a,(x86_vga_test_saved_phys+2)
        ld      (x86_phys_addr+2),a
        call    x86_vga_reset_impl
        ld      a,(x86_vga_test_failed)
        or      a
        jp      nz,.aperture_test_bad
        ld      hl,#A55A
        ld      a,#5A
        or      a
        ret
.aperture_test_bad:
        ld      a,#FF
        scf
        ret

; Register-file regression against the PCem-visible port protocol.
; OUT A=5Ah, HL=A55Ah on pass; carry set on failure. Restores reset state.
x86_vga_register_selftest_impl:
        ; Sequencer index/data round-trip.
        ld      hl,#03C4
        ld      a,2
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C5
        ld      a,#0F
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C5
        call    x86_vga_io_read8_impl
        cp      #0F
        jp      nz,.vga_test_fail

        ; PCem status-port phase: with bit0 clear, bits5:4 toggle on
        ; successive reads; the same read also resets the AC flip-flop.
        xor     a
        ld      (x86_vga_cgastat),a
        ld      hl,#03DA
        call    x86_vga_io_read8_impl
        cp      #30
        jp      nz,.vga_test_fail
        ld      hl,#03DA
        call    x86_vga_io_read8_impl
        or      a
        jp      nz,.vga_test_fail
        ld      hl,#03C0
        ld      a,#12
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C0
        ld      a,#05
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C1
        call    x86_vga_io_read8_impl
        cp      #05
        jp      nz,.vga_test_fail

        ; Graphics Controller read-plane register round-trip.
        ld      hl,#03CE
        ld      a,4
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03CF
        ld      a,3
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03CF
        call    x86_vga_io_read8_impl
        cp      3
        jp      nz,.vga_test_fail

        ; CRTC index/data and the mono/colour alias switch from MiscOut.
        ld      hl,#03D4
        ld      a,#0C
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03D5
        ld      a,#44
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03D5
        call    x86_vga_io_read8_impl
        cp      #44
        jp      nz,.vga_test_fail
        ld      hl,#03C2
        xor     a
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03B4
        ld      a,#0C
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03B5
        ld      a,#33
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03B5
        call    x86_vga_io_read8_impl
        cp      #33
        jp      nz,.vga_test_fail
        ; The inactive colour block remains claimed by VGA and reads open bus.
        ld      hl,#03D5
        call    x86_vga_io_read8_impl
        cp      #FF
        jp      nz,.vga_test_fail

        ; DAC RGB write/read sequencing (standard six-bit DAC components).
        ld      hl,#03C8
        ld      a,2
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C9
        ld      a,#12
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C9
        ld      a,#23
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C9
        ld      a,#34
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C7
        ld      a,2
        call    x86_vga_io_write8_impl
        jp      c,.vga_test_fail
        ld      hl,#03C9
        call    x86_vga_io_read8_impl
        cp      #12
        jp      nz,.vga_test_fail

        call    x86_vga_aperture_selftest_impl
        jp      c,.vga_test_fail

        call    x86_vga_reset_impl
        ld      hl,#A55A
        ld      a,#5A
        or      a
        ret
.vga_test_fail:
        push    af
        call    x86_vga_reset_impl
        pop     af
        scf
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
x86_vga_guest_offset:          dw 0
x86_vga_guest_offset_saved:    dw 0
x86_vga_vram_offset:           defs 3,0
x86_vga_vram_base:             defs 3,0
x86_vga_vram_data:             db 0
x86_vga_latches:               defs 4,0
x86_vga_write_plane_mask:      db 0
x86_vga_selected_plane:        db 0
x86_vga_plane_index:           db 0
x86_vga_effective_mask:        db 0
x86_vga_source_value:          db 0
x86_vga_logical_result:        db 0
x86_vga_latch_temp:            db 0
x86_vga_compare_accum:         db 0
x86_vga_rotated_value:         db 0
x86_vga_plane_bits:            db 1,2,4,8
x86_vga_text_base_mid:         db 0
x86_vga_text_start:            dw 0
x86_vga_text_offset:           dw 0
x86_vga_text_saved_phys:       defs 3,0
x86_vga_text_saved_chain2:     db 0
x86_vga_text_saved_readplane:  db 0
x86_vga_text_saved_latches:    defs 4,0
x86_vga_text_char:             db 0
x86_vga_text_attr:             db 0
x86_vga_test_saved_phys:       defs 3,0
x86_vga_test_saved_vram:       defs 5,0
x86_vga_test_failed:           db 0

        ASSERT X86_VGA_VRAM_BYTES = #40000
        ASSERT X86_VGA_VRAM_PAGE_COUNT*#4000 = X86_VGA_VRAM_BYTES
