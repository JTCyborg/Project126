; PROJECT126 / X86_CPU_STATE v0.2.0
; PCem references: PCem/808x.c resetx86(), PCem/cpu.h CPU_8086.
; Intel 8086 Real Mode architectural state and 20-bit physical address helper.
; Guest physical decode and banked NeoGS guest-RAM access are implemented here.
;
; API:
;   x86_cpu_reset       Reset vector FFFF:0000, FLAGS=0002h.
;   x86_cpu_calc_phys   IN HL=segment, DE=offset.
;                       OUT x86_phys_addr[0..2], little endian; A=high nibble.
;                       Physical address wraps at 1 MiB (8086 bus, no A20).
;   x86_mem_classify    IN x86_phys_addr[0..2], OUT A=region ID.
;   x86_guest_ram_read8 IN x86_phys_addr[0..2], OUT A=byte, carry=error.
;   x86_guest_ram_write8 IN x86_phys_addr[0..2], A=byte, carry=error.
;   x86_guest_mem_read8  IN x86_phys_addr[0..2], OUT A=byte, carry=error.
;   x86_guest_mem_write8 IN x86_phys_addr[0..2], A=byte, carry=error.
;                       Dispatches RAM, VGA aperture and BIOS ROM through WIN3.
;                       Writes to either BIOS ROM region are rejected.
;                       Uses WIN3 (C000h..FFFFh) as a dedicated bank window.
;                       Code, stack and interrupt handlers must remain WIN0..2.
;   x86_cpu_emit_version Emits the executing component version to NeoGS #EF.
;   x86_cpu_state_selftest Carry clear=pass, set=fail. Destructive reset test.

X86_FLAGS_RESET EQU #0002

x86_cpu_reset:
        ld      hl,0
        ld      (x86_reg_ax),hl
        ld      (x86_reg_cx),hl
        ld      (x86_reg_dx),hl
        ld      (x86_reg_bx),hl
        ld      (x86_reg_sp),hl
        ld      (x86_reg_bp),hl
        ld      (x86_reg_si),hl
        ld      (x86_reg_di),hl
        ld      (x86_reg_es),hl
        ld      (x86_reg_ss),hl
        ld      (x86_reg_ds),hl
        ld      (x86_reg_ip),hl
        ld      hl,#FFFF
        ld      (x86_reg_cs),hl
        ld      hl,X86_FLAGS_RESET
        ld      (x86_reg_flags),hl
        xor     a
        ld      (x86_mem_fault_diag_once),a
        ld      (x86_halted),a
        ld      (x86_pending_irq),a
        ld      (x86_pending_nmi),a
        ld      (x86_irq_inhibit),a
        ld      (x86_tf_pending),a
        ld      a,8
        ld      (x86_irq_vector),a
        call    x86_io_reset
        ret

; -------------------------------------------------------------------------
; BIOS reset-vector execution gate.
; The 8086 starts at FFFF:0000. Execute the first guest instruction through
; the production fetch/decode/execute path; BIOS1 contains EA 5B E0 00 F0
; (JMP FAR F000:E05B). This is a real instruction step, not operand seeding.
; Entry: called once after IMAGE_FINISH has set BIOS_IMAGE_READY.
; -------------------------------------------------------------------------
x86_bios_reset_vector_probe:
        call    x86_cpu_reset
        call    x86_cpu_step
        jr      c,.execution_failed

        ld      hl,(x86_reg_ip)
        ld      de,#E05B
        or      a
        sbc     hl,de
        jr      nz,.vector_mismatch
        ld      hl,(x86_reg_cs)
        ld      de,#F000
        or      a
        sbc     hl,de
        jr      nz,.vector_mismatch

        ld      hl,x86_bios_reset_vector_pass_log
        call    p126_ngs_resident_log
        ld      hl,x86_bios_reset_target_log
        call    p126_ngs_resident_log
        or      a
        ret
.execution_failed:
        ld      hl,x86_bios_reset_read_fail_log
        call    p126_ngs_resident_log
        scf
        ret
.vector_mismatch:
        ld      hl,x86_bios_reset_vector_bad_log
        call    p126_ngs_resident_log
        scf
        ret

