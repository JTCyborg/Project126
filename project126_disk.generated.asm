; =========================================================================
; PROJECT126 ??? TR-DOS disk image assembly
; Version: P126_TRDOS_IMAGE v0.1.0
;
; Produces disk_A.trd containing:
;   BOOT.B     BASIC boot loader
;   proj126.C  ATM host program
;   X86CORE.C  current NeoGS x86 CPU-state/ALU module image
;
; The x86 module is packaged as a disk file, but is not yet auto-uploaded:
; the NeoGS resident command receiver/startup protocol is not implemented.
; =========================================================================

        DEVICE ZXSPECTRUM128
        EMPTYTRD "disk_A.trd"

; -------------------------------------------------------------------------
; ATM resident program, loaded by boot.B at 6000h.
; -------------------------------------------------------------------------
        PAGE 0
        ORG P126_HOST_LOAD_ADDRESS
        INCLUDE "atm_host/project126_main.asm"

        ASSERT p126_host_program_start = P126_HOST_LOAD_ADDRESS
        ASSERT p126_host_entry = P126_HOST_ENTRY_POINT
        ASSERT p126_host_program_end <= #A800
        SAVETRD "disk_A.trd", "proj126.C", P126_HOST_LOAD_ADDRESS, p126_host_program_end-P126_HOST_LOAD_ADDRESS

; -------------------------------------------------------------------------
; TR-DOS BASIC boot program.
; -------------------------------------------------------------------------
        PAGE 0
        ORG #E000
        INCLUDE "atm_host/boot_loader.generated.asm"
        SAVETRD "disk_A.trd", "boot.B", BASIC_START, BASIC_END-BASIC_START

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

        PAGE 0

