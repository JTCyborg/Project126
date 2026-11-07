; PROJECT126 — virtual 8086 I/O port bus.
; Guest I/O devices are software models on NeoGS. No guest port number is
; ever issued as a physical NeoGS/Z80 I/O operation.
;
; Implemented:
;   0000h-000Fh, 0080h-0083h: 8237 address/count, controller and page registers.
;   0020h-0021h: 8259A master PIC register model and CPU acknowledge path.
;   0060h-0063h: initial XT-compatible 8255 PPI / keyboard interface.
;   00E0h: retained 16-bit diagnostic test latch.
;   Keyboard FIFO pushes raise master-PIC IRQ1; ATM input producer remains pending.
;   DMA transfer engine and PIT-driven IRQ0 are separate, not-yet-implemented services.
;
; PPI compatibility slice:
;   60h = port A / keyboard data (FIFO consumer when configured input).
;   61h = port B / system control; bit-6 rising edge resets XT keyboard,
;         bit 7 acknowledges/clears the current keyboard data latch.
;   62h = port C input/output composition.
;   63h = mode-set and bit-set/reset control register (mode 0 implemented).
;   PPI reset defaults follow PCem/ppi.c: PA=00h, PB=40h.
;
; Keyboard FIFO bytes raise PIC IRQ1 when accepted. ATM keyboard input delivery
; remains a future DMA/IPC producer; no physical NeoGS I/O is involved.

x86_io_reset_impl:
        ld      hl,0
        ld      (x86_io_count_in),hl
        ld      (x86_io_count_out),hl
        ld      (x86_io_test_latch),hl
        xor     a
        ld      (x86_io_keyboard_head),a
        ld      (x86_io_keyboard_tail),a
        ld      (x86_io_keyboard_count),a
        ld      (x86_io_keyboard_last),a
        ld      (x86_io_ppi_pc),a
        ld      a,#9B
        ld      (x86_io_ppi_control),a
        ld      a,#40
        ld      (x86_io_ppi_pb),a
        ; 8259A master PIC reset state: no pending/in-service IRQs,
        ; all lines masked, XT vector base 08h.
        xor     a
        ld      (x86_io_pic_irr),a
        ld      (x86_io_pic_isr),a
        ld      (x86_io_keyboard_head),a
        ld      (x86_io_keyboard_tail),a
        ld      (x86_io_keyboard_count),a
        ld      (x86_io_keyboard_last),a
        ld      (x86_io_pic_init_state),a
        ld      (x86_io_pic_need_icw4),a
        ld      (x86_io_pic_single),a
        ld      (x86_io_pic_read_isr),a
        ld      a,#FF
        ld      (x86_io_pic_imr),a
        ld      a,#08
        ld      (x86_io_pic_vector_base),a
        call    x86_io_pic_selftest_impl
        call    x86_io_dma_reset_impl
        call    x86_io_dma_selftest_impl
        call    x86_io_pit_reset_impl
        call    x86_io_pit_selftest_impl
        ret

; Register-level regression for the 8259A master model. It is run after the
; deterministic reset state is established and restores that state on exit.
x86_io_pic_selftest_impl:
        ; ICW1=13h (single master, ICW4 follows), ICW2=20h, ICW4=01h.
        ld      hl,#0020
        ld      (x86_io_port),hl
        ld      a,#13
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        ld      hl,#0021
        ld      (x86_io_port),hl
        ld      a,#20
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        ld      a,#01
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        ; Verify IMR write/readback.
        ld      a,#A5
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        call    x86_io_pic_read8
        jp      c,.pic_selftest_fail
        cp      #A5
        jp      nz,.pic_selftest_fail
        ; A queued XT scan code must raise IRQ1 and select vector 21h.
        ld      a,#1E
        call    x86_io_keyboard_push_impl
        jp      c,.pic_selftest_fail
        ld      a,(x86_pending_irq)
        cp      1
        jp      nz,.pic_selftest_fail
        ld      a,(x86_irq_vector)
        cp      #21
        jp      nz,.pic_selftest_fail
        call    x86_io_pic_ack_impl
        jp      c,.pic_selftest_fail
        cp      #21
        jp      nz,.pic_selftest_fail
        ld      a,(x86_io_pic_isr)
        cp      2
        jp      nz,.pic_selftest_fail
        ld      a,(x86_io_pic_irr)
        or      a
        jp      nz,.pic_selftest_fail
        ; The keyboard handler consumes the queued scan code before EOI.
        call    x86_io_keyboard_read_impl
        cp      #1E
        jp      nz,.pic_selftest_fail
        ; Specific EOI for IRQ1 clears the acknowledged request.
        ld      hl,#0020
        ld      (x86_io_port),hl
        ld      a,#61
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        ld      a,(x86_io_pic_isr)
        or      a
        jp      nz,.pic_selftest_fail
        ; OCW3 selects ISR (0Bh) and IRR (0Ah) for command-port reads.
        ld      hl,#0020
        ld      (x86_io_port),hl
        ld      a,#0B
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        call    x86_io_pic_read8
        jp      c,.pic_selftest_fail
        or      a
        jp      nz,.pic_selftest_fail
        ld      a,#0A
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        call    x86_io_pic_read8
        jp      c,.pic_selftest_fail
        or      a
        jp      nz,.pic_selftest_fail
        ; Exercise specific EOI (IRQ7) and non-specific EOI (IRQ0 priority).
        ld      a,#80
        ld      (x86_io_pic_isr),a
        ld      a,#67
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        ld      a,(x86_io_pic_isr)
        or      a
        jp      nz,.pic_selftest_fail
        ld      a,#81
        ld      (x86_io_pic_isr),a
        ld      a,#20
        call    x86_io_pic_write8
        jp      c,.pic_selftest_fail
        ld      a,(x86_io_pic_isr)
        cp      #80
        jp      nz,.pic_selftest_fail
        ld      hl,x86_io_pic_selftest_pass
        jr      .pic_selftest_restore
.pic_selftest_fail:
        ld      hl,x86_io_pic_selftest_fail
.pic_selftest_restore:
        push    hl
        xor     a
        ld      (x86_io_pic_irr),a
        ld      (x86_io_pic_isr),a
        ld      (x86_io_pic_init_state),a
        ld      (x86_io_pic_need_icw4),a
        ld      (x86_io_pic_single),a
        ld      (x86_io_pic_read_isr),a
        ld      a,#FF
        ld      (x86_io_pic_imr),a
        ld      a,#08
        ld      (x86_io_pic_vector_base),a
        xor     a
        ld      (x86_pending_irq),a
        ld      a,8
        ld      (x86_irq_vector),a
        ld      hl,0
        ld      (x86_io_port),hl
        pop     hl
        jp      x86_io_log_string