; -------------------------------------------------------------------------
; Continuous BIOS bring-up execution.
; Runs after IMAGE_FINISH and page-10 readback verification. The old
; 16-instruction slice is removed. Execution continues until guest HLT,
; unsupported opcode, guest-memory fault, or a 65535-instruction watchdog.
; The watchdog is only a runaway-loop safety net; it is not a BIOS slice.
; Progress is reported every 256 instructions to avoid flooding #EF.
; -------------------------------------------------------------------------
; Compare the DMA BIOS payload, installed page-10 bytes and the normal
; guest-memory read path before BIOS execution starts.
; The DMA frame remains mapped and valid until IMAGE_FINISH returns.
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_image_diag:
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         push    af
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         push    bc
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         push    de
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         push    hl
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,#21                  ; DMA staging page 42h
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         out     (P126_NGS_BANK_WINDOW_PORT),a
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(#C077)              ; payload offset 005Bh
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      (x86_bios_diag_src_005b),a
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(#E00C)              ; payload offset 1FF0h
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      (x86_bios_diag_src_1ff0),a
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,#08                  ; installed physical page 10h
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         out     (P126_NGS_BANK_WINDOW_PORT),a
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(#C05B)              ; installed BIOS offset 005Bh
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      (x86_bios_diag_dst_005b),a
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(#DFF0)              ; installed BIOS offset 1FF0h
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      (x86_bios_diag_dst_1ff0),a
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      hl,x86_bios_diag_src_msg
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_string
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(x86_bios_diag_src_005b)
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      hl,x86_bios_diag_dst_msg
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_string
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(x86_bios_diag_dst_005b)
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      hl,x86_bios_diag_run_msg
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_string
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      hl,#F000
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      de,#E05B
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_cpu_calc_phys
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_guest_mem_read8
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      hl,x86_bios_diag_vector_src_msg
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_string
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(x86_bios_diag_src_1ff0)
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      hl,x86_bios_diag_vector_dst_msg
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_string
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(x86_bios_diag_dst_1ff0)
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,13
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_char
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,10
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_char
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,#21                  ; restore production DMA page 42h
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         out     (P126_NGS_BANK_WINDOW_PORT),a
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         pop     hl
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         pop     de
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         pop     bc
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         pop     af
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ret
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: 
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_trace_emit_string:
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ld      a,(hl)
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         inc     hl
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         or      a
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         ret     z
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         call    x86_bios_trace_emit_char
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED:         jr      x86_bios_trace_emit_string
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: 
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_src_msg: db "[BIOS IMAGE] SRC@005B=",0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_dst_msg: db " DST@005B=",0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_run_msg: db " RUN@FE05B=",0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_vector_src_msg: db " SRC@1FF0=",0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_vector_dst_msg: db " DST@1FF0=",0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_src_005b: db 0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_dst_005b: db 0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_src_1ff0: db 0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: x86_bios_diag_dst_1ff0: db 0
; OBSOLETE IMAGE-COPY DIAGNOSTIC DISABLED: 
x86_bios_startup_trace:
        ; Run BIOS in bounded slices so the resident IPC dispatcher remains
        ; responsive during long RAM-sizing and PIT polling loops.
        ld      a,(x86_bios_trace_active)
        or      a
        jr      nz,.run_slice
        call    x86_bios_reset_vector_probe
        jr      nc,.reset_vector_ok
        ld      a,4
        call    x86_bios_trace_capture_event
        xor     a
        ld      (x86_bios_trace_active),a
        scf
        ret
.reset_vector_ok:
        xor     a
        ld      (x86_bios_trace_event_status),a
        ld      hl,x86_bios_trace_start_log
        call    p126_ngs_resident_log
        ; 32-bit runaway guard: a 16-bit budget expired during legitimate
        ; BIOS startup before the PIT polling loop could complete.
        ld      hl,#FFFF
        ld      (x86_bios_trace_remaining),hl
        ld      (x86_bios_trace_remaining+2),hl
        ld      hl,0
        ld      (x86_bios_trace_executed),hl
        xor     a
        ld      (x86_bios_trace_unexpected_cs_once),a
        ld      (x86_bios_trace_eebf_once),a
        ld      a,1
        ld      (x86_bios_trace_active),a
.run_slice:
        ; 64 instructions per pass; service IPC between slices.
        ld      a,64
        ld      (x86_bios_trace_slice_remaining),a
.trace_loop:
        call    x86_cpu_step
        jp      c,.trace_fault
        call    x86_bios_trace_capture_instruction
        ; One-shot history snapshot at the known BIOS2 runaway address.
        ; F000:EEBF is physical FEEBF, inside the system BIOS window.
        ld      a,(x86_bios_trace_eebf_once)
        or      a
        jr      nz,.trace_eebf_done
        ld      hl,(x86_reg_cs)
        ld      de,#F000
        or      a
        sbc     hl,de
        jr      nz,.trace_eebf_done
        ld      hl,(x86_reg_ip)
        ld      de,#EEBF
        or      a
        sbc     hl,de
        jr      nz,.trace_eebf_done
        ld      a,1
        ld      (x86_bios_trace_eebf_once),a
        push    hl
        ld      hl,x86_bios_trace_eebf_log
        call    p126_ngs_resident_log
        call    x86_bios_trace_log_registers
        call    x86_bios_trace_log_history
        pop     hl
.trace_eebf_done:
        ; Capture the first transition away from the BIOS reset segment.
        ; This is a diagnostic only: it does not alter guest CPU state.
        ld      hl,(x86_reg_cs)
        ld      de,#F000
        or      a
        sbc     hl,de
        jr      z,.trace_cs_expected
        ; 0030h is the BIOS's intentional RETF into its stack trampoline.
        ld      hl,(x86_reg_cs)
        ld      de,#0030
        or      a
        sbc     hl,de
        jr      z,.trace_cs_expected
        ld      a,(x86_bios_trace_unexpected_cs_once)
        or      a
        jr      nz,.trace_cs_expected
        inc     a
        ld      (x86_bios_trace_unexpected_cs_once),a
        push    hl
        ld      hl,x86_bios_trace_unexpected_cs_log
        call    p126_ngs_resident_log
        ld      hl,x86_bios_trace_far_target_prefix
        call    p126_ngs_resident_log
        ld      a,(x86_exec_far_jmp_target_valid)
        or      a
        jr      z,.trace_no_far_target
        ld      hl,(x86_exec_far_jmp_target_cs)
        call    x86_bios_trace_emit_hex16
        ld      a,':'
        call    x86_bios_trace_emit_char
        ld      hl,(x86_exec_far_jmp_target_ip)
        call    x86_bios_trace_emit_hex16
        jr      .trace_far_target_done
.trace_no_far_target:
        ld      hl,x86_bios_trace_far_target_none
        call    p126_ngs_resident_log
.trace_far_target_done:
        ld      a,13
        call    x86_bios_trace_emit_char
        ld      a,10
        call    x86_bios_trace_emit_char
        call    x86_bios_trace_log_cs_ip
        call    x86_bios_trace_log_registers
        pop     hl
.trace_cs_expected:
        ld      hl,(x86_bios_trace_executed)
        inc     hl
        ld      (x86_bios_trace_executed),hl
        ; Keep the serial log bounded during long REP/string and RAM-size
        ; loops. Emit progress every 4096 instructions, not every 256.
        ld      a,l
        or      a
        jr      nz,.trace_no_progress
        ld      a,h
        and     #0F
        jr      nz,.trace_no_progress
        call    x86_bios_trace_log_cs_ip
        call    x86_bios_trace_log_progress
.trace_no_progress:
        ld      a,(x86_halted)
        or      a
        jr      nz,.trace_halted
        ; Decrement the 32-bit instruction budget. The 64-instruction
        ; slices still return to the IPC dispatcher, so this large global
        ; budget does not block host servicing.
        ld      hl,(x86_bios_trace_remaining)
        ld      de,(x86_bios_trace_remaining+2)
        dec     hl
        ld      (x86_bios_trace_remaining),hl
        ld      a,h
        cp      #FF
        jr      nz,.watchdog_no_borrow
        ld      a,l
        cp      #FF
        jr      nz,.watchdog_no_borrow
        dec     de
        ld      (x86_bios_trace_remaining+2),de
.watchdog_no_borrow:
        ld      a,d
        or      e
        jr      nz,.watchdog_continue
        ld      a,h
        or      l
        jr      z,.trace_watchdog
.watchdog_continue:
        ld      a,(x86_bios_trace_slice_remaining)
        dec     a
        ld      (x86_bios_trace_slice_remaining),a
        jp      nz,.trace_loop
        or      a
        ret
.trace_watchdog:
        ld      a,5
        ld      hl,x86_bios_trace_watchdog_log
        jr      .trace_stop
.trace_fault:
        ld      a,3
        ld      hl,x86_bios_trace_fault_log
        jr      .trace_stop
.trace_halted:
        ld      a,2
        ld      hl,x86_bios_trace_halted_log
.trace_stop:
        ld      (x86_bios_trace_stop_kind),a
        xor     a
        ld      (x86_bios_trace_active),a
        push    hl
        ld      a,(x86_bios_trace_stop_kind)
        call    x86_bios_trace_capture_event
        pop     hl
        call    p126_ngs_resident_log
        call    x86_bios_trace_log_cs_ip
        call    x86_bios_trace_log_registers
        call    x86_bios_trace_log_io_counts
        ld      a,(x86_bios_trace_stop_kind)
        cp      5
        call    z,x86_io_dump_bios_table
        call    x86_bios_trace_log_history
        ld      a,(x86_bios_trace_stop_kind)
        cp      2
        ret     z
        scf
        ret

; Capture one completed instruction in a 16-entry circular history.
; Record layout: CS(2), IP(2), physical address(3), memory region(1), opcode(1).
x86_bios_trace_capture_instruction:
        push    af
        push    bc
        push    de
        push    hl
        ; Capture post-instruction CX, AL and FLAGS in the existing 9-byte
        ; history slot. CX is essential for diagnosing LOOP/LOOPZ progress;
        ; retain the fixed-size trace ring and resident image footprint.

        ld      a,(x86_bios_trace_history_index)
        ld      e,a
        add     a,a
        add     a,a
        add     a,a
        ld      d,a                    ; 8 * index
        ld      a,e
        add     a,a
        add     a,a
        add     a,e                    ; 5 * index
        add     a,d                    ; thirteen-byte record stride
        ld      l,a
        ld      h,0
        ld      de,x86_bios_trace_history
        add     hl,de
        ld      (x86_bios_trace_record_ptr),hl

        ld      hl,(x86_bios_trace_record_ptr)
        ld      de,(x86_exec_instruction_start_cs)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      de,(x86_exec_instruction_start_ip)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      de,(x86_reg_cx)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,(x86_reg_ax)
        ld      (hl),a
        inc     hl
        ld      a,(x86_reg_flags)
        ld      (hl),a
        inc     hl
        ld      a,(x86_exec_opcode)
        ld      (hl),a
        inc     hl
        ld      de,(x86_reg_ss)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      de,(x86_reg_sp)
        ld      (hl),e
        inc     hl
        ld      (hl),d

        ld      a,(x86_bios_trace_history_index)
        inc     a
        and     #0F
        ld      (x86_bios_trace_history_index),a
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Read the next two bytes through the production guest-memory mapper
; before the CPU step. This separates bad backing/mapping from decode faults.
; OBSOLETE FIRST-32 FETCH PROBE DISABLED: x86_bios_trace_log_fetch_probe:
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         push    af
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         push    bc
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         push    de
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         push    hl
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      a,(x86_bios_trace_first_count)
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         cp      32
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         jp      nc,.probe_done
; OBSOLETE FIRST-32 FETCH PROBE DISABLED: 
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      hl,(x86_reg_cs)
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      de,(x86_reg_ip)
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    x86_cpu_calc_phys
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    x86_guest_mem_read8
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      (x86_bios_trace_probe_byte0),a
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      a,0
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         adc     a,0
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      (x86_bios_trace_probe_error0),a
; OBSOLETE FIRST-32 FETCH PROBE DISABLED: 
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      hl,(x86_reg_cs)
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      de,(x86_reg_ip)
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         inc     de
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    x86_cpu_calc_phys
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    x86_guest_mem_read8
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      (x86_bios_trace_probe_byte1),a
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      a,0
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         adc     a,0
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      (x86_bios_trace_probe_error1),a
; OBSOLETE FIRST-32 FETCH PROBE DISABLED: 
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      hl,x86_bios_trace_probe_prefix
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      a,(x86_bios_trace_probe_byte0)
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      hl,x86_bios_trace_probe_second
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      a,(x86_bios_trace_probe_byte1)
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      a,13
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    x86_bios_trace_emit_char
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ld      a,10
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         call    x86_bios_trace_emit_char
; OBSOLETE FIRST-32 FETCH PROBE DISABLED: .probe_done:
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         pop     hl
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         pop     de
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         pop     bc
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         pop     af
; OBSOLETE FIRST-32 FETCH PROBE DISABLED:         ret
; OBSOLETE FIRST-32 FETCH PROBE DISABLED: 
; Emit a detailed architectural snapshot for each of the first 32 BIOS
; instructions. CS:IP and physical address identify the instruction start;
; registers and FLAGS are the post-instruction architectural state.
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED: x86_bios_trace_log_first32:
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         push    af
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         push    bc
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         push    de
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         push    hl
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_bios_trace_first_count)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         cp      32
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         jp      nc,.first32_done
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         inc     a
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      (x86_bios_trace_first_count),a
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      (x86_bios_trace_first_number),a
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED: 
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_exec_instruction_start_cs)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      de,(x86_exec_instruction_start_ip)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_cpu_calc_phys
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_phys_addr)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      (x86_bios_trace_first_phys),a
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_phys_addr+1)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      (x86_bios_trace_first_phys+1),a
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_phys_addr+2)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      (x86_bios_trace_first_phys+2),a
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_mem_classify
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      (x86_bios_trace_first_region),a
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED: 
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_prefix
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_bios_trace_first_number)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_csip
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_exec_instruction_start_cs)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,':'
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_char
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_exec_instruction_start_ip)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_phys_text
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_bios_trace_first_phys+2)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_bios_trace_first_phys+1)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_bios_trace_first_phys)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_region_text
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_bios_trace_first_region)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_opcode_text
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,(x86_exec_opcode)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex8
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED: 
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_ax
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_ax)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_bx
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_bx)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_cx
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_cx)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_dx
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_dx)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_si
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_si)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_di
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_di)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_bp
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_bp)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_sp
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_sp)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_ds
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_ds)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_es
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_es)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_ss
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_ss)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,x86_bios_trace_first_flags
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    p126_ngs_resident_log
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      hl,(x86_reg_flags)
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_hex16
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,13
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_char
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ld      a,10
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         call    x86_bios_trace_emit_char
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED: .first32_done:
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         pop     hl
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         pop     de
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         pop     bc
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         pop     af
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED:         ret
; OBSOLETE FIRST-32 REGISTER DUMP DISABLED: 
; I/O totals are reported even if no per-access line is present.
x86_bios_trace_log_io_counts:
        push    af
        push    hl
        ; X86IO is a page04 overlay: its counters must be snapshotted
        ; through the resident gate, never read directly while WIN2 is elsewhere.
        call    x86_io_snapshot_counters
        ld      hl,x86_bios_trace_io_prefix
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_io_in_snapshot)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_io_out_text
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_io_out_snapshot)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_io_last_out_text
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_io_last_out_port_snapshot)
        call    x86_bios_trace_emit_hex16
        ld      a,(x86_bios_trace_io_last_out_value_snapshot)
        call    x86_bios_trace_emit_hex8
        ld      a,13
        call    x86_bios_trace_emit_char
        ld      a,10
        call    x86_bios_trace_emit_char
        ld      hl,x86_bios_trace_pit_out_text
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_io_out42_snapshot)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_io_pit_sep_text
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_io_out43_snapshot)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_io_ppi_sep_text
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_io_out61_snapshot)
        call    x86_bios_trace_emit_hex16
        ld      a,13
        call    x86_bios_trace_emit_char
        ld      a,10
        call    x86_bios_trace_emit_char
        pop     hl
        pop     af
        ret

