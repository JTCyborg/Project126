; PROJECT126 — virtual 8086 I/O port bus.
; No physical NeoGS/Z80 port access is performed here. Guest I/O ports are
; modeled in software; external device requests will be routed through DMA/IPC.
;
; Initial deterministic test device:
;   port 00E0h: 16-bit read/write latch (byte accesses use low lane).
; Unmapped reads return FFh/FFFFh; unmapped writes are ignored.
; Guest FLAGS and CPU registers are never changed by the backend.

x86_io_read8:
        ld      hl,(x86_io_count_in)
        inc     hl
        ld      (x86_io_count_in),hl
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
        ld      hl,(x86_io_count_in)
        inc     hl
        ld      (x86_io_count_in),hl
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
        ld      hl,(x86_io_count_out)
        inc     hl
        ld      (x86_io_count_out),hl
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        ret     nz
        ld      (x86_io_test_latch),a
        ret

; HL=value. Word write updates the complete 16-bit test latch.
x86_io_write16:
        ld      (x86_io_value),hl
        ld      hl,(x86_io_count_out)
        inc     hl
        ld      (x86_io_count_out),hl
        ld      hl,(x86_io_port)
        ld      de,#00E0
        or      a
        sbc     hl,de
        ret     nz
        ld      hl,(x86_io_value)
        ld      (x86_io_test_latch),hl
        ret

; Emit one completed guest IN/OUT operation on the existing NeoGS
; diagnostic channel. This is diagnostic output only: guest ports remain
; software-modeled and no guest port number is issued as a physical Z80 I/O.
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
        out     (#EF),a
        jr      .log_port
.log_word_width:
        ld      a,'1'
        out     (#EF),a
        ld      a,'6'
        out     (#EF),a
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
        out     (#EF),a
        ld      hl,(x86_exec_instruction_start_ip)
        call    x86_io_log_hex16
        ld      a,13
        out     (#EF),a
        ld      a,10
        out     (#EF),a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; HL points to a zero-terminated diagnostic string.
x86_io_log_string:
        ld      a,(hl)
        or      a
        ret     z
        out     (#EF),a
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
        out     (#EF),a
        ret

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

x86_io_count_in:  dw 0
x86_io_count_out: dw 0
