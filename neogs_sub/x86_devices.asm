; PROJECT126 — 8237 DMA and 8253 PIT guest-device overlay
; Fixed origin 8000h, physical page 06h (WIN2 selector 03h).
; Guest port emulation only: guest port values are never physical NeoGS I/O.
; Resident gate exports x86_dev_read8, x86_dev_write8 and x86_dev_reset.
; Register models only: DMA transfer execution and PIT clock/IRQ0 pending.

x86_dev_read8_impl:
        ld      (x86_dev_port),hl
        call    x86_dev_dma_read8
        ret     nc
        jp      x86_dev_pit_read8

x86_dev_write8_impl:
        ld      (x86_dev_port),hl
        ld      (x86_dev_write_value),a
        call    x86_dev_dma_write8
        ret     nc
        ld      a,(x86_dev_write_value)
        jp      x86_dev_pit_write8

x86_dev_reset_impl:
        call    x86_dev_dma_reset_impl
        call    x86_dev_dma_selftest_impl
        call    x86_dev_pit_reset_impl
        call    x86_dev_pit_selftest_impl
        ret

x86_dev_overlay_probe_impl:
        ld      a,#5A
        ld      hl,#06D1
        ret

; 8253 PIT programming/readback slice (ports 0040h..0043h).
; Counters are static register latches in this phase: no clock decrement,
; output pin, speaker waveform or IRQ0 generation is claimed.
; -------------------------------------------------------------------------
x86_dev_pit_decode:
        ld      hl,(x86_dev_port)
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

x86_dev_pit_read8:
        call    x86_dev_pit_decode
        ret     c
        cp      3
        jp      z,.pit_read_open_bus
        ld      (x86_dev_pit_channel),a
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_access
        add     hl,de
        ld      a,(hl)
        cp      1
        jr      z,.pit_read_lsb
        cp      2
        jr      z,.pit_read_msb
        cp      3
        jr      nz,.pit_read_open_bus
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_read_ff
        add     hl,de
        ld      a,(hl)
        ld      (x86_dev_pit_byte_select),a
        jr      .pit_read_byte
.pit_read_lsb:
        xor     a
        ld      (x86_dev_pit_byte_select),a
        jr      .pit_read_byte
.pit_read_msb:
        ld      a,1
        ld      (x86_dev_pit_byte_select),a
.pit_read_byte:
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_latch_valid
        add     hl,de
        ld      a,(hl)
        or      a
        jr      z,.pit_read_reload
        ld      hl,x86_dev_pit_latch
        jr      .pit_read_base
.pit_read_reload:
        ld      hl,x86_dev_pit_reload
.pit_read_base:
        ld      a,(x86_dev_pit_channel)
        add     a,a
        ld      e,a
        ld      a,(x86_dev_pit_byte_select)
        add     a,e
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(hl)
        ld      (x86_dev_pit_read_value),a
        ; LSB/MSB mode toggles after each byte; a complete pair releases latch.
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_access
        add     hl,de
        ld      a,(hl)
        cp      3
        jr      nz,.pit_read_clear_latch
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_read_ff
        add     hl,de
        ld      a,(hl)
        xor     1
        ld      (hl),a
        or      a
        jr      nz,.pit_read_done
.pit_read_clear_latch:
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_latch_valid
        add     hl,de
        xor     a
        ld      (hl),a
.pit_read_done:
        ld      a,(x86_dev_pit_read_value)
        or      a
        ret
.pit_read_open_bus:
        ld      a,#FF
        or      a
        ret

x86_dev_pit_write8:
        ld      (x86_dev_pit_write_value),a
        call    x86_dev_pit_decode
        ret     c
        cp      3
        jr      z,.pit_write_control
        ld      (x86_dev_pit_channel),a
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_access
        add     hl,de
        ld      a,(hl)
        cp      1
        jr      z,.pit_write_lsb
        cp      2
        jr      z,.pit_write_msb
        cp      3
        jr      nz,.pit_write_done
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_write_ff
        add     hl,de
        ld      a,(hl)
        ld      (x86_dev_pit_byte_select),a
        jr      .pit_write_byte
.pit_write_lsb:
        xor     a
        ld      (x86_dev_pit_byte_select),a
        jr      .pit_write_byte
.pit_write_msb:
        ld      a,1
        ld      (x86_dev_pit_byte_select),a
