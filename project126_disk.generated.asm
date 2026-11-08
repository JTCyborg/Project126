; =========================================================================
; PROJECT126 ??? TR-DOS disk image assembly
; Version: P126_TRDOS_IMAGE v0.1.0
;
; Produces disk_A.trd containing:
;   BOOT.B     BASIC boot loader
;   proj126.C  ATM host program
;   P126BOOT.C GS105a stage-0 bootstrap
;   X86CORE.C  resident entry, IPC dispatcher and x86 core image
;   X86IO.C    fixed-origin XT PPI/keyboard overlay for WIN2/page 04h
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
; NeoGS stage-0 bootstrap, stored as a standalone TR-DOS CODE file.
; -------------------------------------------------------------------------
        PAGE 5
        ORG #C000
p126_bootstrap_file_start:
        INCBIN "build/P126_BOOTSTRAP.bin"
p126_bootstrap_file_end:
        ASSERT p126_bootstrap_file_end > p126_bootstrap_file_start
        ASSERT p126_bootstrap_file_end-p126_bootstrap_file_start <= #0100
        SAVETRD "disk_A.trd", "P126BOOT.C", #C000, p126_bootstrap_file_end-p126_bootstrap_file_start

; -------------------------------------------------------------------------
; NeoGS resident/x86 core image, loaded into physical WIN0 by P126BOOT.
; -------------------------------------------------------------------------
        PAGE 1
        ORG #C000
p126_x86_core_file_start:
        INCBIN "build/X86CORE.C"
p126_x86_core_file_end:
        ASSERT p126_x86_core_file_end > p126_x86_core_file_start
        ASSERT p126_x86_core_file_end-p126_x86_core_file_start <= #4000
        SAVETRD "disk_A.trd", "X86CORE.C", #C000, p126_x86_core_file_end-p126_x86_core_file_start

; -------------------------------------------------------------------------
; First fixed-origin overlay. ATM streams this file after the resident A2h
; acknowledgement; NeoGS installs it at physical page 04h.
; -------------------------------------------------------------------------
        PAGE 6
        ORG #C000
p126_x86io_file_start:
        INCBIN "build/X86IO.C"
p126_x86io_file_end:
        ASSERT p126_x86io_file_end > p126_x86io_file_start
        ASSERT p126_x86io_file_end-p126_x86io_file_start <= #1000
        SAVETRD "disk_A.trd", "X86IO.C", #C000, p126_x86io_file_end-p126_x86io_file_start

; -------------------------------------------------------------------------
; Second fixed-origin overlay. The host installs it at physical page 05h.
        PAGE 7
        ORG #C000
p126_x86alu_file_start:
        INCBIN "build/X86ALU.C"
p126_x86alu_file_end:
        ASSERT p126_x86alu_file_end > p126_x86alu_file_start
        ASSERT p126_x86alu_file_end-p126_x86alu_file_start <= #1000
        SAVETRD "disk_A.trd", "X86ALU.C", #C000, p126_x86alu_file_end-p126_x86alu_file_start

; Third fixed-origin overlay: 8237 DMA and 8253 PIT guest-device models.
; Reuse build PAGE 7 after X86ALU has already been SAVETRD'd.
        PAGE 7
        ORG #C000
p126_x86dev_file_start:
        INCBIN "build/X86DEV.C"
p126_x86dev_file_end:
        ASSERT p126_x86dev_file_end > p126_x86dev_file_start
        ASSERT p126_x86dev_file_end-p126_x86dev_file_start <= #1000
        SAVETRD "disk_A.trd", "X86DEV.C", #C000, p126_x86dev_file_end-p126_x86dev_file_start

; 8086 instruction dispatcher overlay, pinned to physical page07.
        PAGE 7
        ORG #C000
p126_x86exec_file_start:
        INCBIN "build/X86EXEC.C"
p126_x86exec_file_end:
        ASSERT p126_x86exec_file_end > p126_x86exec_file_start
        ASSERT p126_x86exec_file_end-p126_x86exec_file_start <= #4000
        SAVETRD "disk_A.trd", "X86EXEC.C", #C000, p126_x86exec_file_end-p126_x86exec_file_start

; Dynamic VGA overlay, installed on allocator page08 after readback verification.
        PAGE 7
        ORG #C000
p126_x86vga_file_start:
        INCBIN "build/X86VGA.C"
p126_x86vga_file_end:
        ASSERT p126_x86vga_file_end > p126_x86vga_file_start
        ASSERT p126_x86vga_file_end-p126_x86vga_file_start <= #4000
        SAVETRD "disk_A.trd", "X86VGA.C", #C000, p126_x86vga_file_end-p126_x86vga_file_start

; ATM video frame converter, dynamic module ID06 on allocator page09.
        PAGE 7
        ORG #C000
p126_x86vid_file_start:
        INCBIN "build/X86VID.C"
p126_x86vid_file_end:
        ASSERT p126_x86vid_file_end > p126_x86vid_file_start
        ASSERT p126_x86vid_file_end-p126_x86vid_file_start <= #4000
        SAVETRD "disk_A.trd", "X86VID.C", #C000, p126_x86vid_file_end-p126_x86vid_file_start

; Versioned directory for the currently packaged NeoGS overlay modules (TR-DOS CODE file).
; Runtime parsing/automatic loading is performed by the host loader.
        PAGE 7
        ORG #C000
p126_x86mods_file_start:
        INCBIN "build/X86MODS.MF"
p126_x86mods_file_end:
        ASSERT p126_x86mods_file_end-p126_x86mods_file_start = 7+6*8
        SAVETRD "disk_A.trd", "X86MODS.C", #C000, p126_x86mods_file_end-p126_x86mods_file_start

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
        SAVETRD "disk_A.trd", "COMPAQ.C", #C000, #2000

        PAGE 0