; A=XT keyboard scan-code byte. Carry set means FIFO full (byte rejected).
; This is the software input-service API; the caller is the future IPC
; keyboard event handler, never a physical NeoGS port operation.
x86_io_keyboard_push_impl:
        ld      b,a
        ld      a,(x86_io_keyboard_count)
        cp      16
        jr      nc,.keyboard_push_full
        ld      a,(x86_io_keyboard_tail)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_keyboard_fifo
        add     hl,de
        ld      (hl),b
        ld      a,(x86_io_keyboard_tail)
        inc     a
        and     #0F
        ld      (x86_io_keyboard_tail),a
        ld      a,(x86_io_keyboard_count)
        inc     a
        ld      (x86_io_keyboard_count),a
        ; XT keyboard data-ready edge is IRQ1 on the master PIC.
        ld      a,1
        call    x86_io_pic_raise_impl
        or      a
        ret
.keyboard_push_full:
        scf
        ret

; Reset XT keyboard input state and queue the standard BAT completion byte.
x86_io_keyboard_reset_impl:
        xor     a
        ld      (x86_io_keyboard_head),a
        ld      (x86_io_keyboard_tail),a
        ld      (x86_io_keyboard_count),a
        ld      (x86_io_keyboard_last),a
        ld      a,#AA
        jp      x86_io_keyboard_push_impl

; A=next keyboard byte, or last data latch if FIFO empty.
x86_io_keyboard_read_impl:
        ld      a,(x86_io_keyboard_count)
        or      a
        jr      z,.keyboard_read_empty
        ld      a,(x86_io_keyboard_head)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_keyboard_fifo
        add     hl,de
        ld      a,(hl)
        ld      (x86_io_keyboard_last),a
        ld      a,(x86_io_keyboard_head)
        inc     a
        and     #0F
        ld      (x86_io_keyboard_head),a
        ld      a,(x86_io_keyboard_count)
        dec     a
        ld      (x86_io_keyboard_count),a
        ld      a,(x86_io_keyboard_last)
        ret
.keyboard_read_empty:
        ld      a,(x86_io_keyboard_last)
        ret

; Overlay-gate regression entry. This routine runs on page04 and
; deliberately calls the page05 ALU wrapper while page04 is active.
; A=08h on success (05h + 03h), with carry clear.
x86_io_overlay_nested_gate_probe_impl:
        ; The regression must not leak its arithmetic FLAGS into the guest.
        ld      hl,(x86_reg_flags)
        push    hl
        ld      a,#05
        ld      c,#03
        call    x86_alu_add8
        cp      #08
        pop     hl
        ld      (x86_reg_flags),hl
        ret

; Read one byte from the guest I/O bus. A=read value.
x86_io_read8_impl:
        ld      hl,(x86_io_count_in)
        inc     hl
        ld      (x86_io_count_in),hl
        call    x86_io_read8_impl_device
        ret

; Internal byte read. Does not change the operation counter.
x86_io_read8_impl_device:
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        jr      nz,.io_read8_ppi
        ld      a,(x86_io_test_latch)
        ret
.io_read8_ppi:
        call    x86_io_dma_read8
        ret     nc
        call    x86_io_pit_read8
        ret     nc
        call    x86_io_pic_read8
        ret     nc
        call    x86_io_ppi_read8
        ret     nc
        ld      a,#FF
        ret

; Read one byte from PPI 8255. Carry set means port is not in PPI decode.
x86_io_ppi_read8:
        call    x86_io_ppi_decode
        ret     c
        cp      0
        jr      z,.ppi_read_a
        cp      1
        jr      z,.ppi_read_b
        cp      2
        jr      z,.ppi_read_c
        scf                             ; control register is write-only
        ret
.ppi_read_a:
        jp      x86_io_keyboard_read_impl
.ppi_read_b:
        ld      a,(x86_io_ppi_pb)
        or      a
        ret
.ppi_read_c:
        ; Port C combines external input pins and the output latch by nibble.
        ld      a,(x86_io_ppi_control)
        ld      b,a
        ld      a,(x86_io_ppi_pc)
        ld      c,a
        ld      a,(x86_io_ppi_port_c_input)
        bit     3,b
        jr      nz,.ppi_pc_upper_input
        ld      a,c
        and     #F0
        ld      d,a
        ld      a,(x86_io_ppi_port_c_input)
        and     #0F
        or      d
        jr      .ppi_pc_lower
.ppi_pc_upper_input:
        and     #F0
        ld      d,a
        ld      a,c
        and     #0F
        or      d
.ppi_pc_lower:
        bit     0,b
        jr      nz,.ppi_pc_done
        and     #F0
        ld      d,a
        ld      a,c
        and     #0F
        or      d
.ppi_pc_done:
        or      a
        ret

; -------------------------------------------------------------------------
; 8253 PIT programming/readback slice (ports 0040h..0043h).
; Counters are static register latches in this phase: no clock decrement,
; output pin, speaker waveform or IRQ0 generation is claimed.
; -------------------------------------------------------------------------
x86_io_pit_decode:
        ld      hl,(x86_io_port)
        ld      de,#0040
        or      a
        sbc     hl,de
        ld      a,h
        or      a
        jr      nz,.pit_decode_bad
        ld      a,l
        cp      4
        jr      nc,.pit_decode_bad
        or      a
        ret
.pit_decode_bad:
        scf
        ret

x86_io_pit_read8:
        call    x86_io_pit_decode
        ret     c
        cp      3
        jr      z,.pit_read_open_bus
        ld      (x86_io_pit_channel),a
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_access
        add     hl,de
        ld      a,(hl)
        cp      1
        jr      z,.pit_read_lsb
        cp      2
        jr      z,.pit_read_msb
        cp      3
        jr      nz,.pit_read_open_bus
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_read_ff
        add     hl,de
        ld      a,(hl)
        ld      (x86_io_pit_byte_select),a
        jr      .pit_read_byte
.pit_read_lsb:
        xor     a
        ld      (x86_io_pit_byte_select),a
        jr      .pit_read_byte
.pit_read_msb:
        ld      a,1
        ld      (x86_io_pit_byte_select),a
.pit_read_byte:
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_latch_valid
        add     hl,de
        ld      a,(hl)
        or      a
        jr      z,.pit_read_reload
        ld      hl,x86_io_pit_latch
        jr      .pit_read_base
.pit_read_reload:
        ld      hl,x86_io_pit_reload
.pit_read_base:
        ld      a,(x86_io_pit_channel)
        add     a,a
        ld      e,a
        ld      a,(x86_io_pit_byte_select)
        add     a,e
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(hl)
        ld      (x86_io_pit_read_value),a
        ; LSB/MSB mode toggles after each byte; a complete pair releases latch.
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_access
        add     hl,de
        ld      a,(hl)
        cp      3
        jr      nz,.pit_read_clear_latch
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_read_ff
        add     hl,de
        ld      a,(hl)
        xor     1
        ld      (hl),a
        or      a
        jr      nz,.pit_read_done