; Dump all 16 records, oldest first. At the watchdog the ring is full.


x86_bios_trace_log_history:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl,x86_bios_trace_history_title
        call    p126_ngs_resident_log
        ld      a,(x86_bios_trace_history_index)
        ld      (x86_bios_trace_dump_index),a
        ld      b,16
.history_loop:
        ld      a,(x86_bios_trace_dump_index)
        ld      e,a
        add     a,a
        add     a,a
        add     a,a
        ld      d,a                    ; 8 * index
        ld      a,e
        add     a,a
        add     a,a
        add     a,e                    ; 5 * index
        add     a,d                    ; thirteen-byte record stride
        ld      l,a
        ld      h,0
        ld      de,x86_bios_trace_history
        add     hl,de
        ld      a,(hl)
        ld      (x86_bios_trace_dump_cs),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_cs+1),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_ip),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_ip+1),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_cx),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_cx+1),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_al),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_flags),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_opcode),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_ss),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_ss+1),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_sp),a
        inc     hl
        ld      a,(hl)
        ld      (x86_bios_trace_dump_sp+1),a

        ld      hl,x86_bios_trace_history_prefix
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_dump_cs)
        call    x86_bios_trace_emit_hex16
        ld      a,':'
        call    x86_bios_trace_emit_char
        ld      hl,(x86_bios_trace_dump_ip)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_history_cx_text
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_dump_cx)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_history_al_text
        call    p126_ngs_resident_log
        ld      a,(x86_bios_trace_dump_al)
        call    x86_bios_trace_emit_hex8
        ld      hl,x86_bios_trace_history_flags_text
        call    p126_ngs_resident_log
        ld      a,(x86_bios_trace_dump_flags)
        call    x86_bios_trace_emit_hex8
        ld      hl,x86_bios_trace_history_opcode_text
        call    p126_ngs_resident_log
        ld      a,(x86_bios_trace_dump_opcode)
        call    x86_bios_trace_emit_hex8
        ld      hl,x86_bios_trace_history_ss_text
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_dump_ss)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_history_sp_text
        call    p126_ngs_resident_log
        ld      hl,(x86_bios_trace_dump_sp)
        call    x86_bios_trace_emit_hex16
        ld      a,13
        call    x86_bios_trace_emit_char
        ld      a,10
        call    x86_bios_trace_emit_char

        ld      a,(x86_bios_trace_dump_index)
        inc     a
        and     #0F
        ld      (x86_bios_trace_dump_index),a
        dec     b
        jp      nz,.history_loop
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Capture a compact stop event for the DMA diagnostics response.
; A=1 slice budget, 2 guest HLT, 3 opcode/memory fault, 4 reset-vector fault.
x86_bios_trace_capture_event:
        ld      (x86_bios_trace_event_status),a
        ld      hl,(x86_reg_cs)
        ld      (x86_bios_trace_event_cs),hl
        ld      hl,(x86_reg_ip)
        ld      (x86_bios_trace_event_ip),hl
        ret

