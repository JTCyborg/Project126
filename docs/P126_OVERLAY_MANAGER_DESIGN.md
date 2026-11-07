# Project126 — Overlay / Module Manager design

**Revision:** 0.1  
**Date:** 2026-11-07  
**Status:** first pinned X86IO overlay is implemented and CI-built; dynamic multi-module manager and target validation remain pending

## 1. Purpose

The resident `X86CORE.C` has a hard 16 KiB loader limit. The first overlay split now produces a 15,994-byte resident image and a separate 796-byte `X86IO.C` module at logical origin `8000h`. The NeoGS physical map reserves pages `00h–0Fh` (256 KiB) for the kernel/runtime.

The manager must use that existing allocation without changing the physical map, enlarging the `X86CORE.C` limit, taking ownership of WIN3, or moving the operational stack.

This document records the source-backed design direction and the remaining validation gates. It is not a claim that an overlay loader or runtime manager is already implemented.

## 2. Verified current layout

- Stage-0 is assembled at `4000h`, loaded by the GS105a ROM path, and receives one resident image through the bootstrap DBIT byte channel.
- Stage-0 currently accepts a nonzero image length up to `4000h`, copies it to logical `0000h`, then jumps to `0000h`.
- The resident image is assembled at `ORG 0`; it contains the resident dispatcher, CPU state, execution, ModR/M, ALU and IPC code. `neogs_sub/x86_io.asm` is assembled in the same translation unit at `ORG 8000h`, so calls from resident CPU code resolve to fixed absolute overlay addresses without runtime relocation.
- Resident startup maps WIN0 to physical page `00h`, WIN1 to page `03h`, WIN2 initially to page `01h`, and initializes WIN3 to page `02h`. The operational stack is `7FFEh` in WIN1/page 03. After X86IO IMAGE_FINISH, WIN2 is mapped to physical page `04h`.
- WIN3 (`C000h–FFFFh`) is exclusively owned by the guest physical-memory backend. Its mapping is volatile and is never used as an overlay execution window.
- Kernel pages `00h–0Fh` are allocated. Page 03 contains the operational stack and narrow diagnostic buffers. Page 00 contains the resident image; page 03 contains the operational stack and fixed data; page 04 currently holds the pinned X86IO overlay. The initial WIN2/WIN3 mappings are page 01/page 02.
- A source scan of the CPU/IPC translation units found no fixed data operands in logical `8000h–BFFFh`; the range is now used as the fixed-origin X86IO execution/data aperture. The assembled overlay occupies `8000h–831Bh` (796 bytes).

## 3. Candidate execution aperture

Use WIN2 (`8000h–BFFFh`, 16 KiB) as the fixed-origin overlay execution/data aperture. The first implementation pins X86IO there; it does not yet switch among multiple overlays.

Rationale:

1. Resident code and fixed dispatcher remain in WIN0/page 00.
2. The operational stack remains in WIN1/page 03.
3. Guest memory access continues to own WIN3 exclusively.
4. An overlay can execute at a fixed logical origin (`8000h`) while its physical backing page is selected from the kernel pool.
5. All current X86IO call sites are linked directly to fixed addresses in `8000h–831Bh`. The loader maps page 04h into WIN2 once and keeps it pinned. A general resident call gate that switches among multiple overlay pages and restores nested mappings is future work.

Candidate physical overlay pool: pages `04h–0Fh` (12 pages, 192 KiB). Page 04h is currently pinned to X86IO; pages 05h–0Fh remain unallocated for future overlays. Pages 00–03 are excluded from allocation. No dynamic allocator exists yet.

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

The proposed standalone manifest is not implemented. The current first-slice profile uses the ABI 1.0 IMAGE metadata (kind, message ID, size) and a single FRAGMENT. X86IO is fixed to page 04h and capped at 4096 bytes. Generic destination-page, entry-offset, capabilities and relocation metadata remain future work.

## 5. Load path

The intended path is:

1. ATM opens `X86IO.C` through the existing TR-DOS file-open/descriptor/sector-read path after the resident A2h acknowledgement and before BIOS selection.
2. ATM reads all sectors into the ABI frame buffer at `C01Ch`; the first sector is copied backwards from `C000h` to avoid overlap with the frame header, and later sectors are read directly into the following data blocks.
3. ATM sends IMAGE_BEGIN, one IMAGE_FRAGMENT and IMAGE_FINISH using the existing ABI 1.0 DMA sender. The fragment is bounded by 4096 bytes and carries the standard 10-byte extension.
4. NeoGS validates the frame CRC, message ID, fragment index/count, declared total length and frame payload length.
5. NeoGS copies the fragment from DMA page 42h to physical page 04h through WIN3, then verifies every installed byte by reading it back against the still-preserved page-42 source.
6. After IMAGE_FINISH, NeoGS maps physical page 04h into WIN2 using MPAG port `#00`, selector `#02`, and sets `IO_OVERLAY_READY`.
7. BIOS execution remains gated until both the X86IO overlay and selected SYSBIOS image are ready. Failed transfers do not publish the ready flag.