.pit_read_clear_latch:
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_latch_valid
        add     hl,de
        xor     a
        ld      (hl),a
.pit_read_done:
        ld      a,(x86_io_pit_read_value)
        or      a
        ret
.pit_read_open_bus:
        ld      a,#FF
        or      a
        ret

x86_io_pit_write8:
        ld      (x86_io_pit_write_value),a
        call    x86_io_pit_decode
        ret     c
        cp      3
        jr      z,.pit_write_control
        ld      (x86_io_pit_channel),a
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_access
        add     hl,de
        ld      a,(hl)
        cp      1
        jr      z,.pit_write_lsb
        cp      2
        jr      z,.pit_write_msb
        cp      3
        jr      nz,.pit_write_done
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_write_ff
        add     hl,de
        ld      a,(hl)
        ld      (x86_io_pit_byte_select),a
        jr      .pit_write_byte
.pit_write_lsb:
        xor     a
        ld      (x86_io_pit_byte_select),a
        jr      .pit_write_byte
.pit_write_msb:
        ld      a,1
        ld      (x86_io_pit_byte_select),a
.pit_write_byte:
        ld      a,(x86_io_pit_channel)
        add     a,a
        ld      e,a
        ld      a,(x86_io_pit_byte_select)
        add     a,e
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_reload
        add     hl,de
        ld      a,(x86_io_pit_write_value)
        ld      (hl),a
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_access
        add     hl,de
        ld      a,(hl)
        cp      3
        jr      nz,.pit_write_done
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_write_ff
        add     hl,de
        ld      a,(hl)
        xor     1
        ld      (hl),a
.pit_write_done:
        or      a
        ret
.pit_write_control:
        ld      a,(x86_io_pit_write_value)
        rrca
        rrca
        rrca
        rrca
        rrca
        rrca
        and     3
        cp      3
        jr      z,.pit_write_done
        ld      (x86_io_pit_channel),a
        ; Access mode 00 is a count latch command; it does not reprogram mode.
        ld      a,(x86_io_pit_write_value)
        rrca
        rrca
        rrca
        rrca
        and     3
        jr      z,.pit_latch_command
        ; Store the selected channel's access mode.
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_access
        add     hl,de
        ld      a,(x86_io_pit_write_value)
        rrca
        rrca
        rrca
        rrca
        and     3
        ld      (hl),a
        ; Normalize modes 6/7 to aliases 2/3 and store per channel.
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_mode
        add     hl,de
        ld      a,(x86_io_pit_write_value)
        rrca
        and     7
        cp      6
        jr      c,.pit_mode_store
        sub     4
.pit_mode_store:
        ld      (hl),a
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_bcd
        add     hl,de
        ld      a,(x86_io_pit_write_value)
        and     1
        ld      (hl),a
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_read_ff
        add     hl,de
        xor     a
        ld      (hl),a
        ld      hl,x86_io_pit_write_ff
        add     hl,de
        ld      (hl),a
        ld      hl,x86_io_pit_latch_valid
        add     hl,de
        ld      (hl),a
        or      a
        ret