.pit_write_byte:
        ld      a,(x86_dev_pit_channel)
        add     a,a
        ld      e,a
        ld      a,(x86_dev_pit_byte_select)
        add     a,e
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_reload
        add     hl,de
        ld      a,(x86_dev_pit_write_value)
        ld      (hl),a
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_access
        add     hl,de
        ld      a,(hl)
        cp      3
        jr      nz,.pit_write_done
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_write_ff
        add     hl,de
        ld      a,(hl)
        xor     1
        ld      (hl),a
.pit_write_done:
        or      a
        ret
.pit_write_control:
        ld      a,(x86_dev_pit_write_value)
        rrca
        rrca
        rrca
        rrca
        rrca
        rrca
        and     3
        cp      3
        jr      z,.pit_write_done
        ld      (x86_dev_pit_channel),a
        ; Access mode 00 is a count latch command; it does not reprogram mode.
        ld      a,(x86_dev_pit_write_value)
        rrca
        rrca
        rrca
        rrca
        and     3
        jr      z,.pit_latch_command
        ; Store the selected channel's access mode.
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_access
        add     hl,de
        ld      a,(x86_dev_pit_write_value)
        rrca
        rrca
        rrca
        rrca
        and     3
        ld      (hl),a
        ; Normalize modes 6/7 to aliases 2/3 and store per channel.
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_mode
        add     hl,de
        ld      a,(x86_dev_pit_write_value)
        rrca
        and     7
        cp      6
        jr      c,.pit_mode_store
        sub     4
.pit_mode_store:
        ld      (hl),a
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_bcd
        add     hl,de
        ld      a,(x86_dev_pit_write_value)
        and     1
        ld      (hl),a
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_read_ff
        add     hl,de
        xor     a
        ld      (hl),a
        ld      hl,x86_dev_pit_write_ff
        add     hl,de
        ld      (hl),a
        ld      hl,x86_dev_pit_latch_valid
        add     hl,de
        ld      (hl),a
        or      a
        ret
.pit_latch_command:
        ; Copy the selected 16-bit reload value into its read latch.
        ld      a,(x86_dev_pit_channel)
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_reload
        add     hl,de
        push    hl
        ld      hl,x86_dev_pit_latch
        add     hl,de
        ex      de,hl
        pop     hl
        ld      bc,2
        ldir
        ld      a,(x86_dev_pit_channel)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_pit_latch_valid
        add     hl,de
        ld      a,1
        ld      (hl),a
        or      a
        ret

x86_dev_pit_reset_impl:
        xor     a
        ld      hl,x86_dev_pit_reload
        ld      de,x86_dev_pit_reload+1
        ld      bc,5
        ld      (hl),a
        ldir
        ld      hl,x86_dev_pit_latch
        ld      de,x86_dev_pit_latch+1
        ld      bc,5
        ld      (hl),a
        ldir
        ld      hl,x86_dev_pit_access
        ld      de,x86_dev_pit_access+1
        ld      bc,2
        ld      a,3
        ld      (hl),a
        ldir
        xor     a
        ld      hl,x86_dev_pit_mode
        ld      de,x86_dev_pit_mode+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      hl,x86_dev_pit_bcd
        ld      de,x86_dev_pit_bcd+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      hl,x86_dev_pit_read_ff
        ld      de,x86_dev_pit_read_ff+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      hl,x86_dev_pit_write_ff
        ld      de,x86_dev_pit_write_ff+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      hl,x86_dev_pit_latch_valid
        ld      de,x86_dev_pit_latch_valid+1
        ld      bc,2
        ld      (hl),a
        ldir
        ld      (x86_dev_pit_channel),a
        ld      (x86_dev_pit_byte_select),a
        ld      (x86_dev_pit_read_value),a
        ld      (x86_dev_pit_write_value),a
        ret

