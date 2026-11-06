# Project126 — NeoGS physical RAM map

**Revision:** 0.2 (guest RAM bank-window access contract)  
**Status:** build-time allocation contract; physical paging/DMA access still requires hardware validation.

## Scope

This document assigns byte ranges in the NeoGS 4 MiB physical RAM. It defines the logical window contract needed by the first guest-RAM memory backend. DMA register encoding and ATM host buffer addresses remain separate contracts.

The allocation unit is a 16 KiB physical page. There are 256 pages (00–FF), total 0x400000 bytes. All ranges are half-open: start included, limit excluded.

## Physical allocation

| Pages | Physical range | Size | Owner / purpose |
|---|---:|---:|---|
| 00–0F | 000000–03FFFF | 256 KiB | Resident NeoGS kernel and runtime. Hard maximum remains 256 KiB. |
| 10–1F | 040000–07FFFF | 256 KiB | System x86 BIOS image slot. Enforces the 256 KiB system BIOS limit. |
| 20–2F | 080000–0BFFFF | 256 KiB | VGA BIOS image slot. Separate from system BIOS; reserved capacity, not a required image size. |
| 30–3F | 0C0000–0FFFFF | 256 KiB | VGA VRAM backing store. |
| 40–41 | 100000–107FFF | 32 KiB | One complete ATM presentation-frame buffer. Actual pixel ABI and hardware mode remain open. |
| 42 | 108000–10BFFF | 16 KiB | One DMA aperture backing page for ABI 1.0 frames. One active DMA transaction. |
| 43 | 10C000–10FFFF | 16 KiB | IPC/session scratch and transient frame-codec workspace. Not a second DMA buffer. |
| 44–83 | 110000–20FFFF | 1 MiB | Guest x86 RAM backing store. This is a physical NeoGS allocation, not the guest logical address map. |
| 84–FF | 210000–3FFFFF | 1.9375 MiB | Unassigned expansion reserve. No subsystem may consume it without updating this map and its assertions. |

## NeoGS logical window contract

The resident memory backend reserves logical window WIN3 (C000h–FFFFh) as a banked physical-RAM aperture. The page is selected by writing the physical 16 KiB page number to NeoGS port 23h (WIN3). Guest RAM physical pages 44h–83h are therefore reachable as a sequence of bank selections. The CPU code, resident data and stack used while this backend is active must remain in WIN0–WIN2. WIN3 is volatile and is not restored after a memory access; it is exclusively owned by the memory backend. Interrupt handlers that can run during a banked access must also reside outside WIN3 and must not use WIN3 as their own data window.

This is a logical execution contract, not a claim that the whole resident kernel fits in three windows. Kernel paging/banking beyond the fixed resident entry and memory-access critical section remains a separate linker/runtime design task. The implementation must not switch WIN0–WIN2 while executing code from those windows.

## Ownership and rules

1. The kernel region is the resident code/data/stack budget. Its 256 KiB ceiling is hard; the system BIOS slot is independent.
2. System BIOS and VGA BIOS have distinct backing slots. Guest-visible ROM mapping/overlay addresses are not assigned here.
3. VGA VRAM is exactly 256 KiB. The 32 KiB ATM presentation frame is separate scanout/export storage, not VGA VRAM.
4. ABI 1.0 uses a maximum 16 KiB DMA frame. Page 42 is the NeoGS-side DMA backing page. Larger payloads use ABI fragmentation.
5. The IPC scratch page is reserved RAM and must not be exposed as a second concurrent DMA transaction.
6. Guest RAM backing is a full 1 MiB allocation. The guest 8086 decoder may map RAM, ROM overlays, VGA apertures and devices differently; this does not imply the conventional IBM PC 640 KiB + UMA layout.
7. The banked guest-RAM helper accesses the guest backing linearly at physical offset 110000h + guest physical address. VGA/ROM overlays are dispatched before this helper; it deliberately rejects those regions. ATM-side DMA source/destination placement remains open. ATM paging and the actual DMA aperture must be verified before assigning an address.
8. Physical page numbers are allocation identifiers only. Actual NeoGS logical windows and DMA register programming must follow hardware documentation; do not infer a direct Z80 address from a physical page number.

## Build enforcement

The machine-readable source is shared/p126_neogs_memory_map.inc. It is included by neogs_sub/x86_cpu_state_assemble.asm. Every standard NeoGS assembly build evaluates adjacency, capacity and non-overlap assertions and exports allocation symbols in build/NEOGS.map.

The build can prove internal consistency and fit within 4 MiB. It cannot prove physical paging or DMA access; those require separate emulator/hardware tests.

## Deliberately unresolved

- Guest x86 logical 1 MiB address map: RAM/ROM overlays, VGA apertures, option ROM and device windows.
- WIN3 is assigned as the banked memory aperture (page selected through port 23h); final resident kernel placement and WIN0–WIN2 paging policy remain to be linked and hardware-validated.
- DMA register address encoding and exact DMA transaction setup.
- ATM host staging-buffer addresses and host paging state.
- Guest-visible system-board profile, I/O ports, PIC/PIT/keyboard/RTC.
- VGA BIOS actual maximum image size and guest ROM mapping.
- Video frame pixel format, stride, palette and actual ATM output mode.