.pit_latch_command:
        ; Copy the selected 16-bit reload value into its read latch.
        ld      a,(x86_io_pit_channel)
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_reload
        add     hl,de
        push    hl
        ld      hl,x86_io_pit_latch
        add     hl,de
        ex      de,hl
        pop     hl
        ld      bc,2
        ldir
        ld      a,(x86_io_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pit_latch_valid
        add     hl,de
        ld      a,1
        ld      (hl),a
        or      a
        ret

x86_io_pit_reset_impl:
        xor     a
        ld      hl,x86_io_pit_reload
        ld      de,x86_io_pit_reload+1
        ld      bc,5
        ld      (hl),a
        ldir
        ld      hl,x86_io_pit_latch
        ld      de,x86_io_pit_latch+1
        ld      bc,5
        ld      (hl),a
        ldir
        ld      hl,x86_io_pit_access
        ld      de,x86_io_pit_access+1
        ld      bc,2
        ld      a,3
        ld      (hl),a
        ldir
        xor     a
        ld      hl,x86_io_pit_mode
        ld      de,x86_io_pit_mode+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      hl,x86_io_pit_bcd
        ld      de,x86_io_pit_bcd+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      hl,x86_io_pit_read_ff
        ld      de,x86_io_pit_read_ff+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      hl,x86_io_pit_write_ff
        ld      de,x86_io_pit_write_ff+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      hl,x86_io_pit_latch_valid
        ld      de,x86_io_pit_latch_valid+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      (x86_io_pit_channel),a
        ld      (x86_io_pit_byte_select),a
        ld      (x86_io_pit_read_value),a
        ld      (x86_io_pit_write_value),a
        ret

; Reset-time regression for channel 0 LSB/MSB, latch/readback and channel 1 LSB.
x86_io_pit_selftest_impl:
        call    x86_io_pit_reset_impl
        ld      hl,#0043
        ld      (x86_io_port),hl
        ld      a,#36
        call    x86_io_pit_write8
        jp      c,.pit_selftest_fail
        ld      hl,#0040
        ld      (x86_io_port),hl
        ld      a,#34
        call    x86_io_pit_write8
        jp      c,.pit_selftest_fail
        ld      a,#12
        call    x86_io_pit_write8
        jp      c,.pit_selftest_fail
        ld      a,(x86_io_pit_reload)
        cp      #34
        jp      nz,.pit_selftest_fail
        ld      a,(x86_io_pit_reload+1)
        cp      #12
        jp      nz,.pit_selftest_fail
        call    x86_io_pit_read8
        cp      #34
        jp      nz,.pit_selftest_fail
        call    x86_io_pit_read8
        cp      #12
        jp      nz,.pit_selftest_fail
        ; Latch command 00h snapshots the count without changing access mode.
        ld      hl,#0043
        ld      (x86_io_port),hl
        xor     a
        call    x86_io_pit_write8
        jp      c,.pit_selftest_fail
        ld      hl,#0040
        ld      (x86_io_port),hl
        call    x86_io_pit_read8
        cp      #34
        jp      nz,.pit_selftest_fail
        call    x86_io_pit_read8
        cp      #12
        jp      nz,.pit_selftest_fail
        ; Channel 1 LSB-only mode.
        ld      hl,#0043
        ld      (x86_io_port),hl
        ld      a,#50
        call    x86_io_pit_write8
        jp      c,.pit_selftest_fail
        ld      hl,#0041
        ld      (x86_io_port),hl
        ld      a,#AB
        call    x86_io_pit_write8
        jp      c,.pit_selftest_fail
        ld      a,(x86_io_pit_reload+2)
        cp      #AB
        jp      nz,.pit_selftest_fail
        call    x86_io_pit_read8
        cp      #AB
        jp      nz,.pit_selftest_fail
        ld      hl,x86_io_pit_selftest_pass
        jr      .pit_selftest_restore
.pit_selftest_fail:
        ld      hl,x86_io_pit_selftest_fail
.pit_selftest_restore:
        push    hl
        call    x86_io_pit_reset_impl
        ld      hl,0
        ld      (x86_io_port),hl
        pop     hl
        jp      x86_io_log_string

; -------------------------------------------------------------------------
; 8237-compatible 4-channel DMA register file and page registers.
; Transfer execution is a separate device-service task: this slice models
; guest-visible address/count/mode/mask/request/status programming only.
; -------------------------------------------------------------------------
x86_io_dma_decode:
        ld      hl,(x86_io_port)
        ld      a,h
        or      a
        jr      nz,.dma_decode_bad
        ld      a,l
        cp      #10
        jr      c,.dma_decode_controller
        cp      #80
        jr      c,.dma_decode_bad
        cp      #84
        jr      nc,.dma_decode_bad
        sub     #80
        ld      (x86_io_dma_page_index),a
        ld      a,1
        ld      (x86_io_dma_page_select),a
        or      a
        ret
.dma_decode_controller:
        ld      (x86_io_dma_port_offset),a
        xor     a
        ld      (x86_io_dma_page_select),a
        or      a
        ret
.dma_decode_bad:
        scf
        ret

x86_io_dma_read8:
        call    x86_io_dma_decode
        ret     c
        ld      a,(x86_io_dma_page_select)
        or      a
        jr      nz,.dma_read_page
        ld      a,(x86_io_dma_port_offset)
        cp      8
        jr      z,.dma_read_status
        cp      8
        jr      nc,.dma_read_open_bus
        ; 00h..07h alternate address/count registers; one shared byte pointer.
        ld      a,(x86_io_dma_port_offset)
        srl     a
        add     a,a
        ld      e,a
        ld      a,(x86_io_dma_flipflop)
        add     a,e
        ld      e,a
        ld      d,0
        ld      a,(x86_io_dma_port_offset)
        bit     0,a
        jr      nz,.dma_read_count
        ld      hl,x86_io_dma_address
        jr      .dma_read_channel
.dma_read_count:
        ld      hl,x86_io_dma_count
.dma_read_channel:
        add     hl,de
        ld      a,(hl)
        call    x86_io_dma_toggle_flipflop
        or      a
        ret
.dma_read_status:
        ; Bits 0..3 are terminal-count flags; bits 4..7 are request flags.
        ld      a,(x86_io_dma_status)
        and     #0F
        ld      b,a
        ld      a,(x86_io_dma_request)
        and     #0F
        rlca
        rlca
        rlca
        rlca
        or      b
        ld      b,a
        xor     a
        ld      (x86_io_dma_status),a
        ld      a,b
        or      a
        ret
.dma_read_open_bus:
        ld      a,#FF
        or      a
        ret
.dma_read_page:
        ld      a,(x86_io_dma_page_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_dma_page
        add     hl,de
        ld      a,(hl)
        or      a
        ret

x86_io_dma_write8:
        ld      (x86_io_dma_write_value),a
        call    x86_io_dma_decode
        ret     c
        ld      a,(x86_io_dma_page_select)
        or      a
        jp      nz,.dma_write_page
        ld      a,(x86_io_dma_port_offset)
        cp      8
        jr      c,.dma_write_channel
        cp      8
        jp      z,.dma_write_command
        cp      9
        jp      z,.dma_write_request
        cp      #0A
        jp      z,.dma_write_single_mask
        cp      #0B
        jp      z,.dma_write_mode
        cp      #0C
        jp      z,.dma_write_clear_flipflop
        cp      #0D
        jp      z,.dma_write_master_clear
        cp      #0E
        jp      z,.dma_write_clear_mask
        ; 0Fh: write all four channel mask bits.
        ld      a,(x86_io_dma_write_value)
        and     #0F
        ld      (x86_io_dma_mask),a
        or      a
        ret
.dma_write_channel:
        ld      a,(x86_io_dma_port_offset)
        srl     a
        add     a,a
        ld      e,a
        ld      a,(x86_io_dma_flipflop)
        add     a,e
        ld      e,a
        ld      d,0
        ld      a,(x86_io_dma_port_offset)
        bit     0,a
        jr      nz,.dma_write_count
        ld      hl,x86_io_dma_address
        jr      .dma_write_channel_store
.dma_write_count:
        ld      hl,x86_io_dma_count
.dma_write_channel_store:
        add     hl,de
        ld      a,(x86_io_dma_write_value)
        ld      (hl),a
        call    x86_io_dma_toggle_flipflop
        or      a
        ret
.dma_write_command:
        ld      a,(x86_io_dma_write_value)
        ld      (x86_io_dma_command),a
        or      a
        ret
.dma_write_request:
        ld      a,(x86_io_dma_write_value)
        and     3
        ld      e,a
        ld      d,0
        ld      hl,x86_io_dma_bit_masks
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_io_dma_write_value)
        bit     2,a
        jr      z,.dma_request_clear
        ld      a,(x86_io_dma_request)
        or      b
        ld      (x86_io_dma_request),a
        or      a
        ret
.dma_request_clear:
        ld      a,b
        cpl
        ld      b,a
        ld      a,(x86_io_dma_request)
        and     b
        ld      (x86_io_dma_request),a
        or      a
        ret
.dma_write_single_mask:
        ld      a,(x86_io_dma_write_value)
        and     3
        ld      e,a
        ld      d,0
        ld      hl,x86_io_dma_bit_masks
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_io_dma_write_value)
        bit     2,a
        jr      z,.dma_unmask_channel
        ld      a,(x86_io_dma_mask)
        or      b
        ld      (x86_io_dma_mask),a
        or      a
        ret
.dma_unmask_channel:
        ld      a,b
        cpl
        ld      b,a
        ld      a,(x86_io_dma_mask)
        and     b
        ld      (x86_io_dma_mask),a
        or      a
        ret
.dma_write_mode:
        ld      a,(x86_io_dma_write_value)
        ld      (x86_io_dma_mode),a
        or      a
        ret
.dma_write_clear_flipflop:
        xor     a
        ld      (x86_io_dma_flipflop),a
        or      a
        ret
.dma_write_master_clear:
        xor     a
        ld      (x86_io_dma_command),a
        ld      (x86_io_dma_status),a
        ld      (x86_io_dma_request),a
        ld      (x86_io_dma_mode),a
        ld      (x86_io_dma_temporary),a
        ld      (x86_io_dma_flipflop),a
        ld      a,#0F
        ld      (x86_io_dma_mask),a
        or      a
        ret
.dma_write_clear_mask:
        xor     a
        ld      (x86_io_dma_mask),a
        or      a
        ret