; Reset-time regression for channel 0 LSB/MSB, latch/readback and channel 1 LSB.
x86_dev_pit_selftest_impl:
        call    x86_dev_pit_reset_impl
        ld      hl,#0043
        ld      (x86_dev_port),hl
        ld      a,#36
        call    x86_dev_pit_write8
        jp      c,.pit_selftest_fail
        ld      hl,#0040
        ld      (x86_dev_port),hl
        ld      a,#34
        call    x86_dev_pit_write8
        jp      c,.pit_selftest_fail
        ld      a,#12
        call    x86_dev_pit_write8
        jp      c,.pit_selftest_fail
        ld      a,(x86_dev_pit_reload)
        cp      #34
        jp      nz,.pit_selftest_fail
        ld      a,(x86_dev_pit_reload+1)
        cp      #12
        jp      nz,.pit_selftest_fail
        call    x86_dev_pit_read8
        cp      #34
        jp      nz,.pit_selftest_fail
        call    x86_dev_pit_read8
        cp      #12
        jp      nz,.pit_selftest_fail
        ; Latch command 00h snapshots the count without changing access mode.
        ld      hl,#0043
        ld      (x86_dev_port),hl
        xor     a
        call    x86_dev_pit_write8
        jp      c,.pit_selftest_fail
        ld      hl,#0040
        ld      (x86_dev_port),hl
        call    x86_dev_pit_read8
        cp      #34
        jp      nz,.pit_selftest_fail
        call    x86_dev_pit_read8
        cp      #12
        jp      nz,.pit_selftest_fail
        ; Channel 1 LSB-only mode.
        ld      hl,#0043
        ld      (x86_dev_port),hl
        ld      a,#50
        call    x86_dev_pit_write8
        jp      c,.pit_selftest_fail
        ld      hl,#0041
        ld      (x86_dev_port),hl
        ld      a,#AB
        call    x86_dev_pit_write8
        jp      c,.pit_selftest_fail
        ld      a,(x86_dev_pit_reload+2)
        cp      #AB
        jp      nz,.pit_selftest_fail
        call    x86_dev_pit_read8
        cp      #AB
        jp      nz,.pit_selftest_fail
        ld      hl,x86_dev_pit_selftest_pass
        jr      .pit_selftest_restore
.pit_selftest_fail:
        ld      hl,x86_dev_pit_selftest_fail
.pit_selftest_restore:
        push    hl
        call    x86_dev_pit_reset_impl
        ld      hl,0
        ld      (x86_dev_port),hl
        pop     hl
        jp      p126_ngs_ipc_log

; -------------------------------------------------------------------------
; 8237-compatible 4-channel DMA register file and page registers.
; Transfer execution is a separate device-service task: this slice models
; guest-visible address/count/mode/mask/request/status programming only.
; -------------------------------------------------------------------------
x86_dev_dma_decode:
        ld      hl,(x86_dev_port)
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
        ld      (x86_dev_dma_page_index),a
        ld      a,1
        ld      (x86_dev_dma_page_select),a
        or      a
        ret
.dma_decode_controller:
        ld      (x86_dev_dma_port_offset),a
        xor     a
        ld      (x86_dev_dma_page_select),a
        or      a
        ret
.dma_decode_bad:
        scf
        ret

x86_dev_dma_read8:
        call    x86_dev_dma_decode
        ret     c
        ld      a,(x86_dev_dma_page_select)
        or      a
        jr      nz,.dma_read_page
        ld      a,(x86_dev_dma_port_offset)
        cp      8
        jr      z,.dma_read_status
        cp      8
        jr      nc,.dma_read_open_bus
        ; 00h..07h alternate address/count registers; one shared byte pointer.
        ld      a,(x86_dev_dma_port_offset)
        srl     a
        add     a,a
        ld      e,a
        ld      a,(x86_dev_dma_flipflop)
        add     a,e
        ld      e,a
        ld      d,0
        ld      a,(x86_dev_dma_port_offset)
        bit     0,a
        jr      nz,.dma_read_count
        ld      hl,x86_dev_dma_address
        jr      .dma_read_channel
.dma_read_count:
        ld      hl,x86_dev_dma_count
.dma_read_channel:
        add     hl,de
        ld      a,(hl)
        call    x86_dev_dma_toggle_flipflop
        or      a
        ret
.dma_read_status:
        ; Bits 0..3 are terminal-count flags; bits 4..7 are request flags.
        ld      a,(x86_dev_dma_status)
        and     #0F
        ld      b,a
        ld      a,(x86_dev_dma_request)
        and     #0F
        rlca
        rlca
        rlca
        rlca
        or      b
        ld      b,a
        xor     a
        ld      (x86_dev_dma_status),a
        ld      a,b
        or      a
        ret
.dma_read_open_bus:
        ld      a,#FF
        or      a
        ret
