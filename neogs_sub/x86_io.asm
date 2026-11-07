; PROJECT126 — virtual 8086 I/O port bus.
; No physical NeoGS/Z80 port access is performed here. Guest I/O ports are
; modeled in software; external device requests will be routed through DMA/IPC.
;
; Initial deterministic test device:
;   port 00E0h: 16-bit read/write latch (byte accesses use low lane).
; Unmapped reads return FFh/FFFFh; unmapped writes are ignored.
; Guest FLAGS and CPU registers are never changed by the backend.

x86_io_read8:
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        jr      nz,.io_read8_open_bus
        ld      a,(x86_io_test_latch)
        ret
.io_read8_open_bus:
        ld      a,#FF
        ret

x86_io_read16:
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        jr      nz,.io_read16_open_bus
        ld      hl,(x86_io_test_latch)
        ret
.io_read16_open_bus:
        ld      hl,#FFFF
        ret

; A=value. Byte write updates only the low lane of port 00E0h.
x86_io_write8:
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        ret     nz
        ld      (x86_io_test_latch),a
        ret

; HL=value. Word write updates the complete 16-bit test latch.
x86_io_write16:
        ld      de,(x86_io_port)
        ld      bc,#00E0
        or      a
        sbc     hl,bc
        ret     nz
        ld      (x86_io_test_latch),hl
        ret

x86_io_port: dw 0
x86_io_test_latch: dw 0