.dma_write_page:
        ld      a,(x86_io_dma_page_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_dma_page
        add     hl,de
        ld      a,(x86_io_dma_write_value)
        ld      (hl),a
        or      a
        ret

x86_io_dma_toggle_flipflop:
        ld      a,(x86_io_dma_flipflop)
        xor     1
        ld      (x86_io_dma_flipflop),a
        ret

; CPU reset clears the entire guest-visible 8237 register file and page latches.
x86_io_dma_reset_impl:
        xor     a
        ld      hl,x86_io_dma_address
        ld      de,x86_io_dma_address+1
        ld      bc,7
        ld      (hl),a
        ldir
        ld      hl,x86_io_dma_count
        ld      de,x86_io_dma_count+1
        ld      bc,7
        ld      (hl),a
        ldir
        ld      hl,x86_io_dma_page
        ld      de,x86_io_dma_page+1
        ld      bc,3
        ld      (hl),a
        ldir
        ld      (x86_io_dma_command),a
        ld      (x86_io_dma_status),a
        ld      (x86_io_dma_request),a
        ld      (x86_io_dma_mode),a
        ld      (x86_io_dma_temporary),a
        ld      (x86_io_dma_flipflop),a
        ld      (x86_io_dma_page_select),a
        ld      (x86_io_dma_page_index),a
        ld      (x86_io_dma_port_offset),a
        ld      a,#0F
        ld      (x86_io_dma_mask),a
        ret

; Register-file regression: address/count low-high flip-flop, page registers,
; single-channel mask commands and master-clear reset behavior.
x86_io_dma_selftest_impl:
        ; Clear byte pointer, then program channel 0 address=1234h.
        ld      hl,#000C
        ld      (x86_io_port),hl
        xor     a
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      hl,#0000
        ld      (x86_io_port),hl
        ld      a,#34
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,#12
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_io_dma_address)
        cp      #34
        jp      nz,.dma_selftest_fail
        ld      a,(x86_io_dma_address+1)
        cp      #12
        jp      nz,.dma_selftest_fail
        ; Read back the same low/high sequence.
        ld      a,(x86_io_dma_flipflop)
        or      a
        jp      nz,.dma_selftest_fail
        call    x86_io_dma_read8
        cp      #34
        jp      nz,.dma_selftest_fail
        call    x86_io_dma_read8
        cp      #12
        jp      nz,.dma_selftest_fail
        ; Channel 0 count=5678h.
        ld      hl,#0001
        ld      (x86_io_port),hl
        ld      a,#78
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,#56
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_io_dma_count)
        cp      #78
        jp      nz,.dma_selftest_fail
        ld      a,(x86_io_dma_count+1)
        cp      #56
        jp      nz,.dma_selftest_fail
        ; DMA page register for channel 1 is port 81h.
        ld      hl,#0081
        ld      (x86_io_port),hl
        ld      a,#A5
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        call    x86_io_dma_read8
        cp      #A5
        jp      nz,.dma_selftest_fail
        ; Clear all masks, mask channel 2, then unmask channel 2.
        ld      hl,#000E
        ld      (x86_io_port),hl
        xor     a
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      hl,#000A
        ld      (x86_io_port),hl
        ld      a,#06
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_io_dma_mask)
        cp      4
        jp      nz,.dma_selftest_fail
        ld      a,#02
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_io_dma_mask)
        or      a
        jp      nz,.dma_selftest_fail
        ; Master clear restores mask=0Fh and byte pointer=0.
        ld      hl,#000D
        ld      (x86_io_port),hl
        xor     a
        call    x86_io_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_io_dma_mask)
        cp      #0F
        jp      nz,.dma_selftest_fail
        ld      a,(x86_io_dma_flipflop)
        or      a
        jp      nz,.dma_selftest_fail
        ld      hl,x86_io_dma_selftest_pass
        jr      .dma_selftest_restore
.dma_selftest_fail:
        ld      hl,x86_io_dma_selftest_fail
.dma_selftest_restore:
        push    hl
        call    x86_io_dma_reset_impl
        ld      hl,0
        ld      (x86_io_port),hl
        pop     hl
        jp      x86_io_log_string

; -------------------------------------------------------------------------
; 8259A master PIC register interface (ports 0020h/0021h).
; This is a register-level model: ICW1..4 sequencing, IMR, IRR/ISR reads,
; OCW3 read selection and EOI. IRQ producers and CPU INTA/acknowledge are
; deliberately separate; no timer/keyboard IRQ is claimed at this stage.
; Carry clear means the port was handled; carry set means not PIC decode.
; -------------------------------------------------------------------------
x86_io_pic_decode:
        ld      hl,(x86_io_port)
        ld      de,#0020
        or      a
        sbc     hl,de
        ld      a,h
        or      a
        jr      nz,.pic_decode_bad
        ld      a,l
        cp      2
        jr      nc,.pic_decode_bad
        or      a
        ret
.pic_decode_bad:
        scf
        ret

x86_io_pic_read8:
        call    x86_io_pic_decode
        ret     c
        or      a
        jr      nz,.pic_read_imr
        ld      a,(x86_io_pic_read_isr)
        or      a
        jr      nz,.pic_read_isr
        ld      a,(x86_io_pic_irr)
        or      a
        ret
.pic_read_isr:
        ld      a,(x86_io_pic_isr)
        or      a
        ret
.pic_read_imr:
        ld      a,(x86_io_pic_imr)
        or      a
        ret

; Request an edge-triggered master-PIC IRQ. A=IRQ number 0..7.
x86_io_pic_raise_impl:
        cp      8
        jr      nc,.pic_raise_bad
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pic_bit_masks
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_io_pic_irr)
        or      b
        ld      (x86_io_pic_irr),a
        call    x86_io_pic_update_pending
        or      a
        ret
.pic_raise_bad:
        scf
        ret

; Find the highest-priority eligible request. Returns A=IRQ 0..7,
; carry set when no unmasked request can currently be delivered.
x86_io_pic_find_pending:
        ld      a,(x86_io_pic_irr)
        ld      b,a
        ld      a,(x86_io_pic_imr)
        cpl
        and     b
        ld      (x86_io_pic_candidate),a
        ; Fixed-priority nesting: only IRQs above the highest active ISR
        ; priority may pre-empt an in-service interrupt.
        ld      a,(x86_io_pic_isr)
        or      a
        jr      z,.pic_find_scan
        ld      b,a
        ld      c,0
.pic_find_isr_loop:
        srl     b
        jr      c,.pic_find_isr_found
        inc     c
        jr      .pic_find_isr_loop
.pic_find_isr_found:
        ld      e,c
        ld      d,0
        ld      hl,x86_io_pic_higher_masks
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_io_pic_candidate)
        and     b
        ld      (x86_io_pic_candidate),a
.pic_find_scan:
        ld      a,(x86_io_pic_candidate)
        or      a
        jr      z,.pic_find_none
        ld      b,a
        ld      c,0
.pic_find_scan_loop:
        srl     b
        jr      c,.pic_find_found
        inc     c
        jr      .pic_find_scan_loop
.pic_find_found:
        ld      a,c
        or      a
        ret