.dma_read_page:
        ld      a,(x86_dev_dma_page_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_dma_page
        add     hl,de
        ld      a,(hl)
        or      a
        ret

x86_dev_dma_write8:
        ld      (x86_dev_dma_write_value),a
        call    x86_dev_dma_decode
        ret     c
        ld      a,(x86_dev_dma_page_select)
        or      a
        jp      nz,.dma_write_page
        ld      a,(x86_dev_dma_port_offset)
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
        ld      a,(x86_dev_dma_write_value)
        and     #0F
        ld      (x86_dev_dma_mask),a
        or      a
        ret
.dma_write_channel:
        ld      a,(x86_dev_dma_port_offset)
        srl     a
        add     a,a
        ld      e,a
        ld      a,(x86_dev_dma_flipflop)
        add     a,e
        ld      e,a
        ld      d,0
        ld      a,(x86_dev_dma_port_offset)
        bit     0,a
        jr      nz,.dma_write_count
        ld      hl,x86_dev_dma_address
        jr      .dma_write_channel_store
.dma_write_count:
        ld      hl,x86_dev_dma_count
.dma_write_channel_store:
        add     hl,de
        ld      a,(x86_dev_dma_write_value)
        ld      (hl),a
        call    x86_dev_dma_toggle_flipflop
        or      a
        ret
.dma_write_command:
        ld      a,(x86_dev_dma_write_value)
        ld      (x86_dev_dma_command),a
        or      a
        ret
.dma_write_request:
        ld      a,(x86_dev_dma_write_value)
        and     3
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_dma_bit_masks
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_dev_dma_write_value)
        bit     2,a
        jr      z,.dma_request_clear
        ld      a,(x86_dev_dma_request)
        or      b
        ld      (x86_dev_dma_request),a
        or      a
        ret
.dma_request_clear:
        ld      a,b
        cpl
        ld      b,a
        ld      a,(x86_dev_dma_request)
        and     b
        ld      (x86_dev_dma_request),a
        or      a
        ret
.dma_write_single_mask:
        ld      a,(x86_dev_dma_write_value)
        and     3
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_dma_bit_masks
        add     hl,de
        ld      a,(hl)
        ld      b,a
        ld      a,(x86_dev_dma_write_value)
        bit     2,a
        jr      z,.dma_unmask_channel
        ld      a,(x86_dev_dma_mask)
        or      b
        ld      (x86_dev_dma_mask),a
        or      a
        ret
.dma_unmask_channel:
        ld      a,b
        cpl
        ld      b,a
        ld      a,(x86_dev_dma_mask)
        and     b
        ld      (x86_dev_dma_mask),a
        or      a
        ret
.dma_write_mode:
        ld      a,(x86_dev_dma_write_value)
        ld      (x86_dev_dma_mode),a
        or      a
        ret
.dma_write_clear_flipflop:
        xor     a
        ld      (x86_dev_dma_flipflop),a
        or      a
        ret
.dma_write_master_clear:
        xor     a
        ld      (x86_dev_dma_command),a
        ld      (x86_dev_dma_status),a
        ld      (x86_dev_dma_request),a
        ld      (x86_dev_dma_mode),a
        ld      (x86_dev_dma_temporary),a
        ld      (x86_dev_dma_flipflop),a
        ld      a,#0F
        ld      (x86_dev_dma_mask),a
        or      a
        ret
.dma_write_clear_mask:
        xor     a
        ld      (x86_dev_dma_mask),a
        or      a
        ret
.dma_write_page:
        ld      a,(x86_dev_dma_page_index)
        ld      e,a
        ld      d,0
        ld      hl,x86_dev_dma_page
        add     hl,de
        ld      a,(x86_dev_dma_write_value)
        ld      (hl),a
        or      a
        ret

x86_dev_dma_toggle_flipflop:
        ld      a,(x86_dev_dma_flipflop)
        xor     1
        ld      (x86_dev_dma_flipflop),a
        ret

; CPU reset clears the entire guest-visible 8237 register file and page latches.
x86_dev_dma_reset_impl:
        xor     a
        ld      hl,x86_dev_dma_address
        ld      de,x86_dev_dma_address+1
        ld      bc,7
        ld      (hl),a
        ldir
        ld      hl,x86_dev_dma_count
        ld      de,x86_dev_dma_count+1
        ld      bc,7
        ld      (hl),a
        ldir
        ld      hl,x86_dev_dma_page
        ld      de,x86_dev_dma_page+1
        ld      bc,3
        ld      (hl),a
        ldir
        ld      (x86_dev_dma_command),a
        ld      (x86_dev_dma_status),a
        ld      (x86_dev_dma_request),a
        ld      (x86_dev_dma_mode),a
        ld      (x86_dev_dma_temporary),a
        ld      (x86_dev_dma_flipflop),a
        ld      (x86_dev_dma_page_select),a
        ld      (x86_dev_dma_page_index),a
        ld      (x86_dev_dma_port_offset),a
        ld      a,#0F
        ld      (x86_dev_dma_mask),a
        ret