The IMAGE service now supports two explicit fixed profiles: SYSBIOS kind `00h` to page 10h (8192 bytes), and X86IO kind `01h` to page 04h (1..4096 bytes). Both use the same page-42 staging and WIN3 copy/readback path. This is not yet a generic allocator or arbitrary-page loader.

Modules larger than one frame must be streamed as multiple fragments. A 16 KiB module cannot fit in one ABI 1.0 frame after the IPC header and fragment extension, so the loader must not assume a single-fragment 16 KiB transfer.

## 6. Call ABI and lifetime rules

The future dynamic manager will own a module table and WIN2 mapping state. The current pinned-X86IO slice does not have a module call gate: resident call sites are statically linked to the fixed `8000h` addresses, and page 04h remains mapped in WIN2 after load.

A future module call request will identify a module ID and exported function ID (or validated entry offset). The resident gate:

1. validates that the module is loaded and the entry lies within its image;
2. saves the current WIN2 page and pushes a bounded call frame on the WIN1 stack;
3. maps the requested module page into WIN2;
4. transfers control to the fixed-origin entry;
5. receives the module's normal return at a resident return trampoline;
6. restores the previous WIN2 mapping and pops the call frame.

Rules:

- The call gate, return trampoline, module table, and stack must remain outside WIN2 and WIN3.
- An overlay may call resident APIs through fixed resident entry points.
- An overlay may request another overlay only through the resident gate. The gate must support bounded nesting and restore the suspended module's mapping before returning to it.
- No pointer into WIN2 may be retained by resident code or another module across a call that can remap WIN2.
- Interrupt handlers must remain resident and must not execute overlay code or access WIN2. Overlay entry points are synchronous and non-reentrant unless a module explicitly declares otherwise.
- A module cannot be unloaded while its call depth is nonzero.
- Unknown module/function IDs, invalid offsets, exhausted nesting depth, mapping failure, and unloaded-module calls return explicit errors; they must never jump through an unchecked pointer.

## 7. First vertical slice

The first candidate module is the existing XT PPI/keyboard I/O implementation in `neogs_sub/x86_io.asm`. It is a small, bounded source unit and provides a real consumer of the module ABI.

The first pinned-overlay source/build/load slice is implemented:
- `x86_io.asm` is assembled at `8000h` and exported as `X86IO.C` (796 bytes in the current build);
- `X86CORE.C` is separately exported at 0000h (15,756 bytes in the current build);
- resident CPU call sites resolve directly to the overlay symbols in the same assembler pass;
- ATM loads `X86IO.C` from TR-DOS after A2h and sends the IMAGE transaction over ABI 1.0 DMA;
- NeoGS installs page 04h, verifies the complete image by readback, runs a reversible WIN2 selector test across pages 04h and 05h at offset 3FFFh, then leaves page 04h mapped;
- BIOS execution waits for both IO_OVERLAY_READY and BIOS_IMAGE_READY;
- `00E0h` diagnostic latch and current PPI/keyboard semantics are retained.

Not implemented: dynamic page allocator, general manifest, call/return trampoline, nested overlays, unload/refcounting, and WIN2 save/restore tests. No physical target test has yet verified the transfer or mapping.

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
- [ ] General call/return trampoline preserves arbitrary WIN2 mappings and WIN1 stack.
- [ ] Nested and repeated dynamic overlay calls restore mappings correctly.
- [ ] Invalid/unloaded dynamic module calls fail closed.
- [x] CI build/package passes (run 42396918560, commit 477bd340; X86CORE 15994 bytes, X86IO 796 bytes; NeoGS assembly and TR-DOS packaging 0 errors/0 warnings).
- [ ] Physical ATM/NeoGS log confirms X86IO module load, page-04 readback, `[NGS] WIN2 PAGE04/05 TEST PASS`, and final WIN2 mapping.

No PIC/PIT/DMA/VGA/RTC/IDE implementation is to be added to the resident image before these gates are met. No CPU functional suite, full BIOS POST, or guest operating-system test is implied by overlay infrastructure validation.
