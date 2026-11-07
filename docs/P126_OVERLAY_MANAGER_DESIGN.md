# Project126 — Overlay / Module Manager design

**Revision:** 0.1  
**Date:** 2026-11-07  
**Status:** two pinned fixed-origin overlays (X86IO and X86ALU) plus resident WIN2 gate are implemented and CI-built; dynamic allocator/manifest and physical target validation remain pending

## 1. Purpose

The resident `X86CORE.C` has a hard 16 KiB loader limit. The current overlay-gate build produces a 15,610-byte resident image (774 bytes free), a 796-byte `X86IO.C` module and a 1,175-byte `X86ALU.C` module at logical origin `8000h`. The NeoGS physical map reserves pages `00h–0Fh` (256 KiB) for the kernel/runtime.

The manager must use that existing allocation without changing the physical map, enlarging the `X86CORE.C` limit, taking ownership of WIN3, or moving the operational stack.

This document records the source-backed design direction and the remaining validation gates. It is not a claim that an overlay loader or runtime manager is already implemented.

## 2. Verified current layout

- Stage-0 is assembled at `4000h`, loaded by the GS105a ROM path, and receives one resident image through the bootstrap DBIT byte channel.
- Stage-0 currently accepts a nonzero image length up to `4000h`, copies it to logical `0000h`, then jumps to `0000h`.
- The resident image is assembled at `ORG 0`; it contains the resident dispatcher, CPU state, execution, ModR/M, IPC and the WIN2 call gate. `x86_io.asm` and `x86_alu.asm` are assembled at the same logical `ORG 8000h` into separate files; X86IO is installed at page04 and X86ALU at page05. Both public API sets use resident wrappers.
- Resident startup maps WIN0 to physical page `00h`, WIN1 to page `03h`, WIN2 initially to page `01h`, and initializes WIN3 to page `02h`. The operational stack is `7FFEh` in WIN1/page 03. After X86IO IMAGE_FINISH, WIN2 is mapped to physical page `04h`.
- WIN3 (`C000h–FFFFh`) is exclusively owned by the guest physical-memory backend. Its mapping is volatile and is never used as an overlay execution window.
- Kernel pages `00h–0Fh` are allocated. Page 03 contains the operational stack and narrow diagnostic buffers. Page 00 contains the resident image; page 03 contains the operational stack and fixed data; page 04 holds X86IO and page 05 holds X86ALU. The initial WIN2/WIN3 mappings are page 01/page 02.
- A source scan of the CPU/IPC translation units found no fixed data operands in logical `8000h–BFFFh`; the range is now used as the fixed-origin X86IO execution/data aperture. The assembled overlay occupies `8000h–831Bh` (796 bytes).

## 3. Candidate execution aperture

Use WIN2 (`8000h–BFFFh`, 16 KiB) as the fixed-origin overlay execution/data aperture. The current implementation switches between the two pinned overlays through the resident gate; pages 06h–0Fh are not yet dynamically allocated.

Rationale:

1. Resident code and fixed dispatcher remain in WIN0/page 00.
2. The operational stack remains in WIN1/page 03.
3. Guest memory access continues to own WIN3 exclusively.
4. An overlay can execute at a fixed logical origin (`8000h`) while its physical backing page is selected from the kernel pool.
5. X86IO implementation symbols occupy `8000h–831Bh` on page04; X86ALU occupies `8000h–8496h` on page05. Both public CPU-facing APIs use resident wrappers. The resident call gate saves the current WIN2 selector on the WIN1 stack, maps the requested page, enters through IX, and restores the previous selector at a resident RET trampoline. The gate is source-built but has not yet passed a physical nested-switch test.

Candidate physical overlay pool: pages `04h–0Fh` (12 pages, 192 KiB). Pages 04h and 05h are pinned to X86IO and X86ALU; pages 06h–0Fh remain unallocated for future overlays. Pages 00–03 are excluded from allocation. No dynamic allocator exists yet.

### Mapping register gate

Project125's checked-in `neogs_sub/bank_gateways.asm`, `neogs_sub/main.asm`, `shared/neogs_io.inc` and `PROJECT125_MEMORY_LAYOUT.md` establish the NeoGS mapping contract: WIN2 is selected by MPAG port `#00`; the selector is `ROR8(physical_page)` (one `RRCA`). The Project126 startup write `OUT (#00),#80` is therefore consistent with WIN2→physical page 01h. Project125's resident bank gateways also demonstrate the required pattern: switch MPAG, CALL the banked entry, restore the caller's bank before RET. Project125 uses pages 68h/69h for its own map; those page numbers and its device/memory backend are not copied into Project126.