; Register-file regression: address/count low-high flip-flop, page registers,
; single-channel mask commands and master-clear reset behavior.
x86_dev_dma_selftest_impl:
        ; Clear byte pointer, then program channel 0 address=1234h.
        ld      hl,#000C
        ld      (x86_dev_port),hl
        xor     a
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      hl,#0000
        ld      (x86_dev_port),hl
        ld      a,#34
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,#12
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_dev_dma_address)
        cp      #34
        jp      nz,.dma_selftest_fail
        ld      a,(x86_dev_dma_address+1)
        cp      #12
        jp      nz,.dma_selftest_fail
        ; Read back the same low/high sequence.
        ld      a,(x86_dev_dma_flipflop)
        or      a
        jp      nz,.dma_selftest_fail
        call    x86_dev_dma_read8
        cp      #34
        jp      nz,.dma_selftest_fail
        call    x86_dev_dma_read8
        cp      #12
        jp      nz,.dma_selftest_fail
        ; Channel 0 count=5678h.
        ld      hl,#0001
        ld      (x86_dev_port),hl
        ld      a,#78
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,#56
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_dev_dma_count)
        cp      #78
        jp      nz,.dma_selftest_fail
        ld      a,(x86_dev_dma_count+1)
        cp      #56
        jp      nz,.dma_selftest_fail
        ; DMA page register for channel 1 is port 81h.
        ld      hl,#0081
        ld      (x86_dev_port),hl
        ld      a,#A5
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        call    x86_dev_dma_read8
        cp      #A5
        jp      nz,.dma_selftest_fail
        ; Clear all masks, mask channel 2, then unmask channel 2.
        ld      hl,#000E
        ld      (x86_dev_port),hl
        xor     a
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      hl,#000A
        ld      (x86_dev_port),hl
        ld      a,#06
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_dev_dma_mask)
        cp      4
        jp      nz,.dma_selftest_fail
        ld      a,#02
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_dev_dma_mask)
        or      a
        jp      nz,.dma_selftest_fail
        ; Master clear restores mask=0Fh and byte pointer=0.
        ld      hl,#000D
        ld      (x86_dev_port),hl
        xor     a
        call    x86_dev_dma_write8
        jp      c,.dma_selftest_fail
        ld      a,(x86_dev_dma_mask)
        cp      #0F
        jp      nz,.dma_selftest_fail
        ld      a,(x86_dev_dma_flipflop)
        or      a
        jp      nz,.dma_selftest_fail
        ld      hl,x86_dev_dma_selftest_pass
        jr      .dma_selftest_restore
.dma_selftest_fail:
        ld      hl,x86_dev_dma_selftest_fail
.dma_selftest_restore:
        push    hl
        call    x86_dev_dma_reset_impl
        ld      hl,0
        ld      (x86_dev_port),hl
        pop     hl
        jp      p126_ngs_ipc_log

; -------------------------------------------------------------------------

x86_dev_dma_address: defs 8,0
x86_dev_dma_count: defs 8,0
x86_dev_dma_page: defs 4,0
x86_dev_dma_command: db 0
x86_dev_dma_status: db 0
x86_dev_dma_request: db 0
x86_dev_dma_mask: db #0F
x86_dev_dma_mode: db 0
x86_dev_dma_temporary: db 0
x86_dev_dma_flipflop: db 0
x86_dev_dma_page_select: db 0
x86_dev_dma_page_index: db 0
x86_dev_dma_port_offset: db 0
x86_dev_dma_write_value: db 0
x86_dev_dma_bit_masks: db #01,#02,#04,#08
x86_dev_dma_selftest_pass: db "[NGS] X86 DMA REGISTER SELFTEST PASS",13,10,0
x86_dev_pit_reload: defs 6,0
x86_dev_pit_latch: defs 6,0
x86_dev_pit_access: db 3,3,3
x86_dev_pit_mode: db 0,0,0
x86_dev_pit_bcd: db 0,0,0
x86_dev_pit_read_ff: db 0,0,0
x86_dev_pit_write_ff: db 0,0,0
x86_dev_pit_latch_valid: db 0,0,0
x86_dev_pit_channel: db 0
x86_dev_pit_byte_select: db 0
x86_dev_pit_read_value: db 0
x86_dev_pit_write_value: db 0
x86_dev_pit_selftest_pass: db "[NGS] X86 PIT REGISTER SELFTEST PASS",13,10,0
x86_dev_pit_selftest_fail: db "[NGS] X86 PIT REGISTER SELFTEST FAIL",13,10,0
x86_dev_dma_selftest_fail: db "[NGS] X86 DMA REGISTER SELFTEST FAIL",13,10,0


x86_dev_port: dw 0
x86_dev_write_value: db 0