.pic_find_none:
        scf
        ret

; Recalculate the CPU's maskable-interrupt pending latch after IRR/IMR/ISR
; changes. All maskable IRQ producers enter through this PIC model.
x86_io_pic_update_pending:
        call    x86_io_pic_find_pending
        jr      c,.pic_update_none
        ld      e,a
        ld      a,(x86_io_pic_vector_base)
        add     a,e
        ld      (x86_irq_vector),a
        ld      a,1
        ld      (x86_pending_irq),a
        or      a
        ret
.pic_update_none:
        xor     a
        ld      (x86_pending_irq),a
        or      a
        ret

; 8086 interrupt boundary calls this after seeing x86_pending_irq and IF=1.
; A=vector on acknowledge; carry set means no PIC request was eligible.
x86_io_pic_ack_impl:
        call    x86_io_pic_find_pending
        ret     c
        ld      (x86_io_pic_selected_irq),a
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pic_bit_masks
        add     hl,de
        ld      a,(hl)
        ld      (x86_io_pic_selected_mask),a
        ld      a,(x86_io_pic_irr)
        ld      b,a
        ld      a,(x86_io_pic_selected_mask)
        cpl
        and     b
        ld      (x86_io_pic_irr),a
        ld      a,(x86_io_pic_isr)
        ld      b,a
        ld      a,(x86_io_pic_selected_mask)
        or      b
        ld      (x86_io_pic_isr),a
        ld      a,(x86_io_pic_vector_base)
        ld      b,a
        ld      a,(x86_io_pic_selected_irq)
        add     a,b
        ld      (x86_io_pic_vector_result),a
        call    x86_io_pic_update_pending
        ld      a,(x86_io_pic_vector_result)
        or      a
        ret

; A=value. The original byte is retained because decode helpers return offset.
x86_io_pic_write8:
        ld      (x86_io_pic_write_value),a
        call    x86_io_pic_decode
        ret     c
        or      a
        jp      nz,.pic_write_data
        ld      a,(x86_io_pic_write_value)
        bit     4,a
        jr      z,.pic_write_command
        ; ICW1 starts a fresh initialization sequence.
        xor     a
        ld      (x86_io_pic_irr),a
        ld      (x86_io_pic_isr),a
        ld      a,(x86_io_pic_write_value)
        and     1
        ld      (x86_io_pic_need_icw4),a
        ld      a,(x86_io_pic_write_value)
        and     2
        ld      (x86_io_pic_single),a
        ld      a,1
        ld      (x86_io_pic_init_state),a
        jp      x86_io_pic_update_pending
.pic_write_command:
        ld      a,(x86_io_pic_write_value)
        bit     3,a
        jr      z,.pic_write_ocw2
        ; OCW3: 0Bh selects ISR, 0Ah selects IRR for command-port reads.
        bit     1,a
        jr      z,.pic_write_command_done
        ld      a,(x86_io_pic_write_value)
        and     1
        ld      (x86_io_pic_read_isr),a
.pic_write_command_done:
        or      a
        ret
.pic_write_ocw2:
        ld      a,(x86_io_pic_write_value)
        bit     5,a
        jr      z,.pic_write_command_done
        ; EOI. Specific EOI uses bits 2..0; non-specific EOI clears
        ; the highest-priority in-service bit (IRQ0 before IRQ1..IRQ7).
        bit     6,a
        jr      nz,.pic_specific_eoi
        ld      a,(x86_io_pic_isr)
        or      a
        jr      z,.pic_write_command_done
        ld      b,a
        ld      c,0
.pic_eoi_find:
        srl     b
        jr      c,.pic_eoi_clear
        inc     c
        jr      .pic_eoi_find
.pic_eoi_clear:
        ld      a,c
        jr      .pic_eoi_mask
.pic_specific_eoi:
        ld      a,(x86_io_pic_write_value)
        and     7
.pic_eoi_mask:
        ld      e,a
        ld      d,0
        ld      hl,x86_io_pic_bit_masks
        add     hl,de
        ld      a,(hl)
        cpl
        ld      b,a
        ld      a,(x86_io_pic_isr)
        and     b
        ld      (x86_io_pic_isr),a
        ; Acknowledged keyboard bytes are consumed one at a time. If more
        ; remain in the FIFO, re-latch IRQ1 after EOI.
        ld      a,(x86_io_keyboard_count)
        or      a
        jr      z,.pic_eoi_recalculate
        ld      a,1
        call    x86_io_pic_raise_impl
        or      a
        ret
.pic_eoi_recalculate:
        jp      x86_io_pic_update_pending

.pic_write_data:
        ld      a,(x86_io_pic_init_state)
        or      a
        jr      z,.pic_write_imr
        cp      1
        jr      z,.pic_write_icw2
        cp      2
        jr      z,.pic_write_icw3
        ; ICW4 is accepted for state 3; mode bits are not otherwise needed
        ; by the current XT master-PIC profile.
        xor     a
        ld      (x86_io_pic_init_state),a
        or      a
        ret
.pic_write_icw2:
        ld      a,(x86_io_pic_write_value)
        and     #F8
        ld      (x86_io_pic_vector_base),a
        ld      a,(x86_io_pic_single)
        or      a
        jr      nz,.pic_icw2_after
        ld      a,2
        ld      (x86_io_pic_init_state),a
        or      a
        ret
.pic_icw2_after:
        ld      a,(x86_io_pic_need_icw4)
        or      a
        jr      z,.pic_init_done
        ld      a,3
        ld      (x86_io_pic_init_state),a
        or      a
        ret
.pic_write_icw3:
        ld      a,(x86_io_pic_need_icw4)
        or      a
        jr      z,.pic_init_done
        ld      a,3
        ld      (x86_io_pic_init_state),a
        or      a
        ret
.pic_init_done:
        xor     a
        ld      (x86_io_pic_init_state),a
        or      a
        ret
.pic_write_imr:
        ld      a,(x86_io_pic_write_value)
        ld      (x86_io_pic_imr),a
        jp      x86_io_pic_update_pending

; Decode ports 0060h..0063h. Returns A=offset 0..3, carry if unmatched.
x86_io_ppi_decode:
        ld      hl,(x86_io_port)
        ld      de,#0060
        or      a
        sbc     hl,de
        ld      a,h
        or      a
        jr      nz,.ppi_decode_bad
        ld      a,l
        cp      4
        jr      nc,.ppi_decode_bad
        or      a
        ret
.ppi_decode_bad:
        scf
        ret

; Write one byte to the guest I/O bus. A=value.
x86_io_write8_impl:
        ld      hl,(x86_io_count_out)
        inc     hl
        ld      (x86_io_count_out),hl
        jp      x86_io_write8_impl_device

; Internal byte write. Does not change the operation counter.
; A=value.
x86_io_write8_impl_device:
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        jr      nz,.io_write8_ppi
        ld      (x86_io_test_latch),a
        ret