For Project126, the selector formula is source-backed and used by the first loader: page 04h is selected with `02h` (`RRCA`). Physical target validation of WIN2 mapping and persistence is still required. WIN3's MPAGEX `#10` remains separate and is not touched by the WIN2 mapping operation.

## 4. Module format and linking model

### 4.1 Fixed load origin

Each overlay is assembled for logical origin `8000h`. The module body is limited to one 16 KiB physical page. The module must not contain code/data references into WIN2 that are expected to survive while a different overlay is mapped.

The preferred first linking strategy is a single SjASMPlus translation unit with explicit resident and overlay ORG regions. This allows the assembler to resolve references from overlay code to fixed resident symbols without inventing a runtime relocation format. Separate `SAVEBIN` outputs produce the resident image and overlay file(s). The build must assert that the resident output remains <= `4000h` and each overlay body remains <= `4000h`.

If later modules require independent compilation, introduce an explicit relocation table and linker validation as a separate versioned format; do not silently depend on unresolved assembler symbols.

### 4.2 Proposed manifest

A module file will carry a small fixed manifest followed by the page image. The manifest must identify:
- magic and format revision;
- module ID and required resident ABI revision;
- physical destination page (restricted to the approved kernel overlay pool);
- image length and entry offset;
- module flags/capabilities;
- whole-image checksum.

The proposed standalone manifest is not implemented. The current fixed profiles use ABI 1.0 IMAGE metadata (kind, message ID, size) and one FRAGMENT each. X86IO kind01 is fixed to page04; X86ALU kind02 is fixed to page05; both are capped at 4096 bytes. Generic destination-page, entry-offset, capabilities and relocation metadata remain future work.

## 5. Load path

The intended path is:

1. ATM opens `X86IO.C` and `X86ALU.C` through the shared TR-DOS fixed-overlay loader after the resident A2h acknowledgement and before BIOS selection.
2. ATM reads all sectors into the ABI frame buffer at `C01Ch`; the first sector is copied backwards from `C000h` to avoid overlap with the frame header, and later sectors are read directly into the following data blocks.
3. ATM sends IMAGE_BEGIN, one IMAGE_FRAGMENT and IMAGE_FINISH using the existing ABI 1.0 DMA sender. The fragment is bounded by 4096 bytes and carries the standard 10-byte extension.
4. NeoGS validates the frame CRC, message ID, fragment index/count, declared total length and frame payload length.
5. NeoGS copies the X86IO fragment to page04 and the X86ALU fragment to page05 through WIN3, then verifies every installed byte against the still-preserved page-42 source.
6. X86IO IMAGE_FINISH runs page mapping and nested gate self-tests before setting IO_OVERLAY_READY. X86ALU IMAGE_FINISH probes its page05 entry through the gate and verifies WIN2 returns to page04 before setting X86ALU_READY.
7. BIOS execution remains gated until X86IO, X86ALU and the selected SYSBIOS image are ready. Failed transfers do not publish the ready flag.

The IMAGE service now supports three explicit fixed profiles: SYSBIOS kind `00h` to page10 (8192 bytes), X86IO kind `01h` to page04 (1..4096 bytes), and X86ALU kind `02h` to page05 (1..4096 bytes). Both use the same page-42 staging and WIN3 copy/readback path. This is not yet a generic allocator or arbitrary-page loader.

Modules larger than one frame must be streamed as multiple fragments. A 16 KiB module cannot fit in one ABI 1.0 frame after the IPC header and fragment extension, so the loader must not assume a single-fragment 16 KiB transfer.

## 6. Call ABI and lifetime rules

The resident WIN2 call gate is now implemented as a low-level primitive. Existing X86IO and X86ALU public entry points are resident wrappers and request page04 or page05 through that gate, so the overlay can be called while another trusted overlay temporarily owns WIN2. The higher-level dynamic manager is still absent: there is no module table, allocator, manifest validation, generic loader, unload/refcounting or ownership policy.

A future module call request will identify a module ID and exported function ID (or validated entry offset). The current low-level gate only switches a caller-supplied selector/IX entry; the higher-level manager must extend it to:

1. validates that the module is loaded and the entry lies within its image;
2. saves the current WIN2 page and pushes a bounded call frame on the WIN1 stack;
3. maps the requested module page into WIN2;
4. transfers control to the fixed-origin entry;
5. receives the module's normal return at a resident return trampoline;
6. restores the previous WIN2 mapping and pops the call frame.

Rules:

- The call gate, return trampoline, module table, and stack must remain outside WIN2 and WIN3.
- An overlay may call resident APIs through fixed resident entry points.
- An overlay may request another overlay only through the resident gate. The current primitive saves/restores one selector frame per call; the manager must add a validated maximum depth and reject stack exhaustion before entering a module.
- No pointer into WIN2 may be retained by resident code or another module across a call that can remap WIN2.
- Interrupt handlers must remain resident and must not execute overlay code or access WIN2. Overlay entry points are synchronous and non-reentrant unless a module explicitly declares otherwise.
- A module cannot be unloaded while its call depth is nonzero.
- Unknown module/function IDs, invalid offsets, exhausted nesting depth, mapping failure, and unloaded-module calls return explicit errors; they must never jump through an unchecked pointer.

## 7. First vertical slice

The first candidate module is the existing XT PPI/keyboard I/O implementation in `neogs_sub/x86_io.asm`. It is a small, bounded source unit and provides a real consumer of the module ABI.

The two pinned-overlay source/build/load slices and low-level resident call gate are implemented:
- `x86_io.asm` is assembled at `8000h` and exported as `X86IO.C` (796 bytes in the current build);
- `X86CORE.C` is separately exported at 0000h (15,610 bytes in the current build);
- resident public X86IO entry points route through the WIN2 gate; implementation symbols remain fixed at the overlay origin;
- ATM loads `X86IO.C` from TR-DOS after A2h and sends the IMAGE transaction over ABI 1.0 DMA;
- NeoGS installs page 04h, verifies the complete image by readback, runs a reversible WIN2 selector test across pages 04h and 05h at offset 3FFFh, then runs a temporary page05→page04 X86IO-wrapper→page05 gate test and restores the page05 scratch bytes;
- BIOS execution waits for both IO_OVERLAY_READY and BIOS_IMAGE_READY;
- `00E0h` diagnostic latch and current PPI/keyboard semantics are retained.

Not implemented: dynamic page allocator, general manifest, generic ATM module streaming, unload/refcounting, and runtime validation of repeated/deeper gate calls. The X86ALU probe verifies one page05 gate entry/return after readback, but does not test arithmetic semantics. A boot-time source-level self-test now exercises one page05→page04→page05 call and fails closed before IO_OVERLAY_READY; no physical target log has yet confirmed that self-test, X86IO transfer or return-state preservation.

## 8. Implementation gates

The manager is not complete until all of the following are true:

- [x] WIN2 selector register/encoding identified from Project125 reference: MPAG #00, selector ROR8(physical_page); Project126 startup #80 corresponds to page 01h.
- [x] Resident runtime self-test exercises WIN2 mapping/read/write on physical pages 04h and 05h at offset 3FFFh, saves/restores both bytes, and leaves page 04h mapped.
- [ ] Confirm the runtime self-test passes on the physical Project126 target.
- [x] Resident/overlay link layout and size assertions pass for the fixed X86IO module.
- [ ] Generic module manifest parser rejects malformed and out-of-pool images.
- [x] ATM TR-DOS reader loads the complete X86IO.C file and sends a single bounded IMAGE fragment.
- [x] NeoGS IMAGE receiver validates frame CRC, image kind, ID, fragment metadata, total size and frame length for the X86IO profile.
- [x] Destination page-04 readback is byte-for-byte verified before IO_OVERLAY_READY is published.
- [x] Resident call/return gate saves the previous WIN2 selector on the WIN1 stack and restores it at a resident RET trampoline; X86IO wrappers use this gate.
- [x] IMAGE_FINISH performs a boot-time page05→page04 X86IO wrapper call and verifies that the page05 test stub resumes after the gate restores WIN2; scratch bytes are restored before BIOS is enabled.
- [ ] Physical target log confirms [NGS] WIN2 MAP/GATE TEST PASS; repeated/deeper nested calls, alternate-register use and stack-limit behavior remain to be tested.
- [ ] Invalid/unloaded dynamic module calls fail closed.
- [x] CI build/package passes with the boot-time gate self-test (run 42398846093, commit 94ac5ba2; X86CORE 15610/16384 bytes, X86IO 796/4096 bytes, X86ALU 1175/4096 bytes; NeoGS, ATM, IPC and TR-DOS assembly 0 errors/0 warnings).
- [ ] Physical ATM/NeoGS log confirms X86IO and X86ALU transfer/readback, `[NGS] WIN2 MAP/GATE TEST PASS`, `[NGS] X86ALU PAGE05 GATE OK`, and final WIN2 mapping.

No PIC/PIT/DMA/VGA/RTC/IDE implementation is to be added to the resident image before these gates are met. No CPU functional suite, full BIOS POST, or guest operating-system test is implied by overlay infrastructure validation.