x86_bios_trace_event_status: db 0
x86_bios_trace_event_cs:     dw 0
x86_bios_trace_event_ip:     dw 0

; Emit the post-instruction CS:IP on the independent NeoGS #EF channel.
x86_bios_trace_log_cs_ip:
        push    af
        push    hl
        ld      hl,x86_bios_trace_cs_ip_prefix
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_cs)
        call    x86_bios_trace_emit_hex16
        ld      a,':'
        call    x86_bios_trace_emit_char
        ld      hl,(x86_reg_ip)
        call    x86_bios_trace_emit_hex16
        ld      a,13
        call    x86_bios_trace_emit_char
        ld      a,10
        call    x86_bios_trace_emit_char
        pop     hl
        pop     af
        ret

; Periodic architectural snapshot while the BIOS is running.
; The RAM-sizing loop must advance BH toward B0h and CX toward zero.
; Keeping these values beside CS:IP distinguishes a slow REP from a stuck
; ADD BH,4/CMP BH,B0/JNZ loop without flooding the terminal per iteration.
x86_bios_trace_log_progress:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl,x86_bios_trace_progress_prefix
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_bx)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_progress_cx
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_cx)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_progress_di
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_di)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_progress_es
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_es)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_progress_flags
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_flags)
        call    x86_bios_trace_emit_hex16
        ld      a,13
        call    x86_bios_trace_emit_char
        ld      a,10
        call    x86_bios_trace_emit_char
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; IN HL=word. Emits four uppercase hexadecimal digits.
x86_bios_trace_emit_hex16:
        ld      a,h
        call    x86_bios_trace_emit_hex8
        ld      a,l
        jp      x86_bios_trace_emit_hex8

; IN A=byte. Preserves AF.
x86_bios_trace_emit_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    x86_bios_trace_emit_nibble
        pop     af
        and     #0F
        jp      x86_bios_trace_emit_nibble

