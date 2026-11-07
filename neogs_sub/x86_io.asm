; PROJECT126 — virtual 8086 I/O port bus.
; Guest I/O devices are software models on NeoGS. No guest port number is
; ever issued as a physical NeoGS/Z80 I/O operation.
;
; Implemented:
;   00E0h: retained 16-bit diagnostic test latch.
;   0060h-0063h: initial XT-compatible 8255 PPI / keyboard interface.
;   x86_io_keyboard_push: host/IPC producer API for XT scan-code bytes.
;
; PPI compatibility slice:
;   60h = port A / keyboard data (FIFO consumer when configured input).
;   61h = port B / system control; bit-6 rising edge resets XT keyboard,
;         bit 7 acknowledges/clears the current keyboard data latch.
;   62h = port C input/output composition.
;   63h = mode-set and bit-set/reset control register (mode 0 implemented).
;   PPI reset defaults follow PCem/ppi.c: PA=00h, PB=40h.
;
; Keyboard bytes are queued here only. ATM input delivery and PIC IRQ1
; signaling are separate services and are not claimed implemented yet.

x86_io_reset:
        ld      hl,0
        ld      (x86_io_count_in),hl
        ld      (x86_io_count_out),hl
        ld      (x86_io_test_latch),hl
        ld      (x86_io_keyboard_head),hl
        xor     a
        ld      (x86_io_keyboard_tail),a
        ld      (x86_io_keyboard_count),a
        ld      (x86_io_keyboard_last),a
        ld      (x86_io_keyboard_overflow),a
        ld      (x86_io_ppi_pa),a
        ld      (x86_io_ppi_pc),a
        ld      (x86_io_ppi_control),#9B
        ld      (x86_io_ppi_pb),#40
        ret

; A=XT keyboard scan-code byte. Carry set means FIFO full (byte rejected).
; This is the software input-service API; the caller is the future IPC
; keyboard event handler, never a physical NeoGS port operation.
x86_io_keyboard_push:
        ld      (x86_io_keyboard_push_value),a
        ld      a,(x86_io_keyboard_count)
        cp      16
        jr      nc,.keyboard_push_full
        ld      a,(x86_io_keyboard_tail)
        ld      e,a
        ld      d,0
        ld      hl,x86_io_keyboard_fifo
        add     hl,de
        ld      a,(x86_io_keyboard_push_value)
        ld      (hl),a
        ld      a,(x86_io_keyboard_tail)
        inc     a
        and     #0F
        ld      (x86_io_keyboard_tail),a
        ld      a,(x86_io_keyboard_count)
        inc     a
        ld      (x86_io_keyboard_count),a
        or      a
        ret
.keyboard_push_full:
        ld      a,1
        ld      (x86_io_keyboard_overflow),a
        scf
        ret

; Reset XT keyboard input state and queue the standard BAT completion byte.
x86_io_keyboard_reset:
        xor     a
        ld      (x86_io_keyboard_head),a
        ld      (x86_io_keyboard_tail),a
        ld      (x86_io_keyboard_count),a
        ld      (x86_io_keyboard_last),a
        ld      a,#AA
        jp      x86_io_keyboard_push

; A=next keyboard byte, or last data latch if FIFO empty.
x86_io_keyboard_read:
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

; Read one byte from the guest I/O bus. A=read value.
x86_io_read8:
        ld      hl,(x86_io_count_in)
        inc     hl
        ld      (x86_io_count_in),hl
        call    x86_io_read8_device
        ret

; Internal byte read. Does not change the operation counter.
x86_io_read8_device:
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        jr      nz,.io_read8_ppi
        ld      a,(x86_io_test_latch)
        ret
.io_read8_ppi:
        call    x86_io_ppi_read8
        ret     nc
        ld      a,#FF
        ret

; Read one byte from PPI 8255. Carry set means port is not in PPI decode.
x86_io_ppi_read8:
        ld      hl,(x86_io_port)
        ld      de,#0060
        or      a
        sbc     hl,de
        jr      z,.ppi_read_a
        ld      hl,(x86_io_port)
        ld      de,#0061
        or      a
        sbc     hl,de
        jr      z,.ppi_read_b
        ld      hl,(x86_io_port)
        ld      de,#0062
        or      a
        sbc     hl,de
        jr      z,.ppi_read_c
        ld      hl,(x86_io_port)
        ld      de,#0063
        or      a
        sbc     hl,de
        jr      z,.ppi_read_control
        scf
        ret
.ppi_read_a:
        ld      a,(x86_io_ppi_control)
        bit     4,a
        jr      z,.ppi_read_a_latch
        jp      x86_io_keyboard_read
.ppi_read_a_latch:
        ld      a,(x86_io_ppi_pa)
        or      a
        ret
