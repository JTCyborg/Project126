# Project126 implementation status

This document records actual artifacts and their verification state; it is not a projection of the roadmap.

## ATM host IPC transport primitives

- ATM-side source: `atm_host/neogs_ipc.asm`, public interface: `atm_host/neogs_ipc.inc`; assembly unit: `atm_host/neogs_ipc_assemble.asm`.
- ATM source version is now `P126 ATM_IPC v0.2.0`; the common ABI constants are in `shared/p126_ipc_protocol.inc`.
- Existing bounded CBIT/DBIT polling, GSCOM command and legacy GSDAT byte helpers remain available. GSDAT helpers are compatibility/bootstrap primitives, not the application payload transport.
- Added ATM CRC-16/CCITT-FALSE byte-update routine and executable standard-vector self-test (123456789 → 29B1h). Startup does not call the self-test yet.
- Added NeoGS-side counterpart in `neogs_sub/p126_ipc.asm`, with standalone audit unit `neogs_sub/p126_ipc_assemble.asm`; it uses the same shared constants and test vector. This is a reusable primitive, not yet connected to a resident command loop.
- ATM assembly origin remains image-relative `ORG 0000h`; final host load address is not assigned.
- **BUILD PASS:** GitHub Actions run [42303465405](https://github.com/JTCyborg/Project126/actions/runs/42303465405), commit `50bf91bf35a0ef89e5d5ebb128fb36b46ceac479`; SjASMPlus assembly and TR-DOS packaging completed successfully. The build assembles the ATM and NeoGS CRC primitives and publishes the new `P126_NGS_IPC.bin`, `NEOGS_IPC.lst` and `NEOGS_IPC.map` alongside existing artifacts. No live Project126 DMA/IPC hardware test has been performed.

## Unified DMA/IPC ABI 1.0

- Normative specification: `docs/P126_DMA_IPC_PROTOCOL.md`; architecture reference: `SCENARIO.md` section 7.1.1.
- Fixed: control/data plane separation; ATM-facing DMA aperture contract; NeoGS-only DMA register ownership; GSCOM commands E0h..E3h and FFh end marker; 18-byte P126 frame header; little-endian fields; message types/flags; CRC-16/CCITT-FALSE; per-direction sequence rules; duplicate suppression; ordered fragmentation; status codes; initial service namespace; READY/end/CBIT completion lifecycle.
- Added shared constants in `shared/p126_ipc_protocol.inc`, imported by the ATM IPC public include.
- Added CRC update and standard test-vector routines on both endpoints: `atm_host/neogs_ipc.asm` and `neogs_sub/p126_ipc.asm`.
- **IN PROGRESS:** the contract and CRC primitives on both processors are implemented in source. Complete frame encode/decode, DMA send/receive, session negotiation, sequence state, resident NeoGS command endpoint, fragment reassembly and service dispatch remain unimplemented.
- **OPEN / MUST NOT GUESS:** ATM staging-buffer addresses, ATM paging/buffer placement and final DMA window integration. The NeoGS 4 MiB physical allocation is now assigned in docs/P126_NEOGS_MEMORY_MAP.md; NeoGS logical 64 KiB windows and hardware page selection remain open. Project125 physical addresses/layout are reference material, not Project126 allocations.
- **Verification:** BUILD PASS for both CRC primitives and all three assembly units is recorded in run [42303465405](https://github.com/JTCyborg/Project126/actions/runs/42303465405). CRC self-test routines are assembled but have not been executed on target hardware. Complete DMA directions and frame transport are not implemented and are not claimed as Project126 HARDWARE PASS.

## Build pipeline and address-placement audit

- Assembler: repository-pinned `tools/sjasmplus.exe` (SjASMPlus 1.23.1).
- Local build entry point: `build_project126.bat` (Windows double-click launcher), which invokes `tools/build_project126.ps1`.
- CI: `.github/workflows/neogs-assembly.yml`; CI invokes the same PowerShell build script as a local build.
- Every successful assembly must produce all three modules:
  - `build/x86_cpu_state.bin`, `build/NEOGS.lst`, `build/NEOGS.map`;
  - `build/ATM_IPC.bin`, `build/ATM.lst`, `build/ATM.map`;
  - `build/P126_NGS_IPC.bin`, `build/NEOGS_IPC.lst`, `build/NEOGS_IPC.map`.
- The script deletes stale outputs before assembling and fails if any product is missing.
- NeoGS assembly translation unit: `neogs_sub/x86_cpu_state_assemble.asm`, version v0.6.0. It exports explicit start/end labels for the CPU-state and ALU modules and displays each module's start, end and size, plus the complete image end and size.
- NeoGS assembly-time assertions enforce non-empty modules, contiguous placement (ALU begins exactly at CPU-state end), and total image size no greater than 256 KiB.
- ATM assembly translation unit exports the IPC module start/end/size and asserts a non-empty image no larger than 64 KiB.
- **Address-space qualification:** both assembly origins are image-relative offsets, not final physical NeoGS/ATM load addresses. The guest x86 decode map and NeoGS physical allocation are now specified; the NeoGS logical 64 KiB window mapping, final physical load address and ATM integration/load point remain to be fixed.
- CI publishes all three binaries, listings and maps plus the TR-DOS disk image in one audit artifact.

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
| Unified DMA/IPC ABI 1.0 | IN PROGRESS; BUILD PASS for CRC primitives | Contract, common constants and ATM/NeoGS CRC routines assembled; frame codec, DMA endpoints, session/sequence handling and hardware tests remain. |
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


## NeoGS physical RAM allocation v0.1

- Normative map: docs/P126_NEOGS_MEMORY_MAP.md; machine-readable constants/assertions: shared/p126_neogs_memory_map.inc.
- Allocation: 256 physical pages × 16 KiB = 4 MiB. Pages 00–0F resident kernel (256 KiB); 10–1F system BIOS slot (256 KiB); 20–2F separate VGA BIOS slot (256 KiB); 30–3F VGA VRAM (256 KiB); 40–41 ATM presentation frame (32 KiB); 42 DMA backing page (16 KiB); 43 IPC scratch (16 KiB); 44–83 guest RAM backing (1 MiB); 84–FF unassigned reserve (1.9375 MiB).
- This is a physical RAM allocation only. It does not assign guest x86 logical ROM/RAM/device addresses, NeoGS logical Z80 windows, ATM staging addresses or DMA register encoding.
- Build integration: the NeoGS assembly translation unit includes the map constants and checks all region boundaries, adjacency, capacities and the 4 MiB limit with assembler ASSERTs. Existing NEOGS.lst/NEOGS.map therefore include the allocation symbols.
- Physical paging and DMA hardware tests are not claimed. BUILD PASS is pending CI for this commit.


## Guest 8086 memory map and ATM-PC/XT hybrid profile v0.1

- Profile: docs/P126_ATM_PC_PROFILE.md; machine-readable guest map and port constants: shared/p126_x86_machine_map.inc.
- Guest physical space: 1 MiB, 20-bit wrap, no A20. Full 1 MiB NeoGS guest-RAM backing remains allocated. Read/write decode at reset: 00000–9FFFF RAM (640 KiB); A0000–BFFFF VGA aperture (128 KiB); C0000–C7FFF VGA BIOS ROM (32 KiB); C8000–FDFFF upper RAM (216 KiB); FE000–FFFFF system BIOS ROM (8 KiB). Exposed guest RAM total: 856 KiB.
- This is a custom ATM-PC/XT hybrid. The 216 KiB C8000–FDFFF region is intentionally RAM, not a conventional PC option-ROM/UMA reservation. VGA aperture follows PCem VGA GC register 6 mapping; 256 KiB VRAM is separate backing.
- The current 8 KiB XT-compatible system BIOS images map at FE000–FFFFF; reset vector FFFF0 is image offset 1FF0. The 256 KiB NeoGS BIOS slot is storage capacity, not a linear guest ROM aperture. Images larger than 8 KiB need a separate banking/window policy.
- Added x86_mem_classify and target-side boundary vectors for low RAM, VGA aperture, VGA BIOS, upper RAM and system BIOS. Runtime memory handlers are not implemented.
- I/O decode profile reserves PC/XT-style DMA/PIC/PIT/PPI/VGA/FDC and ATA task-file ranges; DS12887-compatible 70h/71h is a custom extension with ATM as the physical time source. All guest I/O remains software-modeled; no direct NeoGS physical IN/OUT.
- BUILD PASS pending CI for the current commit; target execution of the new classifier and any guest BIOS POST/boot are not claimed.


### Verification — guest memory map and ATM-PC/XT hybrid profile

- **BUILD PASS:** GitHub Actions run [42305863741](https://github.com/JTCyborg/Project126/actions/runs/42305863741), source commit `4e4edf3bbe25f6ffbe2e71cb6d51f411f546b440`. NeoGS assembly completed with 0 errors and 0 warnings; the new memory map constants and classifier assembled into `build/x86_cpu_state.bin` (1,416 bytes), with updated `NEOGS.lst` and `NEOGS.map`.
- ATM IPC and NeoGS IPC audit units also assembled successfully. TR-DOS disk packaging completed at 655,360 bytes; BIOS1.C, BIOS2.C and COMPAQ.C were each verified as 8,192 bytes / 32 sectors. Artifact: `project126-trdos-disk-and-build` (run 42305863741).
- The disk packaging assembler emitted one pre-existing path-format warning for the generated source filename containing a backslash; no assembly errors occurred. GitHub runner Node.js deprecation notices are unrelated to project source.
- The new classifier has target-side boundary test vectors in source, but the self-test has not yet been executed on NeoGS. No guest memory read/write runtime, BIOS POST, VGA output, emulator PASS or hardware PASS is claimed.


## Guest RAM banked access layer v0.1

- Assigned NeoGS logical WIN3 (C000h–FFFFh) as the dedicated 16 KiB physical RAM bank window, selected through port 23h. WIN0–WIN2 are reserved for executing resident code, data, stack and interrupt handlers during a banked access.
- Added `x86_guest_ram_select_page`, `x86_guest_ram_read8` and `x86_guest_ram_write8` to the NeoGS x86 state module. Guest RAM backing is linear: NeoGS physical offset 110000h + 20-bit guest physical address, pages 44h–83h.
- RAM helpers check the guest address decoder and reject VGA/ROM overlay regions rather than incorrectly treating them as RAM. They do not yet implement VGA/ROM access.
- Updated `docs/P126_NEOGS_MEMORY_MAP.md` and `SCENARIO.md` with the WIN3 contract and execution constraints.
- **Verification status:** source-level only until CI assembles this revision. No target-side page-switch, read/write retention, interrupt-safety or guest execution test is claimed. Final resident placement in WIN0–WIN2 remains an integration requirement.


### Verification — banked guest RAM access v0.1

- **BUILD PASS:** GitHub Actions run [42306324753](https://github.com/JTCyborg/Project126/actions/runs/42306324753), source commit `d53e16500183f65f76d93f7b02786829f15c3191`.
- NeoGS memory module assembled successfully: 0 errors, 0 warnings, image size 1,492 bytes. Build map confirms bank aperture C000h and WIN3 page-select port 0023h. ATM IPC and NeoGS IPC units also assembled; TR-DOS disk generation and artifact upload completed.
- The disk assembler emitted the existing generated-filename backslash warning; the NeoGS module itself had no warnings.
- **Not yet verified:** actual WIN3 page selection/read/write on NeoGS hardware or a cycle-accurate emulator. No runtime RAM-retention PASS is claimed. The helpers require the resident runtime to keep code, data, stack and interrupt handlers outside WIN3.


## Unified guest memory dispatcher

- Source: `neogs_sub/x86_cpu_state.asm`; shared page-bias constants: `shared/p126_neogs_memory_map.inc`.
- Added byte read/write entry points `x86_guest_mem_read8` and `x86_guest_mem_write8`, dispatching by `x86_mem_classify`.
- RAM accesses use the existing guest RAM backend. VGA aperture accesses use the first 128 KiB of the dedicated VRAM allocation as linear staging. VGA BIOS and system BIOS reads use their independent physical slots; writes to either ROM are rejected.
- The VGA aperture implementation is not a complete VGA memory model: plane/latch/read/write-mode semantics and register-controlled mapping remain pending.
- Scenario and physical map documentation record exact guest-to-NeoGS page mapping and the limitations.
- Verification is pending CI for this commit. No emulator or hardware runtime PASS is claimed.


### Verification — unified guest memory dispatcher

- **BUILD PASS:** GitHub Actions run [42306662917](https://github.com/JTCyborg/Project126/actions/runs/42306662917), source commit `b4b21ff7dcc4a161c9912d03162487e02dc542fb`.
- SjASMPlus 1.23.1 assembled the NeoGS unit with 0 errors and 0 warnings. The x86 state module is 842 bytes; combined x86 state/ALU image is 1,616 bytes. ATM IPC (246 bytes) and NeoGS IPC (65 bytes) also assembled with 0 errors and 0 warnings.
- TR-DOS image generated at 655,360 bytes. `X86CORE.C` is 1,616 bytes / 7 sectors; BIOS1.C, BIOS2.C and COMPAQ.C are each 8,192 bytes / 32 sectors. Listings, maps and disk artifact were published.
- The disk assembler retains one pre-existing generated-path backslash warning; the NeoGS and IPC assembly units report no warnings.
- **Not verified:** actual WIN3 paging/read/write on target hardware, ROM contents in physical slots, guest BIOS POST, VGA plane semantics or scanout. This is BUILD PASS only.


## ABI 1.0 frame validation

- Implemented matching ATM and NeoGS frame validators in `atm_host/neogs_ipc.asm` and `neogs_sub/p126_ipc.asm`.
- Validation covers minimum header length, P126 magic, ABI major/minor, legal message type, reserved flags, exact 18+payload length and full CRC-16/CCITT-FALSE.
- Return convention: carry clear/A=0 valid; carry set/A=ABI status code invalid. Validators are non-reentrant.
- Hardware DMA endpoint, transaction lifecycle, sequence/session state and BIOS service dispatch remain pending. This milestone alone does not claim DMA transport.


## ABI 1.0 validator branch-range follow-up

- CI run `42307162663` still failed at five ATM validator relative branches targeting the shared BAD_MAGIC/BAD_VERSION exits. The earlier correction did not cover those destinations.
- Converted those remaining branches to absolute `JP`; validation semantics are unchanged. Build verification is pending on this commit. Do not treat either prior failed run as BUILD PASS.


## ABI 1.0 DMA endpoint routines

- Added ATM frame sender and NeoGS DMA receive endpoint routines. NeoGS DMA destination is reserved physical page 42h / 108000h; WIN3 maps page 42h only after DMA has been disabled and acknowledged.
- NeoGS receiver is currently an exported callable routine, not yet wired into a resident command dispatcher. ATM DMA-window mapping and physical hardware tests remain outstanding.
- CI verification is pending for this revision. No hardware transfer result is claimed.


## ABI 1.0 — callable NeoGS receive dispatcher linked into core image

- Added `p126_ngs_ipc_dispatch_once`: polls ZXSTAT/CBIT, reads ZXCMD, dispatches E0h to the ATM→NeoGS DMA receiver, and acknowledges unsupported command IDs with `NO_OPERATION`.
- Corrected the receive endpoint return contract: after validation it restores HL=C000h and BC=exact frame size; previously the validator clobbered these registers.
- Corrected the NeoGS version error to use shared ABI status `P126_STATUS_BAD_VERSION`.
- Linked `neogs_sub/p126_ipc.asm` into the assembled `X86CORE.C` image after CPU state and ALU. The standalone IPC audit binary/listing/map remains available.
- **Not implemented:** no resident firmware startup/main loop currently calls `p126_ngs_ipc_dispatch_once`; final WIN0-WIN2 placement, firmware load/entry, and active polling loop remain open. This commit provides a callable dispatcher in the packaged core, not a running resident endpoint.
- **Verification target:** BUILD PASS must confirm the enlarged core and TR-DOS packaging. Hardware tests must exercise E0h READY, DMA payload, FFh completion, CRC acceptance/rejection, timeout cleanup, and WIN3 page mapping. No hardware PASS is claimed.


## Resident startup implementation v0.1.0

- Added GS105a stage-0 source `neogs_sub/p126_bootstrap.asm`, assembled at 4000h and emitted as a bounded `P126BOOT.C` TR-DOS file (maximum one 256-byte sector).
- Added ATM loader `atm_host/p126_neogs_loader.asm`. It locates the exact 8.3 files in the preloaded directory, reads TR-DOS sectors through C=5/B=1, resets/probes the stock GS105a ROM, loads stage-0 with #14, enters it with #13, streams the resident core and requires A2h before reporting success.
- Added resident entry/vector and main polling loop to X86CORE. It establishes WIN0/page00, WIN1/page03, stack 7FFEh, initializes WIN2/WIN3, runs the CRC16 self-test, sends A2h, then continuously polls the ABI 1.0 dispatcher.
- Added P126BOOT.C to the TR-DOS image and build validation. ATM performs startup file reads before video initialization, preserving the established TR-DOS paging order.
- DBIT/GSDAT is explicitly confined to stock-ROM bootstrap; after A2h, application payloads are DMA-only.
- **Not claimed:** no hardware verification yet for GSCTR reset timing, ROM #14/#13 sequence, paging, A2h handshake, DMA timing or frame integrity. The resident loop currently validates incoming frames and logs success/rejection; service dispatch and reverse DMA remain future work.


### Verification — resident startup build

- **BUILD PASS:** GitHub Actions run [42309240393](https://github.com/JTCyborg/Project126/actions/runs/42309240393), source commit `2375b849bd684087b9027262c277b097e46f408e`.
- SjASMPlus 1.23.1: resident/core image 2,356 bytes; ATM IPC 519 bytes; standalone NeoGS IPC 414 bytes; stage-0 bootstrap 175 bytes. All assembly units completed with 0 errors and 0 warnings.
- TR-DOS image: 655,360 bytes. `proj126.C` 17,517 bytes / 69 sectors; `X86CORE.C` 2,356 bytes / 10 sectors; `P126BOOT.C` 175 bytes / 1 sector; each BIOS image 8,192 bytes / 32 sectors. The disk assembly retains one pre-existing generated-path backslash warning.
- **BUILD PASS only.** No emulator or hardware boot/DMA test has been run.


## Automatic first-frame DMA smoke test

After resident startup and ATM video initialization, the host now builds an 18-byte ABI 1.0 diagnostics request (sequence 0001h, empty payload), calculates CRC-16/CCITT-FALSE with the production ATM routine and sends it through `p126_ipc_dma_send_frame`. This exercises E0h, READY/CBIT, the complete 18-byte DMA write, FFh and completion acknowledgement. The NeoGS resident independently validates the frame and logs either `DMA FRAME VALID` or `DMA FRAME REJECTED`.

The ATM log `DMA SMOKE FRAME SENT` means the transport handshake completed; it is not by itself proof of receiver CRC acceptance. Compare it with the independent NeoGS #EF diagnostic. This is a target-side smoke test, not a build-time test.


## NeoGS startup failure-stage diagnostics (2026-11-07)

- The target log confirms TR-DOS directory access and ATM UI continue, but `p126_neogs_startup` returns carry before resident-ready acknowledgement. No DMA smoke frame is attempted in this state.
- Added loader stage tracking and explicit `[BOOT] NGS FAIL STAGE=x`: 1 bootstrap file locate/read; 2 bootstrap metadata; 3 NeoGS reset/RAM probe; 4 ROM #14 upload; 5 resident file locate/read; 6 resident length validation; 7 ROM #13/A1h handshake; 8 resident length/A3h handshake; 9 resident stream/TR-DOS sector reads; 0 resident A2h/ready.
- The existing generic failure message and startup order are retained. This change diagnoses rather than presumes the failing operation.
- **Verification:** pending CI. No hardware fix or ROM/DMA runtime PASS is claimed. The next target log should include the stage character.


## GS105a stage-3 cold-start recovery (2026-11-07)

- Updated `atm_host/p126_neogs_loader.asm` to use GS105a ROM command `#F4` for cold restart, extended CBIT polling and the `#20` RAM-size probe.
- Added one cold-restart/probe retry for the stale-DMA-end-marker case documented by the working Project125 driver.
- Added a `#0400` DBIT turnaround delay after each received ROM byte.
- Preserved Project126's 4 MiB RAM requirement (`RAM size high byte >= #40`); Project125's 2 MiB threshold is not used.
- Runtime outcome remains **NOT VERIFIED** until the updated TR-DOS image is run on the target ATM. Required next evidence: stage 3 clears and the log reaches stage 4 or later.


## Stage-3 diagnostic subdivision (2026-11-07)

- Replaced the single stage-3 marker with operation-level markers A-H, preserving the existing failure reporting mechanism.
- A=initial #F4/CBIT; B=RAM probe entry; C=#20/CBIT; D/E/F=RAM-size bytes 0/1/2; G=4 MiB threshold validation; H=retry #F4.
- The next target run must report the letter after `NGS FAIL STAGE=`; this identifies the last operation entered, not a claim that the operation completed.
- No hardware runtime result is inferred from this instrumentation.


## GS105a #20 raw RAM-size diagnostics (2026-11-07)

- Added ATM-side HEX output of all three bytes returned by the stock ROM's `#20` RAM-size command: `[NGS ROM] RAM24=HH:MM:LL`. The message is written directly by ATM to its own #EF channel and is emitted before the 4 MiB threshold check.
- Kept the Project126 minimum at 4 MiB; no threshold relaxation or inferred RAM-size correction was made.
- At this point the stock GS105a ROM, not Project126 firmware, owns the NeoGS CPU. Therefore a Project126 `[NGS]` message cannot be produced during this exchange. NeoGS-side diagnostics are independent and begin only after Project126 bootstrap is uploaded and entered.
- **Verification:** source change pending CI and target run. The raw byte values and whether the threshold passes remain unknown until the user tests the new TR-DOS image.


## Архитектурное решение: Project126 не зависит от объёма, сообщаемого штатным ROM

**Решение зафиксировано 2026-11-07; имеет приоритет над предыдущими записями о пороге GS105a #20.**

- Штатное GS105a ROM используется только как временный транспорт первоначальной загрузки: #14 загружает Project126 bootstrap, #13 передаёт ему управление.
- После старта bootstrap отключает штатное ROM через GSCFG0 (#0F), NOROM bit 0. В текущем исходнике neogs_sub/p126_bootstrap.asm это уже выполняется инструкцией or #09 после чтения/маскирования GSCFG0; bit 3 EXPAG также устанавливается.
- ATM loader сейчас ошибочно требует, чтобы ответ ROM #20 имел high byte не меньше #40, и завершает запуск до загрузки собственного bootstrap. Это условие признано устаревшим и должно быть удалено из рабочего загрузочного пути. ROM #20 может оставаться только необязательной диагностикой, не влияющей на решение о запуске.
- После передачи управления собственная прошивка должна выполнить независимое обнаружение/тестирование физической RAM и управлять страницами самостоятельно.
- Целевой диапазон: 4 MiB / 256 страниц по 16 KiB (000000h–3FFFFFh). Действующая карта распределяет страницы 00h–83h, а 84h–FFh помечает резервом. Резерв — свободное распределение, не аппаратное ограничение.
- Необходимо разработать безопасный полный тест всех 256 страниц с проверкой записи/чтения и целостности, исключив повреждение кода, стека и активных DMA/IPC областей.
- ROM-ответ 3F:40:00 — только наблюдение старого ROM (4,145,152 байта); он не доказывает, что физически отсутствуют три верхние страницы. Версия ROM не является входным условием Project126.
- **Статус реализации:** архитектурное решение принято; загрузчик ATM ещё содержит старую проверку и требует изменения. Наличие NOROM в bootstrap подтверждено исходным кодом, но фактическое отключение ROM и полный тест 4 MiB на оборудовании пока не подтверждены. BUILD/HARDWARE PASS не заявляются.


## Independent NeoGS debug stream; ROM RAM-size probe removed from startup gate (2026-11-07)

- Diagnosis: the user's log stopped at stage G, the ATM-side GS105a #20 4 MiB threshold check. Project126 bootstrap had not been entered, so no Project126-originated NeoGS #EF message was possible. The existing resident image already contains direct NeoGS #EF messages (`P126 RESIDENT`, `ABI CRC16 PASS`, DMA frame valid/rejected), but those occur only after successful stage-0 and resident streaming.
- ATM loader now retains GS105a cold restart #F4 but skips #20 entirely and no longer gates Project126 startup on stock-ROM RAM reporting.
- `neogs_sub/p126_bootstrap.asm` now emits `[NGS] BOOTSTRAP ENTER` directly to NeoGS #EF and `[NGS] NOROM ENABLED` after writing GSCFG0 with NOROM/EXPAG bits. ATM does not synthesize these messages.
- Expected NeoGS diagnostics after target run: BOOTSTRAP ENTER -> NOROM ENABLED -> P126 RESIDENT v0.1.0 -> ABI CRC16 PASS. These are separate from the ATM #EF stream.
- **Status:** source changes committed; CI/build and one-sector bootstrap size verification pending; target hardware verification pending. The actual 4 MiB page test is not implemented by this diagnostic change.


### Follow-up: stage-7 failure and bootstrap stack initialization

- The current ATM loader sets startup stage `'7'` immediately before sending the low address argument and GS105a `#13` jump command for stage-0 at `4000h`; it then waits for bootstrap `A1h`. `NGS FAIL STAGE=7` therefore localizes the failure to the jump/initial bootstrap-ready handshake, not to the removed stock-ROM #20 RAM-size gate.
- Inspection found the newly added bootstrap logger was called before Project126 established its own stack. The bootstrap now initializes `SP=#FFFE` immediately after `DI`, before any `CALL`/`PUSH`; the old later initialization was removed.
- This source correction is committed, but no assembly build or hardware pass is claimed yet. On the next target run, `[NGS] BOOTSTRAP ENTER` is the decisive marker for successful execution of the first Project126 bootstrap instructions.

- Comparison against Project125 identified a concrete transport bug in Project126: `p126_neogs_send_argument` did not preserve A across `p126_neogs_wait_dbit_clear`, which overwrites A with GSSTAT. Project125's corresponding `gs_boot_write_command_argument` stores the argument before the wait and restores it before `OUT GSDAT`. Project126 now follows that proven sequence, fixing the first argument byte for both `#14` RECEIVE BLOCK and `#13` JUMP. Build/hardware confirmation is pending.

- Project126 bootstrap startup now follows Project125's validated ordering: temporary stack at `#3FFF`, direct entry marker, ZX DMA disable, settle delay, NOROM/EXPAG and window mapping, then `SP=#FFFE` after WIN3 is selected. This complements the command-argument preservation fix. Assembly and physical-board verification for these latest commits are pending.


## Project125 loader parity — 256-byte stage-0 boundary (2026-11-07)

- The target reported `NGS FAIL STAGE=2`. In the active Project126 loader, stage 2 is the P126BOOT.C byte-length validation immediately after the file is opened; it occurs before GS105a cold restart, ROM #14 upload, or ROM #13 jump.
- GitHub Actions run [42314399945](https://github.com/JTCyborg/Project126/actions/runs/42314399945) completed BUILD PASS and logged `P126_GS105A_BOOTSTRAP bytes=256` and `P126BOOT.C: 256 bytes, 1 sectors`. The build script allowed 1..256 bytes, but the loader's stage-2 check required the high length byte to be zero, thereby rejecting the valid exact length 0100h.
- Corrected stage-2 validation to accept lengths 1..255 and exactly 256, while rejecting zero and values above 256. The existing #14 header already encodes a 256-byte block as the 16-bit negative length FF00h and streams exactly 256 bytes from the first TR-DOS sector.
- This is a direct correction of the observed stage-2 failure. It does not claim that #14, #13, bootstrap entry, resident transfer, BIOS loading, or hardware execution have passed; those are later stages and require a new target log.
- Reference behavior inspected in Project125: `zx_main/neogs_driver.asm` uses the same 256-byte #C000 sector buffer and encodes #14 length as a 16-bit negative value before issuing RECEIVE BLOCK. Project125 also supports repeated sector-sized chunks for larger loader files; Project126 currently intentionally constrains its stage-0 image to one 256-byte block.


## DMA smoke-test stage diagnostics and receiver acknowledgement fix (2026-11-07)

- ATM sender records stage 1 (local frame validator), 2 (frame/aperture size), 3 (E0 command and READY wait), 4 (DMA payload copy), or 5 (FF end marker and final completion wait). On successful return the stage resets to zero. ATM prints [BOOT] DMA FAIL STAGE=n on its own #EF stream when the smoke test fails.
- NeoGS now logs E0 command reception, DMA armed/READY, and FF/end detection directly through the resident logger on NeoGS's independent #EF port. The resident main loop retains its existing DMA FRAME VALID and DMA FRAME REJECTED outcome messages.
- Fixed the receiver lifecycle against ABI 1.0 section 3.1: CBIT is no longer cleared immediately when FFh is detected. DMA is stopped, page 42h is mapped, frame length and CRC are validated, and only then is CBIT cleared. Malformed-length and validation-error paths also clear CBIT after recording the failure; timeout still disables DMA before releasing the host.
- Verification status: source-level change only until the corresponding GitHub Actions build completes. Hardware READY/payload/FF/CRC exchange remains unverified. The next target log must correlate both independent #EF streams; no DMA PASS is inferred from ATM alone.


## NeoGS IPC standalone build dependency correction (2026-11-07)

- Build log exposed that `p126_ipc.asm` is assembled independently as `NEOGS_IPC` as well as included by the resident core. Calls from this shared source to `p126_ngs_resident_log` failed in the standalone assembly because that symbol belongs to the other assembly unit.
- Replaced those references with a self-contained `p126_ngs_ipc_log` routine inside the IPC module. It writes directly to NeoGS's independent `#EF` output and preserves AF/BC, so the same source assembles in both contexts.
- The fix addresses the exact undefined symbol errors reported by the local SjASMPlus build. Full build/CI confirmation remains pending.


## ATM frame-validator CRC pointer correction (2026-11-07)

- Latest hardware evidence: resident startup, ABI CRC self-test, ATM video/RTC/console/catalog all complete; the DMA smoke test fails at `DMA FAIL STAGE=1`.
- Stage 1 is the ATM-local call to `p126_ipc_validate_frame`, before the E0h command or DMA handshake. The NeoGS DMA receiver has not yet been exercised by this attempt.
- Found and corrected a pointer-clobber defect in the ATM CRC validator: an `EX DE,HL` moved the frame pointer out of DE, then `LD HL,#FFFF` overwrote it. The CRC loop consequently read from address 0000h. DE now remains the frame pointer throughout header CRC processing.
- **Verification:** source correction committed; local SjASMPlus/build and target rerun are still required. Do not claim DMA hardware PASS. If stage 1 clears, the next diagnostic stage is 2 (size), then 3 (E0h/READY), 4 (copy), and 5 (FF/completion).


## DMA stage-1 validator error reporting (2026-11-07)

- After the previous CRC pointer correction, the target still reports `DMA FAIL STAGE=1`. This proves only that local ATM validation is failing; no E0h or DMA transfer has been attempted.
- Added capture of the ATM validator's A/status return and a hexadecimal ATM #EF line `[BOOT] DMA VALIDATOR ERROR=xx` after the stage report. This distinguishes BAD_MAGIC, BAD_VERSION, BAD_FRAME and CRC_ERROR without attributing the error to NeoGS.
- **Verification:** diagnostic instrumentation committed; assembly and hardware rerun are pending. The next log must include the validator status before the underlying rejection can be corrected conclusively.


## DMA/IPC end-to-end trace instrumentation (2026-11-07)

- Added ATM-local #EF markers around DMA sender entry, local frame validation, E0 issue/acknowledgement, DMA-window copy, FF issue, and final acknowledgement. E0 and FF timeout paths now emit distinct ATM diagnostics.
- Added independent NeoGS #EF markers around E0 dispatch, DMA register setup/arming, READY/CBIT release, host-end detection, DMA stop, page-42 mapping, frame validation, and timeout/length-error paths. NeoGS frame rejection includes the ABI status byte in hexadecimal.
- The two streams remain physically independent; ATM messages are not forwarded or re-labelled as NeoGS messages.
- Fixed the NeoGS CRC validator's frame-pointer clobber (the same class of defect previously fixed in ATM) and corrected both validators to start payload CRC at frame offset 18 rather than offset 16.
- Logging is at transaction boundaries, not inside polling loops. It still adds latency around DMA copy; timing-sensitive behavior must be checked on target hardware.
- **Verification:** GitHub Actions run [42351776510](https://github.com/JTCyborg/Project126/actions/runs/42351776510), commit `d9b2a391ddaf0bbf4ccd918b34a58cbecc17f40e`, completed successfully. ATM IPC and NeoGS assembly, including the new trace code, passed; TR-DOS image packaging and artifact publication also completed. This is BUILD PASS only. No hardware trace or DMA runtime PASS is claimed.


### 2026-11-07 — локализация ATM CRC_ERROR и сверка с Project125

- **Аппаратный лог пользователя:** ATM выводит `[ATM IPC] FRAME VALIDATION FAILED`, затем `DMA FAIL STAGE=1` и `DMA VALIDATOR ERROR=04`. Это `P126_STATUS_CRC_ERROR`; отказ происходит в локальном ATM валидаторе до команды E0. NeoGS receiver и DMA engine на этом запуске ещё не задействованы.
- **Сверка с Project125:** изучены `PROJECT125_DMA_IPC.md`, `NeoGS/dma_zx_doc.txt`, `NeoGS/ports.inc`, `zx_main/neogs_transport_v2.asm` и `shared/neogs_io.inc`. Для ATM→NeoGS запись Project125 использует host write в DMA aperture `0000h..3FFFh`; NeoGS настраивает DMA module 1, HAD/MAD/LAD и CST bit 7. Dummy read из документа относится к обратному направлению NeoGS→ATM; dummy write перед ATM→NeoGS не требуется. Отдельно учтено предупреждение Project125 о задержке после включения DMA в сценариях, где управление DMA идёт через штатный GS105a ROM. Текущий P126 обмен выполняется уже резидентной прошивкой, поэтому это предупреждение проверяется на аппаратном этапе, а не объявляется причиной текущего CRC отказа.
- **Изменено:** `atm_host/neogs_ipc.asm` — перед сравнением CRC теперь выводятся две независимые величины: CRC, рассчитанный ATM валидатором, и CRC, сохранённый в байтах 16–17 кадра. Это позволит определить, ошибка ли в вычислении или в подготовке/записи кадра.
- **Эталон smoke frame:** первые 16 байт `50313236010001050000010000000000`; CRC-16/CCITT-FALSE должен быть `FF5B`, хранение little-endian — `5B FF`. Это рассчитано независимо и соответствует стандартному алгоритму Project125 bootstrap.
- **Следующий диагностический критерий:** сравнить в новом логе `CRC CALCULATED=FFFF`-формат и `FRAME CRC=FFFF`-формат. Если отличаются — локализовать вычисление/подготовку; если оба `FF5B`, но валидатор всё равно возвращает 04 — проверять саму последовательность сравнения/адресацию.
- **Статус:** исходная аппаратная ошибка подтверждена логом; диагностический патч требует сборки и повторного запуска. DMA аппаратный PASS не заявляется.
