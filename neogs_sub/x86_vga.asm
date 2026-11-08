; =========================================================================
; PROJECT126 — IBM VGA overlay foundation
; Reference implementation: Project126/PCem vid_vga.c + vid_svga.c.
; Physical VRAM allocation: pages 30h..3Fh (256 KiB), managed by the
; guest-memory VGA backend; this overlay owns register/scanout state only.
;
; This first integration slice deliberately exports only reset and a
; load/dispatch probe. VGA register and aperture semantics are added in
; subsequent stages; no partial port behavior is advertised as VGA-ready.
; Logical origin 8000h, dynamic physical page 08h, module ID 05h.
; =========================================================================

X86_VGA_MODULE_ID       EQU 5
X86_VGA_PHYS_PAGE       EQU #08
X86_VGA_VRAM_BYTES      EQU #40000
X86_VGA_VRAM_PAGE_FIRST EQU #30
X86_VGA_VRAM_PAGE_COUNT EQU #10

; Called through p126_overlay_call_module after the resident registers ID05.
; OUT A=56h, HL=A55Ah. This proves the dynamically mapped overlay is callable.
x86_vga_overlay_probe:
        ld      hl,#A55A
        ld      a,#56
        ret

; Initialize the standard VGA register file defaults used by PCem vga_init.
; This is state initialization only; register I/O is not wired yet.
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
        ld      a,1
        ld      (x86_vga_miscout),a
        ld      a,8
        ld      (x86_vga_bpp),a
        ret

; Private VGA state. DAC stores 256 RGB triplets, 6/8-bit components as
; selected by the standard VGA DAC configuration.
x86_vga_miscout:              db 1
x86_vga_crtcreg:              db 0
x86_vga_seqaddr:              db 0
x86_vga_gdcaddr:              db 0
x86_vga_attraddr:             db 0
x86_vga_attrff:               db 0
x86_vga_attr_palette_enable:  db 0
x86_vga_dac_mask:             db #FF
x86_vga_dac_status:           db 0
x86_vga_dac_read:             db 0
x86_vga_dac_write:            db 0
x86_vga_dac_pos:              db 0
x86_vga_bpp:                  db 8
x86_vga_crtc:                 defs 128,0
x86_vga_gdc:                  defs 64,0
x86_vga_attr:                 defs 32,0
x86_vga_seq:                  defs 64,0
x86_vga_dac:                  defs 768,0

        ASSERT X86_VGA_VRAM_BYTES = #40000
        ASSERT X86_VGA_VRAM_PAGE_COUNT*#4000 = X86_VGA_VRAM_BYTES
