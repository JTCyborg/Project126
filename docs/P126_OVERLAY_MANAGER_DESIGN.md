# Project126 — Overlay / Module Manager design

**Revision:** 0.1  
**Date:** 2026-11-07  
**Status:** source-audited design baseline; runtime implementation not yet started

## 1. Purpose

The current `X86CORE.C` is a single resident image with a hard 16 KiB loader limit. The latest successful build ends at `3FFBh` (16,379 bytes), leaving five bytes. The NeoGS physical map nevertheless reserves pages `00h–0Fh` (256 KiB) for the kernel/runtime.

The manager must use that existing allocation without changing the physical map, enlarging the `X86CORE.C` limit, taking ownership of WIN3, or moving the operational stack.

This document records the source-backed design direction and the remaining validation gates. It is not a claim that an overlay loader or runtime manager is already implemented.

## 2. Verified current layout

- Stage-0 is assembled at `4000h`, loaded by the GS105a ROM path, and receives one resident image through the bootstrap DBIT byte channel.
- Stage-0 currently accepts a nonzero image length up to `4000h`, copies it to logical `0000h`, then jumps to `0000h`.
- The resident image is assembled at `ORG 0`; `x86_cpu_state_assemble.asm` includes the resident dispatcher, CPU state, execution, ModR/M, ALU, I/O and IPC code into one flat image.
- Resident startup maps WIN0 to physical page `00h`, WIN1 to page `03h`, WIN2 to page `01h`, and initializes WIN3 to page `02h`. The operational stack is `7FFEh) in WIN1/page 03.
- WIN3 (`C000h–FFFFh)) is exclusively owned by the guest physical-memory backend. Its mapping is volatile and must not be used by the overlay manager.
- Kernel pages `00h–0Fh` are allocated. Page 03 contains the operational stack and narrow diagnostic buffers. Page 00 contains the current resident image. The initial WIN2/WIN3 mappings are page 01/page 02.
- A source scan of the current CPU/IPC translation units found no direct memory operands in the logical `8000h–BFFFh` range. This supports WIN2 as a candidate overlay aperture, but is not yet a complete proof that every runtime path leaves WIN2 unused.

## 3. Candidate execution aperture

Use WIN2 (`8000h–BFFFh`, 16 KiB) as the one-module execution/data aperture.

Rationale:

1. Resident code and fixed dispatcher remain in WIN0/page 00.
2. The operational stack remains in WIN1/page 03.
3. Guest memory access continues to own WIN3 exclusively.
4. An overlay can execute at a fixed logical origin (`8000h`) while its physical backing page is selected from the kernel pool.
5. A resident call gate can switch the WIN2 page, call a module entry, and restore the previous mapping on return. Nested calls can be represented as a stack of previous page selections, provided the call gate and its stack frames remain in WIN0/WIN1.

Candidate physical overlay pool: pages `04h–0Fh` (12 pages, 192 KiB). Pages 00–03 are excluded from allocation: resident image, initial fixed window/temporary page reservations, and page-03 stack/diagnostic ownership. This candidate pool still requires an explicit allocator table and build/runtime assertions before use.

### Mapping register gate

The current source proves only the startup write `OUT (#00),#80` is used to establish WIN2→page 01. It does not yet provide a complete documented page-selector encoding for arbitrary WIN2 physical pages. Do not infer a formula from that one value.

Before implementing page switching, verify the exact WIN2 register and encoding against the NeoGS hardware documentation or a known-good Project125 paging routine, then add a save/map/restore hardware test. WIN3's MPAGEX `#10` and RRCA encoding must not be reused for WIN2 without evidence.

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

The exact byte layout is intentionally not frozen until the first module is built and the ATM/NeoGS transfer path is implemented. All lengths and offsets are little-endian. Reject unknown format/ABI versions, zero length, page outside the pool, entry outside image, arithmetic overflow, and images larger than one page.

## 5. Load path

The intended path is:

1. ATM host opens a named TR-DOS `.C` module using the already established TR-DOS file-open/descriptor/sector-read discipline.
2. ATM streams module data in ABI 1.0 IMAGE frames. Do not introduce a second transport or direct NeoGS physical-port access from ATM.
3. NeoGS validates every complete frame (header, sequence, length and per-frame CRC) before accepting it.
4. NeoGS copies fragment data from the production DMA staging page 42h into the requested physical kernel page using WIN3, without changing WIN2 or the stack.
5. NeoGS verifies the installed bytes against the accepted source data and verifies the complete module checksum before publishing the module as loaded.
6. Only after successful verification does the manager publish the module ID/page/entry in its resident module table.
7. Failed or incomplete transfers leave the module unpublished; retry must not call partially installed code.

The current BIOS IMAGE service is a useful reference for frame validation, page-42 staging, WIN3 copy and destination readback, but it is hard-coded to the SYSBIOS page-10 destination and an 8 KiB single-fragment image. It must be generalized carefully; do not repurpose its current SYSBIOS contract or change BIOS page placement.

Modules larger than one frame must be streamed as multiple fragments. A 16 KiB module cannot fit in one ABI 1.0 frame after the IPC header and fragment extension, so the loader must not assume a single-fragment 16 KiB transfer.

## 6. Call ABI and lifetime rules

The resident dispatcher owns a fixed module table and the WIN2 mapping state.

A module call request identifies a module ID and exported function ID (or validated entry offset). The resident gate:

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

The first slice must:
- assemble the I/O unit at `8000h` as a separate overlay output;
- keep only resident call gates/stubs in the core image;
- route reset/read/write/keyboard API calls through the resident gate;
- load the overlay before BIOS execution can invoke CPU reset/I/O paths;
- verify module bytes after installation;
- test WIN2 page save/restore, repeated calls, nested calls, invalid entry rejection, and unloaded-module rejection;
- preserve the `00E0h` diagnostic latch behavior and the current PPI/keyboard limitations until the device tests are expanded.

The existing I/O module is currently embedded in the resident image. It must not be removed from the resident image until the overlay file is packaged, loaded, verified and available before the first call.

## 8. Implementation gates

The manager is not complete until all of the following are true:

- [ ] WIN2 selector encoding is documented and hardware-validated for at least two approved physical pages.
- [ ] Resident/overlay link layout and size assertions pass.
- [ ] Module manifest parser rejects malformed and out-of-pool images.
- [ ] ATM TR-DOS module reader streams the entire module with bounded sector and frame handling.
- [ ] NeoGS IMAGE module receiver validates sequence, per-frame CRC, total size and whole-image checksum.
- [ ] Destination readback is byte-for-byte verified before module publication.
- [ ] Call/return trampoline preserves the WIN2 mapping and WIN1 stack.
- [ ] Nested and repeated calls restore mappings correctly.
- [ ] Invalid/unloaded calls fail closed.
- [ ] CI build/package passes.
- [ ] Physical ATM/NeoGS log confirms module load, checksum/readback, call, return and mapping restore.

No PIC/PIT/DMA/VGA/RTC/IDE implementation is to be added to the resident image before these gates are met. No CPU functional suite, full BIOS POST, or guest operating-system test is implied by overlay infrastructure validation.
