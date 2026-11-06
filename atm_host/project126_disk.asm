; =========================================================================
; PROJECT126 — TR-DOS disk image assembly
; Version: P126_TRDOS_IMAGE v0.1.0
;
; Produces disk_A.trd containing:
;   BOOT.B     BASIC boot loader
;   @@HOST_NAME@@.C  ATM host program
;   X86CORE.C  current NeoGS x86 CPU-state/ALU module image
;
; The x86 module is packaged as a disk file, but is not yet auto-uploaded:
; the NeoGS resident command receiver/startup protocol is not implemented.
; =========================================================================

        DEVICE ZXSPECTRUM128
        EMPTYTRD "disk_A.trd"

; -------------------------------------------------------------------------
; ATM resident program, loaded by @@BOOT_NAME@@.B at 6000h.
; -------------------------------------------------------------------------
        PAGE 0
        ORG P126_HOST_LOAD_ADDRESS
        INCLUDE "atm_host/project126_main.asm"

        ASSERT p126_host_program_start = P126_HOST_LOAD_ADDRESS
        ASSERT p126_host_entry = P126_HOST_ENTRY_POINT
        ASSERT p126_host_program_end <= #A800
        SAVETRD "disk_A.trd", "@@HOST_NAME@@.C", P126_HOST_LOAD_ADDRESS, p126_host_program_end-P126_HOST_LOAD_ADDRESS

; -------------------------------------------------------------------------
; TR-DOS BASIC boot program.
; -------------------------------------------------------------------------
        PAGE 0
        ORG #E000
        INCLUDE "atm_host/boot_loader.generated.asm"
        SAVETRD "disk_A.trd", "@@BOOT_NAME@@.B", BASIC_START, BASIC_END-BASIC_START

; -------------------------------------------------------------------------
; NeoGS x86 module. Stored as a standalone CODE file on the TR-DOS disk.
; -------------------------------------------------------------------------
        PAGE 1
        ORG #C000
p126_x86_core_file_start:
        INCBIN "build/x86_cpu_state.bin"
p126_x86_core_file_end:
        ASSERT p126_x86_core_file_end > p126_x86_core_file_start
        ASSERT p126_x86_core_file_end-p126_x86_core_file_start <= #4000
        SAVETRD "disk_A.trd", "X86CORE.C", #C000, p126_x86_core_file_end-p126_x86_core_file_start

; -------------------------------------------------------------------------
; Three 8 KiB BIOS images, packaged under TR-DOS-compatible 8.3 names.
; The long Compaq source filename is represented on disk as COMPAQ.C.
; -------------------------------------------------------------------------
        PAGE 2
        ORG #C000
p126_bios1_file_start:
        INCBIN "bios/27c64d.bin"
p126_bios1_file_end:
        ASSERT p126_bios1_file_end-p126_bios1_file_start = #2000
        SAVETRD "disk_A.trd", "BIOS1.C", #C000, #2000

        PAGE 3
        ORG #C000
p126_bios2_file_start:
        INCBIN "bios/Bios.bin"
p126_bios2_file_end:
        ASSERT p126_bios2_file_end-p126_bios2_file_start = #2000
        SAVETRD "disk_A.trd", "BIOS2.C", #C000, #2000

        PAGE 4
        ORG #C000
p126_bios3_file_start:
        INCBIN "bios/Compaq Portable Plus 100666-001 Rev C.bin"
p126_bios3_file_end:
        ASSERT p126_bios3_file_end-p126_bios3_file_start = #2000
        SAVETRD "disk_A.trd", "disk_A.trd", "COMPAQ.C", #C000, #2000

        PAGE 0