; Dump the complete architectural state at a terminal BIOS stop.
; This distinguishes a guest wait loop from bad register/segment state.
x86_bios_trace_log_registers:
        push    af
        push    bc
        push    de
        push    hl
        ld      hl,x86_bios_trace_regs_ax
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_ax)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_bx
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_bx)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_cx
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_cx)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_dx
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_dx)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_si
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_si)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_di
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_di)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_bp
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_bp)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_sp
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_sp)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_ds
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_ds)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_es
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_es)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_ss
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_ss)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_flags
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_flags)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_bios_trace_regs_opcode
        call    p126_ngs_resident_log
        ld      a,(x86_exec_opcode)
        call    x86_bios_trace_emit_hex8
        ld      a,13
        call    x86_bios_trace_emit_char
        ld      a,10
        call    x86_bios_trace_emit_char
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; Use the same full 00EF diagnostic port as the resident logger.
; Preserve BC because callers may be maintaining loop counters.
x86_bios_trace_emit_char:
        push    bc
        ld      bc,#00EF
        out     (c),a
        pop     bc
        ret

x86_bios_trace_emit_nibble:
        and     #0F
        add     a,'0'
        cp      '9'+1
        jr      c,.hex_digit
        add     a,7
.hex_digit:
        call    x86_bios_trace_emit_char
        ret

x86_bios_trace_probe_byte0: db 0
x86_bios_trace_probe_byte1: db 0
x86_bios_trace_probe_error0: db 0
x86_bios_trace_probe_error1: db 0
x86_bios_trace_probe_prefix: db "[X86 FETCH] B0=",0
x86_bios_trace_probe_second: db " B1=",0
x86_bios_trace_first_number: db 0
x86_bios_trace_first_phys: db 0,0,0
x86_bios_trace_first_region: db 0
x86_bios_trace_first_prefix: db "[X86 STEP ",0
x86_bios_trace_first_csip: db "] CS:IP=",0
x86_bios_trace_first_phys_text: db " P=",0
x86_bios_trace_first_region_text: db " R=",0
x86_bios_trace_first_opcode_text: db " OP=",0
x86_bios_trace_first_ax: db " AX=",0
x86_bios_trace_first_bx: db " BX=",0
x86_bios_trace_first_cx: db " CX=",0
x86_bios_trace_first_dx: db " DX=",0
x86_bios_trace_first_si: db " SI=",0
x86_bios_trace_first_di: db " DI=",0
x86_bios_trace_first_bp: db " BP=",0
x86_bios_trace_first_sp: db " SP=",0
x86_bios_trace_first_ds: db " DS=",0
x86_bios_trace_first_es: db " ES=",0
x86_bios_trace_first_ss: db " SS=",0
x86_bios_trace_first_flags: db " FLAGS=",0

x86_bios_trace_history_index: db 0
x86_bios_trace_dump_index: db 0
x86_bios_trace_record_ptr: dw 0
x86_bios_trace_dump_cs: dw 0
x86_bios_trace_dump_ip: dw 0
x86_bios_trace_dump_cx: dw 0
x86_bios_trace_dump_al: db 0
x86_bios_trace_dump_flags: db 0
x86_bios_trace_dump_opcode: db 0
x86_bios_trace_dump_ss: dw 0
x86_bios_trace_dump_sp: dw 0
x86_bios_trace_io_prefix: db "[IO COUNT] IN=",0
x86_bios_trace_io_out_text: db " OUT=",0
x86_bios_trace_io_last_out_text: db " LAST OUT=",0
x86_bios_trace_pit_out_text: db "[GUEST OUT] 42=",0
x86_bios_trace_io_pit_sep_text: db " 43=",0
x86_bios_trace_io_ppi_sep_text: db " 61=",0
x86_bios_trace_io_in_snapshot: dw 0
x86_bios_trace_io_out_snapshot: dw 0
x86_bios_trace_io_port_snapshot: dw 0
x86_bios_trace_io_last_out_port_snapshot: dw 0
x86_bios_trace_io_last_out_value_snapshot: db 0
x86_bios_trace_io_out42_snapshot: dw 0
x86_bios_trace_io_out43_snapshot: dw 0
x86_bios_trace_io_out61_snapshot: dw 0
x86_bios_trace_history_title: db "[X86 HIST] LAST 16 INSTRUCTIONS (OLDEST FIRST)",13,10,0
x86_bios_trace_history_prefix: db "[X86 HIST] ",0
x86_bios_trace_history_cx_text: db " CX=",0
x86_bios_trace_history_al_text: db " AL=",0
x86_bios_trace_history_flags_text: db " FL=",0
x86_bios_trace_history_opcode_text: db " OP=",0
x86_bios_trace_history_ss_text: db " SS=",0
x86_bios_trace_history_sp_text: db " SP=",0
x86_bios_trace_history: BLOCK 16*13,0

x86_bios_trace_remaining: dw 0,0
x86_bios_trace_executed:  dw 0
x86_bios_trace_active:    db 0
x86_bios_trace_eebf_once: db 0
x86_bios_trace_unexpected_cs_once: db 0
x86_bios_trace_unexpected_cs_log:
        db "[X86 TRACE] FIRST UNEXPECTED CS CHANGE",13,10,0
x86_bios_trace_far_target_prefix:
        db "[X86 TRACE] LAST EA TARGET=",0
x86_bios_trace_far_target_none:
        db "NONE",0
x86_bios_trace_slice_remaining: db 0
x86_bios_trace_stop_kind: db 0
x86_bios_trace_start_log: db "[NGS] X86 BIOS CONTINUOUS EXECUTION START",13,10,0
x86_bios_trace_cs_ip_prefix: db "[X86] CS:IP=",0
x86_bios_trace_progress_prefix: db "[X86 RAMTEST] BX=",0
x86_bios_trace_progress_cx: db " CX=",0
x86_bios_trace_progress_di: db " DI=",0
x86_bios_trace_progress_es: db " ES=",0
x86_bios_trace_progress_flags: db " FLAGS=",0
x86_bios_trace_eebf_log: db "[X86 TRACE] FIRST F000:EEBF SNAPSHOT",13,10,0
x86_bios_trace_fault_log: db "[NGS] X86 BIOS TRACE STOP: OPCODE OR MEMORY FAULT",13,10,0
x86_bios_trace_halted_log: db "[NGS] X86 BIOS EXECUTION HALTED BY GUEST",13,10,0
x86_bios_trace_watchdog_log: db "[NGS] X86 BIOS DIAGNOSTIC STOP",13,10,0
x86_bios_trace_regs_ax:    db "[X86 REG] AX=",0
x86_bios_trace_regs_bx:    db " BX=",0
x86_bios_trace_regs_cx:    db " CX=",0
x86_bios_trace_regs_dx:    db " DX=",0
x86_bios_trace_regs_si:    db " SI=",0
x86_bios_trace_regs_di:    db " DI=",0
x86_bios_trace_regs_bp:    db " BP=",0
x86_bios_trace_regs_sp:    db " SP=",0
x86_bios_trace_regs_ds:    db " DS=",0
x86_bios_trace_regs_es:    db " ES=",0
x86_bios_trace_regs_ss:    db " SS=",0
x86_bios_trace_regs_flags: db " FLAGS=",0
x86_bios_trace_regs_opcode: db " OP=",0

