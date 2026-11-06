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

- Sources: `atm_host/p126_disk_catalog.asm`, `atm_host/project126_main.asm`, and `atm_host/project126_disk.asm`.
- Implemented: early TR-DOS directory read before ATM video/shadow-port initialization; eight individual one-sector reads (`C=5, B=1)); directory buffer at `#C800..#CFFF`; directory parsing (up to 128 descriptors); filtering of supported TR-DOS file types (`B/C/D/#`); nine visible rows; selected-entry tracking and scrolling with CAPS SHIFT+7 / CAPS SHIFT+6.
- The TR-DOS image contains three 8 KiB BIOS images under TR-DOS names: `BIOS1.C` (from `bios/27c64d.bin`), `BIOS2.C` (from `bios/Bios.bin`), and `COMPAQ.C` (from `bios/Compaq Portable Plus 100666-001 Rev C.bin`).
- **BUILD PASS:** GitHub Actions run [42302005699](https://github.com/JTCyborg/Project126/actions/runs/42302005699), commit `94c7436a258ccab48182f72446609738ec7e80ca`; assembly/package workflow completed successfully, including ATM/NeoGS assembly and TR-DOS disk creation, and published binaries, listings, maps and disk image.
- **HARDWARE PASS (catalogue stage):** the user explicitly confirmed that this part works on the target ATM. This confirmation covers the working directory/catalogue path and the currently implemented list interaction; it does not validate BIOS transfer or x86 execution.
- BIOS selection confirmation and transfer to NeoGS are **NOT IMPLEMENTED**. ENTER was proposed as the confirmation/start key, but has not yet been bound in code.

## ATM startup and TR-DOS catalogue diagnostics

- ATM `#EF` stage diagnostics remain in `atm_host/project126_main.asm` and `atm_host/p126_disk_catalog.asm`; they identify startup, disk-read, directory-scan, drawing and keyboard-input stages.
- The earlier diagnostic commits `7bb87ac204bd7a32d4bc62eb0465664482ad6de3` and `f03c7999ff3b8f3ae27edfe5a856691c816d5da2` were superseded by the TR-DOS access-ordering corrections recorded below.
- The former failure state (catalogue empty / disk-read stage unresolved) is closed by the later successful build and the user's hardware confirmation. Do not treat old diagnostic notes as the current state of the catalogue.

## Current work queue (2026-11-06)

| Area | State | Notes |
|---|---|---|
| ATM host entry and version output | HARDWARE CONFIRMED | Host and IPC banners observed in the user's runtime log. |
| DS12887 RTC integration | HARDWARE CONFIRMED IN PRIOR RUN | ATM shadow-port activation and Project125-derived read-only RTC path; valid timestamp was previously observed. |
| ATM 80x25 status console | HARDWARE CONFIRMED FOR CURRENT CATALOGUE UI | The catalogue interface is displayed on the target ATM. |
| TR-DOS directory read | HARDWARE PASS | Early read before ATM video init; eight individual C=5, B=1 sector reads. User confirmed operation. |
| Directory filtering, rendering and scrolling | HARDWARE PASS | Nine-row catalogue and CAPS SHIFT+7/6 navigation confirmed by user. |
| BIOS images in TR-DOS disk | BUILD PASS | BIOS1.C, BIOS2.C and COMPAQ.C, each 8192 bytes; included in successful disk build. |
| BIOS choice on ENTER | PLANNED | ENTER is the proposed confirmation key only; no selection/confirmation handler implemented yet. |
| BIOS file transfer ATM → NeoGS | PLANNED | Transfer mechanism and buffer/address contract must be checked against the approved IPC/DMA architecture before implementation. |
| NeoGS BIOS receive, validation and x86 handoff | PLANNED | Receiver, integrity check, BIOS placement in the custom 1 MiB guest memory map, and execution entry remain unimplemented. |
| Full x86 BIOS boot | PLANNED | Not demonstrated by this catalogue milestone. |



## TR-DOS access ordering correction (2026-11-06)

- Compared Project126 catalogue access with the working Project125 startup and BIOS sector loader.
- Corrected startup ordering: Project126 selects the legacy TR-DOS paging state (`7FFD=#10`, `5C3B=#10`, `EFF7=0`) and reads the directory before ATM video/shadow-port initialization.
- Removed the standalone `C=1` drive-select call; it was not part of Project125's proven file-access sequence.
- Replaced one `C=5, B=8` call with eight individual `C=5, B=1` calls. Each call reloads D/E/HL and clears/checks `#5D0F/#5D10`.
- Directory buffer: `#C800..#CFFF`; parsing, display and keyboard navigation run in the later UI phase.
- **Verification:** commits `94c7436a258ccab48182f72446609738ec7e80ca`, `591c00eed1227bc89ecbf9658942297ac6867193`, and `ea916953044349e68ef3cc8af93fc8f5020b483e`. GitHub Actions run [42302005699](https://github.com/JTCyborg/Project126/actions/runs/42302005699) completed successfully. The user subsequently confirmed the catalogue stage on physical ATM hardware.
