# Project126 implementation status

This document records actual artifacts and their verification state; it is not a projection of the roadmap.

## ATM host IPC module

- ATM-side source: `atm_host/neogs_ipc.asm`, public interface: `atm_host/neogs_ipc.inc`.
- Assembly unit: `atm_host/neogs_ipc_assemble.asm`, source version `P126 ATM_IPC v0.1.0`.
- Implements bounded CBIT/DBIT polling, command transmission through GSCOM, byte transmission/reception through GSDAT, and an ATM-side version banner on the independent #EF debug port.
- Handshake semantics follow the established Project125 host transport v2 implementation.
- ATM build outputs: `build/ATM_IPC.bin`, `build/ATM.lst`, `build/ATM.map`.
- ATM assembly origin is image-relative `ORG 0000h`; the final host load address is not assigned.
- Not yet implemented: application command schema, versioned request frames, sequence IDs, CRC, retry/deduplication, DMA aperture and host-service ABIs. These remain explicit interface work, not implied by successful assembly.
- Status: **BUILD PASS** for ATM assembly in GitHub Actions run `42274548106` (commit `20f5945e47f118706821d6d47b237be8b9b160a3`); 235 source lines, 0 errors, 0 warnings, 181-byte binary, 14,766-byte listing and 1,407-byte symbol map. No live ATM↔NeoGS hardware test has been performed.

## Build pipeline and address-placement audit

- Assembler: repository-pinned `tools/sjasmplus.exe` (SjASMPlus 1.23.1).
- Local build entry point: `build_project126.bat` (Windows double-click launcher), which invokes `tools/build_project126.ps1`.
- CI: `.github/workflows/neogs-assembly.yml`; CI invokes the same PowerShell build script as a local build.
- Every successful assembly must produce both modules:
  - `build/x86_cpu_state.bin`, `build/NEOGS.lst`, `build/NEOGS.map`;
  - `build/ATM_IPC.bin`, `build/ATM.lst`, `build/ATM.map`.
- The script deletes stale outputs before assembling and fails if any product is missing.
- NeoGS assembly translation unit: `neogs_sub/x86_cpu_state_assemble.asm`, version v0.5.0. It exports explicit start/end labels for the CPU-state and ALU modules and displays each module's start, end and size, plus the complete image end and size.
- NeoGS assembly-time assertions enforce non-empty modules, contiguous placement (ALU begins exactly at CPU-state end), and total image size no greater than 256 KiB.
- ATM assembly translation unit exports the IPC module start/end/size and asserts a non-empty image no larger than 64 KiB.
- **Address-space qualification:** both assembly origins are image-relative offsets, not final physical NeoGS/ATM load addresses. Runtime memory maps and the ATM integration/load point remain to be fixed.
- CI publishes both binaries, listings and maps in one audit artifact.

## Latest verified assembly