; physical = ((segment << 4) + offset) & 0FFFFFh
x86_cpu_calc_phys:
        push    bc
        ; low byte of segment<<4
        ld      a,l
        and     #0F
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      (x86_phys_addr),a
        ; middle byte = (segment.high<<4) | (segment.low>>4)
        ld      a,l
        rrca
        rrca
        rrca
        rrca
        and     #0F
        ld      b,a
        ld      a,h
        and     #0F
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      b
        ld      (x86_phys_addr+1),a
        ; high nibble
        ld      a,h
        rrca
        rrca
        rrca
        rrca
        and     #0F
        ld      (x86_phys_addr+2),a
        ; add 16-bit offset
        ld      a,(x86_phys_addr)
        add     a,e
        ld      (x86_phys_addr),a
        ld      a,(x86_phys_addr+1)
        adc     a,d
        ld      (x86_phys_addr+1),a
        ld      a,(x86_phys_addr+2)
        adc     a,0
        and     #0F
        ld      (x86_phys_addr+2),a
        pop     bc
        ld      a,(x86_phys_addr+2)
        or      a                       ; return carry clear
        ret


; Classify the 20-bit physical address already stored in x86_phys_addr.
; IN:  x86_phys_addr = low byte, middle byte, high nibble.
; OUT: A = P126_X86_MEM_* region ID.
; The 8086 address helper masks to 20 bits, so all inputs are in range.
x86_mem_classify:
        ld      a,(x86_phys_addr+2)
        cp      #0A
        jr      c,.ram_low
        cp      #0C
        jr      c,.vga_aperture
        cp      #0D
        jr      z,.segment_c
        cp      #0F
        jr      c,.ram_high
        jr      z,.segment_f
        ; Defensive fallback; unreachable for a valid 20-bit address.
        ld      a,P126_X86_MEM_RAM_LOW
        ret
.segment_c:
        ld      a,(x86_phys_addr+1)
        cp      #80
        jr      c,.vga_bios
        jr      .ram_high
.segment_f:
        ld      a,(x86_phys_addr+1)
        cp      #E0
        jr      c,.ram_high
        ld      a,P126_X86_MEM_SYSBIOS
        ret
.ram_low:
        ld      a,P126_X86_MEM_RAM_LOW
        ret
.vga_aperture:
        ld      a,P126_X86_MEM_VGA_APERTURE
        ret
.vga_bios:
        ld      a,P126_X86_MEM_VGABIOS
        ret
.ram_high:
        ld      a,P126_X86_MEM_RAM_HIGH
        ret


; -------------------------------------------------------------------------
; Guest RAM backing access
;
; Guest RAM allocation starts at NeoGS physical page 44h.
; Guest byte address maps linearly to physical offset 110000h + guest address.
; WIN3 is a permanently reserved bank aperture; its current page is volatile.
; These routines do not restore WIN3's previous page because the page port is
; write-only and WIN3 is owned exclusively by this memory backend.
;
; Entry address: x86_phys_addr = low, middle, high-nibble.
; Read returns byte in A, carry clear. Non-RAM overlay regions return carry.
; Write takes byte in A, carry clear on success; non-RAM returns carry.
; -------------------------------------------------------------------------

x86_guest_ram_read8:
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_LOW
        jr      z,.read_map
        cp      P126_X86_MEM_RAM_HIGH
        jr      nz,.read_reject
.read_map:
        call    x86_guest_ram_select_page
        ld      a,(hl)
        or      a
        ret
.read_reject:
        scf
        ret

x86_guest_ram_write8:
        ld      (x86_mem_data),a
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_LOW
        jr      z,.write_map
        cp      P126_X86_MEM_RAM_HIGH
        jr      nz,.write_reject
.write_map:
        call    x86_guest_ram_select_page
        ld      a,(x86_mem_data)
        ld      (hl),a
        or      a
        ret
.write_reject:
        scf
        ret

; Select WIN3 physical page and return HL=C000h|(guest_address&3FFFh).
; Physical page = 44h + guest_address[19:14].
; Clobbers AF, BC, HL; does not touch DE or guest CPU registers.
x86_guest_ram_select_page:
        ld      a,(x86_phys_addr+2)
        add     a,a
        add     a,a
        add     a,P126_NGS_GUEST_RAM_PAGE_BASE
        ld      b,a
        ld      a,(x86_phys_addr+1)
        ; Extract physical address bits 15:14 as the 16 KiB page index.
        ; Six logical shifts are required; two RRCA rotations selected
        ; unrelated bits and sent BIOS/RAM reads to the wrong WIN3 bank.
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        and     #03
        add     a,b
        rrca                            ; MPAGEX selector = physical page rotated right
        out     (P126_NGS_BANK_WINDOW_PORT),a

        ld      a,(x86_phys_addr+1)
        and     #3F
        or      #C0
        ld      h,a
        ld      a,(x86_phys_addr)
        ld      l,a
        ret

; -------------------------------------------------------------------------
; Unified guest memory interface
;
; Guest physical address is classified before selecting its physical backing:
;   00000-9FFFF / C8000-FDFFF : guest RAM, pages 44h-83h
;   A0000-BFFFF               : linear VGA aperture backing, pages 30h-37h
;   C0000-C7FFF               : VGA BIOS slot, pages 20h-21h
;   FE000-FFFFF               : system BIOS slot, page 10h (8 KiB image)
;
; The VGA aperture backend is deliberately a byte-linear staging layer over
; the first 128 KiB of the 256 KiB VRAM allocation. It is NOT yet IBM VGA
; plane/latch/read-mode/write-mode emulation. VGA register semantics are a
; separate implementation stage.
;
; All backing is reached through WIN3. A is the page bias for the address
; formula: page = (guest_high_nibble*4)+(guest_middle>>6)+bias.
; -------------------------------------------------------------------------

