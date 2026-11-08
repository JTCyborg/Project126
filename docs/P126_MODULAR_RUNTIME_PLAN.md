# Project126 — Modular NeoGS runtime implementation plan

**Revision:** 0.2  
**Date:** 2026-11-08  
**Status:** Phase 1 implemented in source; build/runtime validation pending.

## Objective

Remove the artificial 16 KiB limit on the *total NeoGS program*. The 16 KiB physical page remains the maximum size of one independently mapped WIN2 overlay image. The resident bootstrap image and each individual overlay must still fit their actual execution windows.

Project126 has 4 MiB of NeoGS physical RAM (256 pages × 16 KiB). WIN0 is the resident execution window, WIN1 owns the resident stack/fixed runtime data, WIN2 is the overlay aperture selected through MPAG port 00h, and WIN3 remains exclusively reserved for guest physical-memory access through MPAGEX port 10h.

## Non-negotiable constraints

- Do not map or execute resident code/stack from WIN3.
- Do not change the MPAG/MPAGEX ports or selector encoding.
- Do not use Spectrum 128 7FFD semantics; Project126 uses its existing NeoGS page mapper.
- Do not make an overlay call through a stale WIN2 pointer.
- Keep the call gate, registry metadata and operational stack resident or in another permanently mapped region.
- Keep ABI 1.0 DMA frame limits; larger module images must be streamed in multiple validated fragments.
- Preserve the existing X86IO/X86ALU/X86DEV entry wrappers and BIOS2 execution path.
- Keep the resident bootstrap image within its real WIN0/loader capacity. This is a per-resident-image limit, not a limit on total program size.

## Target architecture

### Memory ownership

| Region | Responsibility |
|---|---|
| WIN0 / physical page 00 | Minimal resident kernel, dispatch, module registry API and permanent services |
| WIN1 / physical page 03 | Operational stack and fixed runtime state |
| WIN2 / physical pages 04–0F initially | One active overlay at logical 8000h–BFFFh |
| WIN3 / MPAGEX | Guest-memory and DMA staging aperture only |

The physical overlay allocator must be extended beyond the current dynamic pages only after the runtime validates which physical pages are available and reserved. The remaining physical RAM must not be treated as overlay code storage until a dedicated ownership/allocation policy is implemented.

### Module directory format v1

The build now generates a 7-byte header and 8-byte records:

- Header: ASCII magic P126, format revision, record count, record size.
- Record: module ID, physical destination page, flags, reserved byte, image length (little-endian), CRC-16/CCITT-FALSE (little-endian).
- IDs 01/02/03 identify X86IO/X86ALU/X86DEV, pinned to pages 04/05/06.
- Flag bit 0 means pinned; reserved byte must be zero.

The directory is generated from the exact assembled module binaries and packaged as X86MODS.M. Phase 1 metadata is not yet consumed by the runtime; the current fixed-profile ATM loader remains authoritative until the parser and generic fragment loader are implemented.

## Implementation phases

### Phase 1 — build-time module catalog (implemented in source)
- Generate a deterministic directory from X86IO.C, X86ALU.C and X86DEV.C.
- Compute CRC-16/CCITT-FALSE over each exact image.
- Package the directory as X86MODS.M on the TR-DOS disk.
- Verify its exact size and directory entry during disk packaging.
- Retain genuine per-image execution-window checks.

### Phase 2 — resident module registry and generic call API
- Parse and validate magic, revision, record count/size, unique IDs, page pool, nonzero image length, image length <= 16 KiB, reserved bits and CRC.
- Add bounded states: absent, loading, loaded, active.
- Add a module-ID + entry-offset call API. Validate loaded state and entry bounds before entering 8000h + offset through the existing WIN2 gate.
- Keep compatibility wrappers until all callers migrate.

### Phase 3 — generic multi-fragment loader
- Add a generic ATM file streamer driven by directory records.
- Stream images in multiple ABI 1.0 fragments; never assume a full 16 KiB image fits in one frame.
- Publish loaded state only after complete length and CRC validation.
- Install only into allocator-owned pages; never overwrite pinned or active modules.

### Phase 4 — lifecycle and expanded capacity
- Add reference counts/call-depth ownership, unload rules and explicit failure codes.
- Add page discovery/validation and a configurable pool outside pinned pages.
- Keep active code pages pinned until call depth returns to zero.
- Support a total linked module set larger than 16 KiB, with each individual overlay <= 16 KiB.

### Phase 5 — regression and BIOS validation
- Test malformed manifests, duplicate IDs, invalid pages, CRC mismatch, out-of-range entries, allocator exhaustion and nested calls.
- Confirm WIN2 selector restoration and WIN3 isolation.
- Run BIOS2 unchanged after each runtime stage.
- Compare CPU/device semantics with PCem; no unrelated x86 changes are part of this work.

## Acceptance criteria

- The sum of all module image sizes may exceed 16 KiB without build/package failure.
- No individual module exceeds one 16 KiB execution page.
- Resident image remains within its independently required WIN0/bootstrap capacity.
- Manifest entries match packaged binaries by exact length and CRC.
- ATM can load modules using directory metadata, and NeoGS rejects malformed or out-of-pool images.
- Existing BIOS2 boot behavior remains unchanged.
