; PROJECT126 — virtual 8086 I/O port bus.

; Diagnostic policy: normal builds suppress per-IN/OUT trace. Set to 1
; temporarily when investigating a specific guest port sequence.
P126_DEBUG_IO_TRACE EQU 0
; Guest I/O devices are software models on NeoGS. No guest port number is
; ever issued as a physical NeoGS/Z80 I/O operation.
;
; Implemented:
;   0000h-000Fh, 0080h-0083h: 8237 address/count, controller and page registers.
;   0020h-0021h: 8259A master PIC register model and CPU acknowledge path.
;   0040h-0043h: 8253 channel programming, latches and static readback.
;   0060h-0063h: PCem-compatible XT keyboard/PPI port handler.
;   00E0h: retained 16-bit diagnostic test latch.
;   Keyboard FIFO is idle after reset; XT BAT response AAh is queued only
;   when PB6 has a low-to-high edge. ATM keyboard input remains a future IPC
;   producer; no physical NeoGS I/O is involved.
;   DMA transfer engine and PIT clock/IRQ0 are separate services.
;
; PCem keyboard_xt.c owns the observable 60h-63h handler:
;   60h = keyboard data latch/FIFO, 61h = XT system-control PB,
;   62h = board configuration/speaker status, 63h = open bus (FFh).
; PCem ppi_reset() initializes PA=00h/PB=40h, while keyboard_xt.pb itself
; starts at 00h. The XT handler reads its own PB latch, so this model keeps
; the keyboard PB latch at 00h until the guest writes port 61h.

x86_io_reset_impl:
        ld      hl,0
        ld      (x86_io_count_in),hl
        ld      (x86_io_count_out),hl
        ld      (x86_io_pit_out42_count),hl
        ld      (x86_io_pit_out43_count),hl
        ld      (x86_io_ppi_out61_count),hl
        ld      (x86_io_last_out_port),hl
        xor     a
        ld      (x86_io_last_out_value),a
        ld      (x86_io_test_latch),hl
        xor     a
        ld      (x86_io_keyboard_head),a
        ld      (x86_io_keyboard_tail),a
        ld      (x86_io_keyboard_count),a
        ld      (x86_io_keyboard_last),a
        ; keyboard_xt.pb is zero-initialized separately from ppi.pb=40h.
        xor     a
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
        call    x86_dev_reset
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

; Reset XT keyboard input state and queue BAT completion. PCem queues
; the byte first; keyboard_xt_poll() raises IRQ1 asynchronously afterwards.
x86_io_keyboard_reset_impl:
        xor     a
        ld      (x86_io_keyboard_head),a
        ld      (x86_io_keyboard_tail),a
        ld      (x86_io_keyboard_count),a
        ld      (x86_io_keyboard_last),a
        ld      a,#AA
        call    x86_io_keyboard_push_impl
        ret     c
        ; Defer IRQ1 until the guest releases PB7 acknowledge.
        ld      a,(x86_io_pic_irr)
        and     #FD
        ld      (x86_io_pic_irr),a
        jp      x86_io_pic_update_pending

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
        ld      hl,(x86_io_port)
        call    x86_dev_read8
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
        ; PCem keyboard_xt_read() generic XT profile:
        ; PB3 selects video identification (CGA=6), otherwise FPU
        ; identification (no FPU=Dh). Bit 5 reflects an enabled speaker.
        ld      a,(x86_io_ppi_pb)
        bit     3,a
        jr      z,.ppi_pc_no_video_id
        ld      a,#06
        jr      .ppi_pc_speaker
.ppi_pc_no_video_id:
        ld      a,#0D
.ppi_pc_speaker:
        ; PCem's bit 5 is ppispeakon, driven by PIT channel-2 OUT,
        ; not by PB0/PB1. Reflect the emulated OUT2 state.
        ld      b,a
        ld      a,(x86_dev_pit_out2)
        or      a
        ld      a,b
        jr      z,.ppi_pc_return
        or      #20
.ppi_pc_return:
        or      a
        ret

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
        ld      (x86_io_last_out_value),a
        ld      hl,(x86_io_port)
        ld      (x86_io_last_out_port),hl
        ld      de,#0042
        or      a
        sbc     hl,de
        jr      nz,.check_pit_control_out
        ld      hl,(x86_io_pit_out42_count)
        inc     hl
        ld      (x86_io_pit_out42_count),hl
        jr      .restore_out_value
.check_pit_control_out:
        ld      hl,(x86_io_port)
        ld      de,#0043
        or      a
        sbc     hl,de
        jr      nz,.check_ppi_pb_out
        ld      hl,(x86_io_pit_out43_count)
        inc     hl
        ld      (x86_io_pit_out43_count),hl
        jr      .restore_out_value
.check_ppi_pb_out:
        ld      hl,(x86_io_port)
        ld      de,#0061
        or      a
        sbc     hl,de
        jr      nz,.restore_out_value
        ld      hl,(x86_io_ppi_out61_count)
        inc     hl
        ld      (x86_io_ppi_out61_count),hl