x86_guest_mem_read8:
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_LOW
        jr      z,.ram
        cp      P126_X86_MEM_RAM_HIGH
        jr      z,.ram
        cp      P126_X86_MEM_VGA_APERTURE
        jr      z,.vram
        cp      P126_X86_MEM_VGABIOS
        jr      z,.vgabios
        cp      P126_X86_MEM_SYSBIOS
        jr      z,.sysbios
        ; A region outside the configured guest map is a real memory fault.
        ; Emit one compact address/mapping snapshot, then preserve CF=1.
        ld      (x86_mem_fault_region),a
        call    x86_guest_mem_fault_diag
        scf
        ret
.ram:
        jp      x86_guest_ram_read8
.vram:
        jp      x86_vga_mem_read8
.vgabios:
        ld      a,P126_NGS_GUEST_VGABIOS_PAGE_BIAS
        call    x86_guest_mem_select_page
        ld      a,(hl)
        or      a
        ret
.sysbios:
        ld      a,P126_NGS_GUEST_SYSBIOS_PAGE_BIAS
        call    x86_guest_mem_select_page
        ; FE000h is half-way through a 16 KiB guest page. Rebase the
        ; guest-visible 8 KiB BIOS window to offset 0000h in slot page 10h.
        ld      a,h
        sub     #20
        ld      h,a
        ld      a,(hl)
        or      a
        ret

; -------------------------------------------------------------------------
; One-shot diagnostic for rejected guest-memory reads.
; Logs physical address, classifier result, computed NeoGS page/MPAGEX value,
; WIN3 aperture address and the architectural DS:SI source registers.
; This is intentionally fault-only; normal memory accesses remain silent.
; -------------------------------------------------------------------------
x86_guest_mem_fault_diag:
        push    af
        push    bc
        push    de
        push    hl
        ld      a,(x86_mem_fault_diag_once)
        or      a
        jp      nz,.diag_done
        inc     a
        ld      (x86_mem_fault_diag_once),a
        ld      a,(x86_phys_addr+2)
        ld      (x86_mem_fault_page),a
        add     a,a
        add     a,a
        add     a,P126_NGS_GUEST_RAM_PAGE_BASE
        ld      b,a
        ld      a,(x86_phys_addr+1)
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        and     #03
        add     a,b
        ld      (x86_mem_fault_page),a
        rrca
        ld      (x86_mem_fault_selector),a
        ld      a,(x86_phys_addr+1)
        and     #3F
        or      #C0
        ld      (x86_mem_fault_h),a
        ld      a,(x86_phys_addr)
        ld      (x86_mem_fault_l),a

        ld      hl,x86_mem_fault_prefix
        call    p126_ngs_resident_log
        ld      a,(x86_phys_addr+2)
        call    x86_bios_trace_emit_hex8
        ld      a,(x86_phys_addr+1)
        call    x86_bios_trace_emit_hex8
        ld      a,(x86_phys_addr)
        call    x86_bios_trace_emit_hex8
        ld      hl,x86_mem_fault_region_text
        call    p126_ngs_resident_log
        ld      a,(x86_mem_fault_region)
        call    x86_bios_trace_emit_hex8
        ld      hl,x86_mem_fault_page_text
        call    p126_ngs_resident_log
        ld      a,(x86_mem_fault_page)
        call    x86_bios_trace_emit_hex8
        ld      hl,x86_mem_fault_selector_text
        call    p126_ngs_resident_log
        ld      a,(x86_mem_fault_selector)
        call    x86_bios_trace_emit_hex8
        ld      hl,x86_mem_fault_hl_text
        call    p126_ngs_resident_log
        ld      a,(x86_mem_fault_h)
        call    x86_bios_trace_emit_hex8
        ld      a,(x86_mem_fault_l)
        call    x86_bios_trace_emit_hex8
        ld      hl,x86_mem_fault_dssi_text
        call    p126_ngs_resident_log
        ld      hl,(x86_reg_ds)
        call    x86_bios_trace_emit_hex16
        ld      a,':'
        call    x86_bios_trace_emit_char
        ld      hl,(x86_reg_si)
        call    x86_bios_trace_emit_hex16
        ld      hl,x86_mem_fault_cf_text
        call    p126_ngs_resident_log
.diag_done:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

x86_mem_fault_prefix:       db "[X86 MEM FAULT] P=",0
x86_mem_fault_region_text:  db " R=",0
x86_mem_fault_page_text:    db " PAGE=",0
x86_mem_fault_selector_text: db " MP=",0
x86_mem_fault_hl_text:      db " HL=",0
x86_mem_fault_dssi_text:   db " DS:SI=",0
x86_mem_fault_cf_text:      db " CF=1",13,10,0
x86_mem_fault_diag_once:    db 0
x86_mem_fault_region:       db 0
x86_mem_fault_page:         db 0
x86_mem_fault_selector:     db 0
x86_mem_fault_h:            db 0
x86_mem_fault_l:            db 0

x86_guest_mem_write8:
        ld      (x86_mem_data),a
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_LOW
        jr      z,.ram
        cp      P126_X86_MEM_RAM_HIGH
        jr      z,.ram
        cp      P126_X86_MEM_VGA_APERTURE
        jr      z,.vram
        ; Both BIOS regions are read-only. Unknown regions fail closed.
        scf
        ret
.ram:
        ld      a,(x86_mem_data)
        jp      x86_guest_ram_write8
.vram:
        ld      a,(x86_mem_data)
        jp      x86_vga_mem_write8

; Generic WIN3 selector. IN A=page bias; OUT HL=C000h|(guest_address&3FFFh).
; Clobbers AF, BC, HL. The caller's page bias is consumed here.
x86_guest_mem_select_page:
        ld      b,a
        ld      a,(x86_phys_addr+2)
        add     a,a
        add     a,a
        add     a,b
        ld      b,a
        ld      a,(x86_phys_addr+1)
        ; Extract physical address bits 15:14 as the 16 KiB page index.
        ; Six logical shifts are required; two RRCA rotations selected
        ; unrelated bits and sent BIOS/RAM reads to the wrong WIN3 bank.
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        srl     a
        and     #03
        add     a,b
        rrca                            ; MPAGEX selector = physical page rotated right
        out     (P126_NGS_BANK_WINDOW_PORT),a
        ld      a,(x86_phys_addr+1)
        and     #3F
        or      #C0
        ld      h,a
        ld      a,(x86_phys_addr)
        ld      l,a
        ret

