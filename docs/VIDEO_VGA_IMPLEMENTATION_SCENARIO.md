# Project126 — VGA and ATM frame pipeline implementation scenario

Revision 0.1. Status: implementation plan and staged work baseline.
Behavioral reference: Project126/PCem only. Project125 is explicitly excluded as a source of VGA code or behavior.

## 1. Fixed architecture

- One IBM-compatible VGA adapter, including its CGA/EGA compatibility modes. No separate CGA/MDA device.
- Exactly 256 KiB VGA VRAM: NeoGS physical pages 30h–3Fh (0C0000h–0FFFFFh).
- Guest VGA aperture: A0000h–BFFFFh. The current Project126 dispatcher is linear staging only, not VGA-compatible; it must become register-controlled.
- VGA BIOS storage remains separate at pages 20h–2Fh; guest option-ROM window C0000h–C7FFFh.
- ATM presentation storage: pages 40h–41h, 32 KiB total. Use as two 16 KiB frame slots for producer/consumer handoff.
- Production DMA staging: page 42h, 16 KiB. IPC/session scratch: page 43h. Do not repurpose either allocation.
- ATM is the owner of physical hardware. All guest x86 ports are software models; all NeoGS↔ATM exchange uses DMA/IPC.

## 2. Source-of-truth PCem paths

- PCem/vid_vga.c and vid_vga.h: VGA adapter setup, port decode, CRTC mono/colour aliasing and 256 KiB allocation.
- PCem/vid_svga.c and vid_svga.h: Attribute Controller, Sequencer, Graphics Controller, CRTC, DAC, latches, plane masks, aperture mapping and banking.
- PCem/vid_svga_render.c and vid_svga_render.h: text/graphics scanout, planar/packed decoding, palette and pixel generation.

Do not port host-only SDL, Allegro, OS timers, native windowing, host memory mapping or file APIs. Preserve guest-visible behavior using deterministic Project126 state.

## 3. Responsibility split

### VGA core on NeoGS

Owns guest VGA registers, port decode, 256 KiB VRAM, aperture semantics, latches/planes, mode state and scanout. The initial VGA aperture in x86_cpu_state.asm is explicitly staging-only and must not be treated as a completed VGA implementation.

### ATM frame converter on NeoGS

- Reads VGA state and VRAM through the VGA module API, never as an assumed linear bitmap.
- Decodes VGA mode, geometry, pitch, start address, panning, palette and text/planar/packed layout.
- Consumes a versioned ATM mode descriptor delivered by the host. It must not infer ATM mode from VGA registers.
- Converts to the exact active ATM memory layout and emits exactly 16384 bytes.
- Writes only to the inactive page-40/page-41 slot. Publish it only after conversion completes; never modify the slot currently being transferred/displayed.
- Defines deterministic scaling/colour policy for any VGA mode not natively representable by the selected ATM mode.

### ATM host and frame service

ATM reports its current mode and accepts the finished frame. NeoGS video service owns scheduling, slot ownership, fragmentation and DMA/IPC. ATM host performs final placement/page flip only after complete frame validation.

## 4. Transport contract

The DMA aperture is 16 KiB including the 18-byte ABI header; a regular ABI frame carries at most 16366 payload bytes. A 16 KiB image therefore cannot fit into one framed transfer.

Use the existing ordered ABI 1.1 fragmentation extension: 10-byte fragment extension, at most 16356 bytes of frame data per fragment, individual CRC-16/CCITT-FALSE validation, common frame/message ID, ordered reassembly. Keep page 42h as the single DMA staging page and page 43h as scratch. On any timeout, missing fragment, sequence error or CRC failure, retain the previously displayed frame.

## 5. Implementation stages

### Stage 0 — baseline audit
Record PCem references and the existing physical allocations. Preserve the BIOS2 INT CD stop point and do not modify CPU/IVT code as part of video work.

### Stage 1 — VGA register and port core
Implement PCem-compatible port decode, mono/colour CRTC alias selection, Attribute Controller flip-flop, Sequencer, Graphics Controller, CRTC protection, DAC index/data and status-read side effects. Add deterministic register tests.

### Stage 2 — VGA memory semantics
Replace linear A0000h–BFFFFh staging with map select, chain-4/chain-2, plane selection, latches, read modes 0/1, write modes 0–3, rotate, set/reset, logical operation, bit mask and map mask. Verify all four planes independently.

### Stage 3 — VGA scanout
Port relevant PCem text, planar 4-bpp and packed 8-bpp rendering. Derive geometry, pitch, start address, cursor, blink, panning, palette and display enable from VGA registers. Add deterministic patterns.

### Stage 4 — ATM mode descriptor and converter
Derive the descriptor from actual ATM mode-control state and Project126 ATM source/docs. Implement each supported ATM layout separately. Verify exact 16384-byte output and reference vectors; do not invent modes.

### Stage 5 — frame slots and DMA/IPC
Use pages 40h–41h as alternating 16 KiB frame slots, page 42h as DMA staging, page 43h as scratch. Transfer the logical frame as independently CRC-checked ABI 1.1 fragments. Add timeout/recovery and ownership rules.

### Stage 6 — BIOS and end-to-end tests
Run BIOS2 INT 10h text/graphics paths. Validate guest register access, aperture, scanout, ATM conversion, reassembly and final ATM placement. Keep the current BIOS2 INT CD stop point unchanged.

## 6. Acceptance criteria

- Exactly 262144 bytes of VRAM; all four planes pass read/write/latch tests.
- Implemented VGA register behavior matches the corresponding PCem paths.
- BIOS2 INT 10h text and supported graphics tests produce expected VGA scanout.
- Every supported ATM mode produces exactly 16384 deterministic output bytes.
- DMA fragmentation never exceeds the 16 KiB aperture and never mutates an in-flight slot.
- ATM displays only a fully validated frame; on failure it retains the previous frame.
- Build logs report component versions, image sizes and test results. Assembly success is not hardware/display verification.