.io_write8_ppi:
        ld      (x86_io_write_value),a
        call    x86_io_dma_write8
        ret     nc
        ld      a,(x86_io_write_value)
        call    x86_io_pit_write8
        ret     nc
        ld      a,(x86_io_write_value)
        call    x86_io_pic_write8
        ret     nc
        ld      a,(x86_io_write_value)
        jp      x86_io_ppi_write8

; Write one byte to PPI 8255. Carry set means port is not in PPI decode.
; A=value.
x86_io_ppi_write8:
        ld      (x86_io_ppi_write_value),a
        call    x86_io_ppi_decode
        ret     c
        cp      0
        jr      z,.ppi_write_a
        cp      1
        jr      z,.ppi_write_b
        cp      2
        jr      z,.ppi_write_c
        jr      .ppi_write_control
.ppi_write_a:
        ; XT profile uses port A as keyboard input; output writes are ignored.
        or      a
        ret
.ppi_write_b:
        ; XT keyboard reset is triggered by a low-to-high transition on PB6.
        ld      a,(x86_io_ppi_pb)
        and     #40
        ld      b,a
        ld      a,(x86_io_ppi_write_value)
        ld      c,a
        and     #40
        jr      z,.ppi_pb_store
        ld      a,b
        or      a
        jr      nz,.ppi_pb_store
        call    x86_io_keyboard_reset_impl
.ppi_pb_store:
        ld      a,c
        ld      (x86_io_ppi_pb),a
        bit     7,a
        jr      z,.ppi_pb_done
        xor     a
        ld      (x86_io_keyboard_last),a
.ppi_pb_done:
        or      a
        ret
.ppi_write_c:
        ld      a,(x86_io_ppi_write_value)
        ld      (x86_io_ppi_pc),a
        or      a
        ret
.ppi_write_control:
        ld      a,(x86_io_ppi_write_value)
        bit     7,a
        jr      z,.ppi_bit_set_reset
        ; Mode-set operation. XT BIOS selects mode 0 (control word 99h).
        ld      (x86_io_ppi_control),a
        xor     a
        ld      (x86_io_ppi_pb),a
        ld      (x86_io_ppi_pc),a
        or      a
        ret
.ppi_bit_set_reset:
        ; Bit set/reset: D3..D1 select PC bit, D0 selects set/reset.
        ld      b,a
        and     #0E
        srl     a
        ld      e,a
        ld      d,0
        ld      hl,x86_io_ppi_pc_masks
        add     hl,de
        ld      a,(hl)
        ld      c,a
        ld      a,(x86_io_ppi_pc)
        bit     0,b
        jr      z,.ppi_bsr_clear
        or      c
        jr      .ppi_bsr_store
.ppi_bsr_clear:
        ld      a,c
        cpl
        ld      c,a
        ld      a,(x86_io_ppi_pc)
        and     c
.ppi_bsr_store:
        ld      (x86_io_ppi_pc),a
        or      a
        ret

; Read a 16-bit value. PCem io.c fallback for 8-bit devices reads port and
; port+1; the 00E0h test device retains its explicit 16-bit latch behavior.
x86_io_read16_impl:
        ld      hl,(x86_io_count_in)
        inc     hl
        ld      (x86_io_count_in),hl
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        jr      nz,.io_read16_split
        ld      hl,(x86_io_test_latch)
        ret
.io_read16_split:
        ld      hl,(x86_io_port)
        ld      (x86_io_saved_port),hl
        call    x86_io_read8_impl_device
        ld      (x86_io_word_low),a
        ld      hl,(x86_io_saved_port)
        inc     hl
        ld      (x86_io_port),hl
        call    x86_io_read8_impl_device
        ld      (x86_io_word_high),a
        ld      hl,(x86_io_saved_port)
        ld      (x86_io_port),hl
        ld      a,(x86_io_word_low)
        ld      l,a
        ld      a,(x86_io_word_high)
        ld      h,a
        ret

; Write a 16-bit value. The 00E0h test device has a native word latch;
; other ports use PCem's byte fallback at port and port+1.
x86_io_write16_impl:
        ld      (x86_io_word_value),hl
        ld      hl,(x86_io_count_out)
        inc     hl
        ld      (x86_io_count_out),hl
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        jr      nz,.io_write16_split
        ld      hl,(x86_io_word_value)
        ld      (x86_io_test_latch),hl
        ret
.io_write16_split:
        ld      hl,(x86_io_port)
        ld      (x86_io_saved_port),hl
        ld      a,(x86_io_word_value)
        call    x86_io_write8_impl_device
        ld      hl,(x86_io_saved_port)
        inc     hl
        ld      (x86_io_port),hl
        ld      a,(x86_io_word_value+1)
        call    x86_io_write8_impl_device
        ld      hl,(x86_io_saved_port)
        ld      (x86_io_port),hl
        ret

; One-shot BIOS watchdog diagnostic: dump the 16 bytes surrounding the
; current DS:SI table cursor. This reads guest memory through the normal
; physical mapper and never changes guest registers or the memory map contract.
x86_io_dump_bios_table_impl:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl,x86_io_bios_table_prefix
        call    x86_io_log_string
        ld      hl,(x86_reg_ds)
        call    x86_io_log_hex16
        ld      a,':'
        call    x86_io_log_char
        ld      hl,(x86_reg_si)
        call    x86_io_log_hex16
        ld      hl,x86_io_bios_table_data_text
        call    x86_io_log_string
        ; The watchdog stops immediately after LODSB at E06E. Include the
        ; byte just consumed by starting at SI-1, then show the next 15 bytes.
        ld      hl,(x86_reg_si)
        dec     hl
        ld      (x86_io_diag_offset),hl
        ld      a,16
        ld      (x86_io_diag_remaining),a
.bios_table_dump_loop:
        ld      hl,(x86_reg_ds)
        ld      de,(x86_io_diag_offset)
        call    x86_cpu_calc_phys
        call    x86_guest_mem_read8
        jr      c,.bios_table_dump_fault
        call    x86_io_log_hex8
        jr      .bios_table_dump_separator
.bios_table_dump_fault:
        ld      a,'?'
        call    x86_io_log_char
        ld      a,'?'
        call    x86_io_log_char
.bios_table_dump_separator:
        ld      a,' '
        call    x86_io_log_char
        ld      hl,(x86_io_diag_offset)
        inc     hl
        ld      (x86_io_diag_offset),hl
        ld      a,(x86_io_diag_remaining)
        dec     a
        ld      (x86_io_diag_remaining),a
        jr      nz,.bios_table_dump_loop
        ld      a,13
        call    x86_io_log_char
        ld      a,10
        call    x86_io_log_char
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Diagnostic output only: guest ports remain software-modeled.
; Format: [IO] IN8 P=03DA V=FF @F000:E05B
x86_io_log_access_impl:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl,x86_io_log_prefix
        call    x86_io_log_string
        ld      a,(x86_io_log_direction)
        or      a
        jr      nz,.log_out
        ld      hl,x86_io_log_in
        call    x86_io_log_string
        jr      .log_width