; Emit a runtime identity, not merely an assembler-time banner.
x86_cpu_emit_version:
        push    af
        push    hl
        ld      hl,x86_cpu_version_text
.loop:
        ld      a,(hl)
        or      a
        jr      z,.done
        call    x86_bios_trace_emit_char
        inc     hl
        jr      .loop
.done:
        pop     hl
        pop     af
        ret

x86_cpu_version_text:
        defb    "[P126 X86_CPU_STATE v0.3.0]",13,10,0

; Executable target-side test vectors. Does not require BIOS, VGA or a
; selected memory-region map. It must be run before marking BUILD/HARDWARE PASS.
x86_cpu_state_selftest:
        push    af
        push    bc
        push    de
        push    hl
        call    x86_cpu_reset

        ld      hl,(x86_reg_cs)
        ld      de,#FFFF
        or      a
        sbc     hl,de
        jp      nz,.fail
        ld      hl,(x86_reg_ip)
        ld      de,0
        or      a
        sbc     hl,de
        jp      nz,.fail
        ld      hl,(x86_reg_flags)
        ld      de,X86_FLAGS_RESET
        or      a
        sbc     hl,de
        jp      nz,.fail

        ; 0000:0000 = 00000h
        ld      hl,0
        ld      de,0
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_zero
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; FFFF:000F = FFFFFh
        ld      hl,#FFFF
        ld      de,#000F
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_fffff
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; FFFF:0010 wraps to 00000h on the 20-bit bus.
        ld      hl,#FFFF
        ld      de,#0010
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_zero
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; 1234:5678 = 179B8h
        ld      hl,#1234
        ld      de,#5678
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_179b8
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; F000:FFF0 = FFFF0h, the reset-vector physical address.
        ld      hl,#F000
        ld      de,#FFF0
        call    x86_cpu_calc_phys
        ld      hl,x86_expected_ffff0
        call    x86_cpu_check_phys
        jp      nz,.fail

        ; Guest memory decode boundary tests.
        ld      hl,x86_test_9ffff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_LOW
        jp      nz,.fail

        ld      hl,x86_test_a0000
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_VGA_APERTURE
        jp      nz,.fail

        ld      hl,x86_test_bffff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_VGA_APERTURE
        jp      nz,.fail

        ld      hl,x86_test_c0000
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_VGABIOS
        jp      nz,.fail

        ld      hl,x86_test_c7fff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_VGABIOS
        jp      nz,.fail

        ld      hl,x86_test_c8000
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_HIGH
        jp      nz,.fail

        ld      hl,x86_test_fdfff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_RAM_HIGH
        jp      nz,.fail

        ld      hl,x86_test_fe000
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_SYSBIOS
        jp      nz,.fail

        ld      hl,x86_test_fffff
        ld      de,x86_phys_addr
        ld      bc,3
        ldir
        call    x86_mem_classify
        cp      P126_X86_MEM_SYSBIOS
        jp      nz,.fail

        pop     hl
        pop     de
        pop     bc
        pop     af
        or      a
        ret
.fail:
        pop     hl
        pop     de
        pop     bc
        pop     af
        scf
        ret

; IN HL=expected address bytes. Z set iff all three bytes match.
x86_cpu_check_phys:
        push    bc
        push    de
        ex      de,hl
        ld      hl,x86_phys_addr
        ld      b,3
.check:
        ld      a,(de)
        cp      (hl)
        jr      nz,.done
        inc     de
        inc     hl
        djnz    .check
.done:
        pop     de
        pop     bc
        ret

; Stable register names for subsequent instruction-decoder modules.
x86_reg_ax:    dw 0
x86_reg_cx:    dw 0
x86_reg_dx:    dw 0
x86_reg_bx:    dw 0
x86_reg_sp:    dw 0
x86_reg_bp:    dw 0
x86_reg_si:    dw 0
x86_reg_di:    dw 0
x86_reg_es:    dw 0
x86_reg_cs:    dw 0
x86_reg_ss:    dw 0
x86_reg_ds:    dw 0
x86_reg_ip:    dw 0
x86_reg_flags: dw X86_FLAGS_RESET
x86_halted:      db 0
x86_pending_irq: db 0
x86_pending_nmi: db 0
x86_irq_inhibit: db 0
; Set from TF at instruction start; consumed at the following boundary.
x86_tf_pending: db 0
x86_irq_vector: db 8
x86_phys_addr: db 0,0,0
x86_mem_data:  db 0

x86_bios_probe_remaining: db 0
x86_bios_reset_vector_bytes: db 0,0,0,0,0
x86_bios_reset_vector_expected: db #EA,#5B,#E0,#00,#F0
x86_bios_reset_vector_pass_log:
        db "[NGS] X86 BIOS RESET VECTOR FETCH PASS",13,10,0
x86_bios_reset_target_log:
        db "[NGS] X86 FAR JMP DECODED F000:E05B",13,10,0
x86_bios_reset_read_fail_log:
        db "[NGS] X86 BIOS RESET VECTOR READ FAILED",13,10,0
x86_bios_reset_vector_bad_log:
        db "[NGS] X86 BIOS RESET VECTOR MISMATCH",13,10,0

x86_expected_zero:  db 0,0,0
x86_expected_fffff: db #FF,#FF,#0F
x86_expected_179b8: db #B8,#79,#01
x86_expected_ffff0: db #F0,#FF,#0F

; Physical address boundary vectors: low, middle, high-nibble bytes.
x86_test_9ffff:  db #FF,#FF,#09
x86_test_a0000:  db #00,#00,#0A
x86_test_bffff:  db #FF,#FF,#0B
x86_test_c0000:  db #00,#00,#0C
x86_test_c7fff:  db #FF,#7F,#0C
x86_test_c8000:  db #00,#80,#0C
x86_test_fdfff:  db #FF,#DF,#0F
x86_test_fe000:  db #00,#E0,#0F
x86_test_fffff:  db #FF,#FF,#0F