.ppi_read_b:
        ld      a,(x86_io_ppi_control)
        bit     1,a
        jr      nz,.ppi_read_b_input
        ld      a,(x86_io_ppi_pb)
        or      a
        ret
.ppi_read_b_input:
        ld      a,#FF
        or      a
        ret
.ppi_read_c:
        ; Port C combines external input pins and the output latch according
        ; to the upper/lower direction bits of the 8255 mode control word.
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
.ppi_read_control:
        ; 8255 control register is not a readable data register.
        ld      a,#FF
        or      a
        ret

; Write one byte to the guest I/O bus. A=value.
x86_io_write8:
        ld      hl,(x86_io_count_out)
        inc     hl
        ld      (x86_io_count_out),hl
        jp      x86_io_write8_device

; Internal byte write. Does not change the operation counter.
; A=value.
x86_io_write8_device:
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        jr      nz,.io_write8_ppi
        ld      (x86_io_test_latch),a
        ret
.io_write8_ppi:
        jp      x86_io_ppi_write8

; Write one byte to PPI 8255. Carry set means port is not in PPI decode.
; A=value.
x86_io_ppi_write8:
        ld      (x86_io_ppi_write_value),a
        ld      hl,(x86_io_port)
        ld      de,#0060
        or      a
        sbc     hl,de
        jr      z,.ppi_write_a
        ld      hl,(x86_io_port)
        ld      de,#0061
        or      a
        sbc     hl,de
        jr      z,.ppi_write_b
        ld      hl,(x86_io_port)
        ld      de,#0062
        or      a
        sbc     hl,de
        jr      z,.ppi_write_c
        ld      hl,(x86_io_port)
        ld      de,#0063
        or      a
        sbc     hl,de
        jr      z,.ppi_write_control
        scf
        ret
.ppi_write_a:
        ld      a,(x86_io_ppi_write_value)
        ld      (x86_io_ppi_pa),a
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
        call    x86_io_keyboard_reset
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
        ; Mode-set operation. The XT BIOS selects mode 0 (control word 99h).
        ; 8255 mode-set resets output latches; mode 1/2 handshake behavior
        ; remains outside this first implementation slice.
        ld      (x86_io_ppi_control),a
        xor     a
        ld      (x86_io_ppi_pa),a
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
x86_io_read16:
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
        call    x86_io_read8_device
        ld      (x86_io_word_low),a
        ld      hl,(x86_io_saved_port)
        inc     hl
        ld      (x86_io_port),hl
        call    x86_io_read8_device
        ld      h,a
        ld      a,(x86_io_word_low)
        ld      l,a
        ld      hl,(x86_io_word_value)
        ; Rebuild HL from the saved low byte and the high byte just read.
        ld      h,a
        ld      a,(x86_io_word_high)
        ; High byte is saved below; this placeholder is overwritten by
        ; the explicit high-byte path to keep AF/HL handling unambiguous.
        ld      hl,(x86_io_saved_port)
        ld      (x86_io_port),hl
        ld      a,(x86_io_word_low)
        ld      l,a
        ld      a,(x86_io_word_high)
        ld      h,a
        ret

; Write a 16-bit value. The 00E0h test device has a native word latch;
; other ports use PCem's byte fallback at port and port+1.
x86_io_write16:
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
        call    x86_io_write8_device
        ld      hl,(x86_io_saved_port)
        inc     hl
        ld      (x86_io_port),hl
        ld      a,(x86_io_word_value+1)
        call    x86_io_write8_device
        ld      hl,(x86_io_saved_port)
        ld      (x86_io_port),hl
        ret

; Diagnostic output only: guest ports remain software-modeled.
; Format: [IO] IN8 P=03DA V=FF @F000:E05B
x86_io_log_access:
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

x86_io_port: dw 0
x86_io_value: dw 0
x86_io_test_latch: dw 0
x86_io_log_value: dw 0
x86_io_log_direction: db 0
x86_io_log_width: db 0
x86_io_saved_port: dw 0
x86_io_word_value: dw 0
x86_io_word_low: db 0
x86_io_word_high: db 0

x86_io_ppi_pa: db 0
x86_io_ppi_pb: db #40
x86_io_ppi_pc: db 0
x86_io_ppi_control: db #9B
x86_io_ppi_write_value: db 0
; Deterministic XT profile switch input (generic XT/no-FPU default). This
; value remains a profile parameter until the ATM-PC board switches are set.
x86_io_ppi_port_c_input: db #0D

x86_io_keyboard_fifo: defs 16,0
x86_io_keyboard_head: db 0
x86_io_keyboard_tail: db 0
x86_io_keyboard_count: db 0
x86_io_keyboard_last: db 0
x86_io_keyboard_push_value: db 0
x86_io_keyboard_overflow: db 0

x86_io_count_in:  dw 0
x86_io_count_out: dw 0