.log_out:
        ld      hl,x86_io_log_out
        call    x86_io_log_string
.log_width:
        ld      a,(x86_io_log_width)
        or      a
        jr      nz,.log_word_width
        ld      a,'8'
        call    x86_io_log_char
        jr      .log_port
.log_word_width:
        ld      a,'1'
        call    x86_io_log_char
        ld      a,'6'
        call    x86_io_log_char
.log_port:
        ld      hl,x86_io_log_port_text
        call    x86_io_log_string
        ld      hl,(x86_io_port)
        call    x86_io_log_hex16
        ld      hl,x86_io_log_value_text
        call    x86_io_log_string
        ld      a,(x86_io_log_width)
        or      a
        jr      z,.log_byte_value
        ld      hl,(x86_io_log_value)
        call    x86_io_log_hex16
        jr      .log_location
.log_byte_value:
        ld      a,(x86_io_log_value)
        call    x86_io_log_hex8
.log_location:
        ld      hl,x86_io_log_at_text
        call    x86_io_log_string
        ld      hl,(x86_reg_cs)
        call    x86_io_log_hex16
        ld      a,':'
        call    x86_io_log_char
        ld      hl,(x86_exec_instruction_start_ip)
        call    x86_io_log_hex16
        ld      a,13
        call    x86_io_log_char
        ld      a,10
        call    x86_io_log_char
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Emit on the full 00EF diagnostic port, preserving BC and A.
x86_io_log_char:
        push    bc
        ld      bc,#00EF
        out     (c),a
        pop     bc
        ret

; HL points to a zero-terminated diagnostic string.
x86_io_log_string:
        ld      a,(hl)
        or      a
        ret     z
        call    x86_io_log_char
        inc     hl
        jr      x86_io_log_string

; HL=word; emit four uppercase hexadecimal digits.
x86_io_log_hex16:
        ld      a,h
        call    x86_io_log_hex8
        ld      a,l
        jp      x86_io_log_hex8

; A=byte; emit two uppercase hexadecimal digits.
x86_io_log_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    x86_io_log_nibble
        pop     af
        and     #0F
        jp      x86_io_log_nibble

x86_io_log_nibble:
        and     #0F
        add     a,'0'
        cp      '9'+1
        jr      c,.log_hex_emit
        add     a,7
.log_hex_emit:
        call    x86_io_log_char
        ret

x86_io_ppi_pc_masks: db #01,#02,#04,#08,#10,#20,#40,#80
x86_io_log_prefix:    db "[IO] ",0
x86_io_log_in:        db "IN",0
x86_io_log_out:       db "OUT",0
x86_io_log_port_text: db " P=",0
x86_io_log_value_text: db " V=",0
x86_io_log_at_text:  db " @",0
x86_io_bios_table_prefix: db "[BIOS TABLE] DS:SI=",0
x86_io_bios_table_data_text: db " DATA=",0
x86_io_pic_selftest_pass: db "[NGS] X86 PIC REGISTER SELFTEST PASS",13,10,0
x86_io_pic_selftest_fail: db "[NGS] X86 PIC REGISTER SELFTEST FAIL",13,10,0

x86_io_port: dw 0
x86_io_diag_offset: dw 0
x86_io_diag_remaining: db 0
x86_io_test_latch: dw 0
x86_io_log_value: dw 0
x86_io_log_direction: db 0
x86_io_log_width: db 0
x86_io_saved_port: dw 0
x86_io_word_value: dw 0
x86_io_word_low: db 0
x86_io_word_high: db 0

x86_io_ppi_pb: db #40
x86_io_ppi_pc: db 0
x86_io_ppi_control: db #9B
x86_io_ppi_write_value: db 0
x86_io_write_value: db 0

; 8259A master PIC state. IRQ generation/CPU acknowledge are separate tasks.
x86_io_pic_irr: db 0
x86_io_pic_isr: db 0
x86_io_pic_imr: db #FF
x86_io_pic_vector_base: db #08
x86_io_pic_init_state: db 0
x86_io_pic_need_icw4: db 0
x86_io_pic_single: db 0
x86_io_pic_read_isr: db 0
x86_io_pic_write_value: db 0
x86_io_pic_candidate: db 0
x86_io_pic_selected_irq: db 0
x86_io_pic_selected_mask: db 0
x86_io_pic_vector_result: db 0
x86_io_pic_bit_masks: db #01,#02,#04,#08,#10,#20,#40,#80
x86_io_pic_higher_masks: db #00,#01,#03,#07,#0F,#1F,#3F,#7F

; 8237 register state: four address/count pairs, page latches and controller.
x86_io_dma_address: defs 8,0
x86_io_dma_count: defs 8,0
x86_io_dma_page: defs 4,0
x86_io_dma_command: db 0
x86_io_dma_status: db 0
x86_io_dma_request: db 0
x86_io_dma_mask: db #0F
x86_io_dma_mode: db 0
x86_io_dma_temporary: db 0
x86_io_dma_flipflop: db 0
x86_io_dma_page_select: db 0
x86_io_dma_page_index: db 0
x86_io_dma_port_offset: db 0
x86_io_dma_write_value: db 0
x86_io_dma_bit_masks: db #01,#02,#04,#08
x86_io_dma_selftest_pass: db "[NGS] X86 DMA REGISTER SELFTEST PASS",13,10,0
x86_io_pit_reload: defs 6,0
x86_io_pit_latch: defs 6,0
x86_io_pit_access: db 3,3,3
x86_io_pit_mode: db 0,0,0
x86_io_pit_bcd: db 0,0,0
x86_io_pit_read_ff: db 0,0,0
x86_io_pit_write_ff: db 0,0,0
x86_io_pit_latch_valid: db 0,0,0
x86_io_pit_channel: db 0
x86_io_pit_byte_select: db 0
x86_io_pit_read_value: db 0
x86_io_pit_write_value: db 0
x86_io_pit_selftest_pass: db "[NGS] X86 PIT REGISTER SELFTEST PASS",13,10,0
x86_io_pit_selftest_fail: db "[NGS] X86 PIT REGISTER SELFTEST FAIL",13,10,0
x86_io_dma_selftest_fail: db "[NGS] X86 DMA REGISTER SELFTEST FAIL",13,10,0

; Deterministic XT profile switch input (generic XT/no-FPU default). This
; value remains a profile parameter until the ATM-PC board switches are set.
x86_io_ppi_port_c_input: db #0D

x86_io_keyboard_fifo: defs 16,0
x86_io_keyboard_head: db 0
x86_io_keyboard_tail: db 0
x86_io_keyboard_count: db 0
x86_io_keyboard_last: db 0

x86_io_count_in:  dw 0
x86_io_count_out: dw 0