.restore_out_value:
        ld      a,(x86_io_last_out_value)
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
        ld      hl,(x86_io_port)
        ld      a,(x86_io_write_value)
        call    x86_dev_write8
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
        ; Match PCem keyboard_xt_write(61h): detect PB6 rising edge,
        ; store the keyboard PB latch, then process PB7 acknowledge.
        ld      a,(x86_io_ppi_pb)
        ld      b,a
        and     #40
        ld      a,(x86_io_ppi_write_value)
        ld      c,a
        and     #40
        jr      z,.ppi_pb_store
        ld      a,b
        and     #40
        jr      nz,.ppi_pb_store
        push    bc
        call    x86_io_keyboard_reset_impl
        pop     bc
.ppi_pb_store:
        ld      a,c
        ld      (x86_io_ppi_pb),a
        ; PB0 is PIT channel-2 GATE. Route the pin update through the
        ; existing resident X86DEV write API (port 61h software model).
        push    bc
        ld      hl,#0061
        ld      a,c
        call    x86_dev_write8
        pop     bc
        ld      a,c
        bit     7,a
        jr      z,.ppi_pb_ack_released
        ; PB7 acknowledges the current data latch/IRQ but does not discard
        ; queued bytes: PCem's keyboard timer may deliver BAT after ACK.
        xor     a
        ld      (x86_io_keyboard_last),a
        ld      a,(x86_io_pic_irr)
        and     #FD
        ld      (x86_io_pic_irr),a
        jp      x86_io_pic_update_pending
.ppi_pb_ack_released:
        ; Releasing PB7 lets the queued XT BAT byte become IRQ1-visible.
        bit     7,b
        jr      z,.ppi_pb_done
        ld      a,(x86_io_keyboard_count)
        or      a
        jr      z,.ppi_pb_done
        ld      a,1
        jp      x86_io_pic_raise_impl
.ppi_pb_done:
        or      a
        ret
.ppi_write_c:
        ; PCem XT keyboard handler ignores writes to port 62h.
        or      a
        ret
.ppi_write_control:
        ; PCem XT keyboard handler ignores writes to port 63h.
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

; One-shot BIOS watchdog diagnostic: dump 20 bytes beginning at DS:SI-1,
; including the byte consumed by the last LODSB and the following table data.
; This reads guest memory through the normal mapper without changing guest state.
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
        ; Start at SI-1 so the dump includes the last byte consumed by LODSB.
        ; This is deliberately the live DS:SI source, not a guessed ROM offset.
        ld      hl,(x86_reg_si)
        dec     hl
        ld      (x86_io_diag_offset),hl
        ld      a,20
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
        ; Per-IN/OUT trace is intentionally compiled out in normal builds.
        ; Keep this entry point as a no-op so callers need no conditional code.
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

x86_io_log_prefix:    db "[IO] ",0
x86_io_log_in:        db "IN",0
x86_io_log_out:       db "OUT",0
x86_io_log_port_text: db " P=",0
x86_io_log_value_text: db " V=",0
x86_io_log_at_text:  db " @",0
x86_io_bios_table_prefix: db "[BIOS TABLE] CURSOR=",0
x86_io_bios_table_data_text: db " DATA@DS:SI-1=",0
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

x86_io_ppi_pb: db 0
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
x86_io_keyboard_fifo: defs 16,0
x86_io_keyboard_head: db 0
x86_io_keyboard_tail: db 0
x86_io_keyboard_count: db 0
x86_io_keyboard_last: db 0

x86_io_snapshot_counters_impl:
        ld      hl,(x86_io_count_in)
        ld      (x86_bios_trace_io_in_snapshot),hl
        ld      hl,(x86_io_count_out)
        ld      (x86_bios_trace_io_out_snapshot),hl
        ld      hl,(x86_io_port)
        ld      (x86_bios_trace_io_port_snapshot),hl
        ld      hl,(x86_io_last_out_port)
        ld      (x86_bios_trace_io_last_out_port_snapshot),hl
        ld      a,(x86_io_last_out_value)
        ld      (x86_bios_trace_io_last_out_value_snapshot),a
        ld      hl,(x86_io_pit_out42_count)
        ld      (x86_bios_trace_io_out42_snapshot),hl
        ld      hl,(x86_io_pit_out43_count)
        ld      (x86_bios_trace_io_out43_snapshot),hl
        ld      hl,(x86_io_ppi_out61_count)
        ld      (x86_bios_trace_io_out61_snapshot),hl
        ; X86IO is mapped on page04. Nested gate logs X86DEV page06.
        ld      a,P126_NGS_X86DEV_OVERLAY_SELECTOR
        ld      (p126_overlay_request_selector),a
        ld      ix,x86_dev_pit_log_state_impl
        call    p126_overlay_call
        ret

x86_io_count_in:  dw 0
x86_io_count_out: dw 0
x86_io_pit_out42_count: dw 0
x86_io_pit_out43_count: dw 0
x86_io_ppi_out61_count: dw 0
x86_io_last_out_port: dw 0
x86_io_last_out_value: db 0