- GitHub Actions run `42274548106`, commit `20f5945e47f118706821d6d47b237be8b9b160a3`: SjASMPlus 1.23.1; both modules assembled with 0 errors and 0 warnings.
- NeoGS: 695 source lines, `x86_cpu_state.bin` 1,155 bytes, `NEOGS.lst` 37,553 bytes, `NEOGS.map` 2,732 bytes.
- ATM: 235 source lines, `ATM_IPC.bin` 181 bytes, `ATM.lst` 14,766 bytes, `ATM.map` 1,407 bytes.
- Combined audit artifact `project126-atm-neogs-assembly-audit` uploaded successfully: [workflow run and artifact](https://github.com/JTCyborg/Project126/actions/runs/42274548106).
- This is an assembly/build result only; the IPC handshake has not yet been exercised on physical ATM/NeoGS hardware.

## PCem reference integrity tooling

- `docs/PCEM_REFERENCE_MAP.md`
- `tools/verify_pcem_reference.py`
- Status: committed. The verifier has not yet been executed in a local checkout.
- Purpose: pin the CPU, memory, I/O, interrupt, timer, keyboard and VGA reference files by Git blob identity.

## x86 CPU architectural state foundation

- Source: `neogs_sub/x86_cpu_state.asm`
- Assembly unit: `neogs_sub/x86_cpu_state_assemble.asm`
- Runtime version emitter: `x86_cpu_emit_version`, string `[P126 X86_CPU_STATE v0.1.0]`. Startup call is not wired because the Project126 firmware entry point and NeoGS memory map are not yet defined.
- PCem comparison points: `PCem/808x.c:resetx86()`, `PCem/cpu.h:CPU_8086`.
- Implemented in source: deterministic register reset, 8086 reset vector FFFF:0000, FLAGS=0002h, 20-bit segment:offset physical-address calculation and target-side self-test vectors.
- Status: source assembled successfully in CI run `42273068373`; target-side self-test has not been executed on NeoGS.
- Not implemented by this module: instruction decoding/execution, memory-region mapping, interrupt delivery, timing or device models.

## x86 ALU foundation

- Source: `neogs_sub/x86_alu.asm`, version `P126 / X86_ALU v0.2.0`.
- PCem comparison points: `PCem/808x.c:setadd8()`, `setsub8()` and adjacent flag helpers.
- Implemented in source: 8-bit and 16-bit ADD/SUB; CF, PF, AF, ZF, SF and OF translation into guest FLAGS; preservation of non-arithmetic flags. A runtime version emitter reports the ALU component on NeoGS #EF.
- Included target-side regression vectors: 8-bit and 16-bit signed overflow, carry/borrow, auxiliary carry/borrow, zero, sign, parity and preservation of TF/IF/DF.
- Status: assembled successfully in CI run `42273068373`; target-side regression vectors have not yet been executed on NeoGS.

## Verification policy

A committed source file is not automatically a successful runtime or hardware test. Keep assembly, emulator, NeoGS runtime and ATM hardware results separate. The current CPU-state and ALU modules have BUILD PASS only; they do not yet constitute an executable x86 CPU.


## TR-DOS boot image

- Disk assembly source: `atm_host/project126_disk.asm`.
- BASIC boot loader: `atm_host/boot_loader.asm`, version `P126_TRDOS_BOOT v0.1.0`; based on the proven Project125 boot sequence.
- ATM host application: `atm_host/project126_main.asm`, version `P126_ATM_HOST v0.1.0`; loaded at 6000h and entered at 6009h.
- The disk contains `BOOT.B`, `PROJ126.C`, and `X86CORE.C`.
- Build outputs: root `disk_A.trd`, `build/disk_A.trd`, `build/ATM_DISK.lst`, and `build/ATM_DISK.map`.
- **BUILD PASS:** GitHub Actions run `42275327342`, commit `79b28a4266fdb3cdd151b7842d0b78ed73e5d2c4`. SjASMPlus assembled the disk unit (436 lines) with 0 errors and 0 warnings; image size 655,360 bytes.
- Verified TR-DOS entries: `BOOT.B` 475 bytes / 2 sectors; `PROJ126.C` 248 bytes / 1 sector; `X86CORE.C` 1,155 bytes / 5 sectors.
- [Download TR-DOS disk image and build artifacts](https://github.com/JTCyborg/Project126/actions/runs/42275327342).
- Functional boundary: boot.B loads and starts the ATM host shell. The x86 core is present as a disk file but is not yet transferred to NeoGS or executed.


## ATM native display shell

- Source: `atm_host/p126_screen_console.asm`, adapted from the working Project125 ATM Turbo 2+ 80x25 text console.
- The console module is placed at `#A000`; the host entry remains at `#6009` in the `#6000` image.
- Startup order: emit the ATM/IPC version banners on `#EF`; initialize ATM shadow ports and the 80x25 text mode; clear the display; draw the Project126 status panel; then write the current host/guest state into the lower log.
- The status panel explicitly reports that BIOS is not loaded and x86 execution has not started. The current shell still does not upload or start NeoGS firmware.
- The TR-DOS disk image continues to contain `BOOT.B`, `PROJ126.C`, and `X86CORE.C`.
- This change is intended to address the previously missing on-screen interface. It is not a claim of physical ATM display validation; that requires the user's runtime test.


## ATM host entry diagnostic

- The first instructions at the BASIC USR target `6009h` now emit the single character `>` to the ATM debug port `#EF`, before stack setup, version banners, or display/paging initialization.
- This is a diagnostic marker only; it does not alter `BOOT.B`, its TR-DOS startup trampoline, `CLEAR 24000`, `LOAD`, or the `USR 24585` transfer address.
- Expected runtime sequence: loader's `02` marker, then `>`, then `[P126 ATM HOST v0.1.0]`. Absence of `>` means control did not reach `6009h`, or the ATM #EF output path is not displaying application writes. Presence of `>` but absence of the banner localizes the failure after entry, before/during the string output.
- This diagnostic is not a claim of hardware runtime validation.


## ATM TR-DOS catalogue and BIOS file staging

- Source: `atm_host/p126_disk_catalog.asm`; integration: `atm_host/project126_main.asm`.
- Implemented in source: select TR-DOS drive A, request the directory sectors through the TR-DOS ROM gateway `#3D13`, scan up to 128 directory descriptors, filter supported TR-DOS file types (`B/C/D/#`), display nine rows, maintain a selected entry and scroll the list using the Project125 CAPS SHIFT+7 / CAPS SHIFT+6 matrix combinations.
- Disk image source `atm_host/project126_disk.asm` adds three 8 KiB BIOS files under TR-DOS-compatible names: `BIOS1.C`, `BIOS2.C`, and `COMPAQ.C`. The build script checks that these entries exist and have the expected 8 KiB size.
- **Source implementation committed; BUILD PASS not yet established for this catalogue/BIOS-image revision.** No ATM hardware/runtime directory read has been confirmed. The user's latest runtime report showed only the host and IPC banners and an empty catalogue; therefore directory access and rendering remain **HARDWARE TEST PENDING / FUNCTIONALITY NOT CONFIRMED**.
- Cursor navigation is implemented in source but has not been confirmed on the user's physical keyboard. The current scan is the Spectrum matrix CAPS SHIFT+7/6 convention; it is not yet verified as native PS/2 arrow-key input.
- BIOS selection with Enter and loading the selected BIOS into NeoGS are **NOT IMPLEMENTED**.

## ATM startup and TR-DOS catalogue diagnostics

- Added ATM `#EF` stage messages in `atm_host/project126_main.asm` and `atm_host/p126_disk_catalog.asm`.
- Startup markers identify video initialization begin/end, RTC probe return, console initialization begin/end, and catalogue initialization return.
- Catalogue markers identify entry to catalogue initialization, disk-read entry, drive-select return, directory-read call/return, VG93 idle, I/O success/error, read result, directory scan completion, drawing begin/end, and detected cursor input.
- Latest diagnostic commits: `7bb87ac204bd7a32d4bc62eb0465664482ad6de3` (catalogue stages) and `f03c7999ff3b8f3ae27edfe5a856691c816d5da2` (startup stages).
- These messages are instrumentation only. They do not prove that the TR-DOS read succeeded. The current markers do not yet print the numeric TR-DOS error bytes or the valid-entry count; those values should be added if the next log still does not isolate the cause.
- **Verification state:** source committed; assembly/build and ATM runtime not yet tested for these diagnostic commits. The next required evidence is the complete `#EF` log from a fresh build/run, including the last emitted marker.

## Current work queue (2026-11-06)

| Area | State | Notes |
|---|---|---|
| ATM host entry and version output | IMPLEMENTED IN SOURCE; prior runtime banner observed | User log confirms host and IPC banners. |
| DS12887 RTC integration | IMPLEMENTED IN SOURCE; runtime timestamp previously observed | Uses ATM shadow-port activation and Project125-derived RTC driver. |
| ATM 80x25 status console | IMPLEMENTED IN SOURCE; hardware display validation pending | Catalogue screen currently appears empty per latest user report. |
| TR-DOS directory read | IN PROGRESS / UNVERIFIED | Must inspect stage log and numeric ROM/VG93 error status; no successful directory data confirmed. |
| Directory filtering and nine-row rendering | IMPLEMENTED IN SOURCE; runtime unverified | Depends on successful directory read and correct buffer contents. |
| Cursor navigation | IMPLEMENTED IN SOURCE; runtime unverified | CAPS SHIFT+7/6 matrix combinations. |
| BIOS files in TR-DOS image | IMPLEMENTED IN SOURCE; build verification pending | BIOS1.C, BIOS2.C, COMPAQ.C, each expected 8192 bytes. |
| BIOS selection and transfer to NeoGS | PLANNED | Not implemented; wait until catalogue is proven. |
| NeoGS BIOS receiver / x86 BIOS launch | PLANNED | Requires a defined and tested upload/launch path. |



## TR-DOS access ordering correction (2026-11-06)

- Compared Project126 catalogue access with the working Project125 startup and BIOS sector loader.
- Corrected startup ordering: Project126 now selects the legacy TR-DOS paging state (7FFD=#10, 5C3B=#10, EFF7=0) and reads the directory before ATM video/shadow-port initialization.
- Removed the standalone C=1 drive-select call. It was not part of Project125's proven file-access sequence and was the exact point where the user's runtime log stopped.
- Changed directory reading from one C=5, B=8 call to eight individual C=5, B=1 calls, following Project125's documented one-sector contract. Each call reloads D/E/HL and clears/checks 5D0F/5D10.
- The directory buffer remains at #C800; catalogue parsing, display and keyboard navigation remain in the later UI phase.
- **Verification:** source changes committed. No local SjASMPlus build or ATM hardware run was available for this edit; BUILD PASS and HARDWARE PASS remain unclaimed. Expected log order: TR-DOS DIRECTORY READ BEGIN/RETURN before ATM VIDEO INIT BEGIN.
