# Project126 — ATM-PC/XT hybrid machine profile

**Profile ID:** P126-ATMPC-XT-HYBRID-0.1  
**Status:** initial guest memory and I/O decode contract; device runtime is not yet implemented.

## 1. Selected compatibility model

Project126 uses a custom ATM-PC board profile with an Intel 8086 in Real Mode and a 20-bit address bus. It adopts IBM PC/XT-style system interfaces where they improve compatibility, but it is not a claim of complete IBM PC/XT hardware compatibility.

The machine has a full 1 MiB guest physical RAM backing store in NeoGS. VGA and ROM decode windows overlay that backing store. The address map is deliberately not the conventional 640 KiB RAM plus permanently lost UMA layout: 216 KiB of RAM remains available above the VGA BIOS window.

The CPU semantics remain tied to the pinned PCem 8086 reference. PCem device models are behavioral references, not code to be copied wholesale into the NeoGS firmware.

## 2. Guest physical memory map

All ranges are half-open. Physical addresses are 20-bit and wrap at 1 MiB, as required by the 8086 bus. There is no A20 gate.

| Guest address range | Size | Read path | Write path | Notes |
|---|---:|---|---|---|
| 00000–9FFFF | 640 KiB | Guest RAM | Guest RAM | Low RAM, includes IVT and BIOS Data Area. |
| A0000–BFFFF | 128 KiB | VGA aperture | VGA aperture | VGA memory window. VGA Graphics Controller selects the effective aperture; 256 KiB VRAM is separate backing storage. |
| C0000–C7FFF | 32 KiB | VGA BIOS ROM | Ignored / no-op | Separate VGA BIOS image, independent from system BIOS limit. |
| C8000–FDFFF | 216 KiB | Guest RAM | Guest RAM | Custom upper RAM extension; unlike conventional PC UMA this region is not globally reserved for option ROMs. |
| FE000–FFFFF | 8 KiB | System BIOS ROM | Ignored / no-op | Initial 8 KiB XT-compatible ROM window; contains reset vector at physical FFFF0. |

Totals: 1,024 KiB guest address space; 856 KiB guest RAM exposed at reset; 128 KiB VGA aperture; 32 KiB VGA BIOS; 8 KiB system BIOS boot window. The entire 1 MiB is backed by the separate 1 MiB NeoGS guest-RAM allocation; ROM/VGA overlays take priority over RAM on reads and suppress ordinary RAM writes while enabled.

### BIOS capacity versus visible reset window

The architecture retains a maximum system BIOS image size of 256 KiB, stored in the independent 256 KiB NeoGS system-BIOS slot. The initial XT BIOS images supplied with Project126 are 8 KiB ROMs and are mapped at FE000–FFFFF, matching the ORG 0E000h / 8 KiB layout documented in bios/bios.asm. The reset instruction fetch at FFFF0 therefore resolves to offset 1FF0 within the selected 8 KiB image.

A future BIOS image larger than 8 KiB requires an explicit ROM-window/banking policy before it can be declared bootable. The 256 KiB storage limit must not be misrepresented as a 256 KiB linear guest-visible ROM window. No banking register or runtime bank switch is assigned by this revision.

### ROM priority and write behavior

1. System BIOS overlay FE000–FFFFF has priority over RAM.
2. VGA BIOS overlay C0000–C7FFF has priority over RAM.
3. VGA aperture A0000–BFFFF routes to VGA, not guest RAM.
4. All other addresses route to guest RAM.
5. BIOS writes do not modify the hidden RAM backing while the ROM overlay is active. A future shadow-RAM feature requires an explicit control bit and cache/invalidation rules.

## 3. VGA memory and I/O

The initial VGA memory aperture is A0000–BFFFF (128 KiB maximum CPU-visible window). The adapter owns 256 KiB VRAM. The actual active aperture and bank mapping are controlled by VGA registers; the decoder must follow PCem vid_vga.c and vid_svga.c, including Graphics Controller register 6 mapping choices. The 128 KiB guest window is not a declaration that all 256 KiB VRAM is linearly visible at once.

VGA I/O decode:
- 3C0–3CF: Attribute Controller, Sequencer, DAC and Graphics Controller.
- 3B0–3BF: monochrome CRTC/status aliases.
- 3D0–3DF: color CRTC/status aliases.
- The active CRTC base follows the VGA Miscellaneous Output register, as in PCem vga_in() / vga_out().

The VGA BIOS guest ROM window is C0000–C7FFF (32 KiB), matching the PCem IBM VGA device's rom_init(..., 0xc0000, 0x8000, ...) placement.

## 4. System-board I/O decode

The profile reserves the following PC/XT-style interfaces. They are guest-visible software devices on NeoGS. Any request requiring a physical resource is forwarded to ATM only through the unified DMA/IPC ABI 1.0.

| Port range | Model / purpose | Status |
|---|---|---|
| 0000–000F | 8237-compatible DMA controller | Reserved decode; implementation pending |
| 0020–0021 | 8259-compatible master PIC | Reserved decode; implementation pending |
| 0040–0043 | 8253-compatible PIT | Reserved decode; implementation pending |
| 0060–0063 | 8255-compatible PPI / XT keyboard and system control | Reserved decode; keyboard events originate at ATM and arrive through IPC |
| 0070–0071 | DS12887-compatible RTC/CMOS extension | Custom ATM-PC extension; time source is ATM |
| 0080–0083 | DMA page registers | Reserved decode; implementation pending |
| 01F0–01F7 | Primary ATA-compatible guest disk task file | Software device; requests forwarded to ATM/NEMO IDE through IPC |
| 03B0–03DF | IBM VGA register interfaces | VGA implementation pending |
| 03F0–03F5, 03F7 | 765-compatible floppy controller (3F7 status/direction) | Reserved; whether floppy service is enabled remains a separate device decision |
| 03F6 | Primary ATA control register | Software device; requests forwarded to ATM through IPC |

Port 03F6 is assigned to the ATA control register and is intentionally excluded from the floppy-controller register set (the legacy PC/XT decode shares this neighborhood). The RTC ports are a deliberate custom extension; the physical DS12887/time source remains on ATM. This does not grant NeoGS direct access to a physical RTC.

Unknown or unimplemented guest ports return FFh on reads and ignore writes in this initial profile. They must never be forwarded as physical NeoGS port operations.

## 5. BIOS images currently packaged

The TR-DOS image builder includes three 8 KiB system BIOS choices:
- BIOS1.C — source bios/27c64d.bin.
- BIOS2.C — source bios/Bios.bin; the associated source bios/bios.asm identifies this family as a Generic Turbo XT BIOS for 8088/V20-compatible systems and documents an 8 KiB image at the top of the F000 segment.
- COMPAQ.C — source bios/Compaq Portable Plus 100666-001 Rev C.bin; machine-specific assumptions may differ from the generic XT profile.

Each packaged image is currently required by the build to be exactly 8192 bytes. This profile defines the intended guest placement, not successful POST/boot for every image. Compaq-specific hardware services and all BIOS boot paths still require runtime compatibility testing.

VGA BIOS is a separate image and is not one of these three system BIOS choices. Its file source and guest image contents are not yet staged in the TR-DOS catalog.

## 6. PCem comparison points

- CPU reset and 20-bit address behavior: PCem/808x.c, PCem/cpu.h.
- Memory mapping and read/write dispatch: PCem/mem.c, PCem/mem.h.
- IBM VGA ROM and aperture setup: PCem/vid_vga.c (vga_init(), rom_init).
- VGA aperture mapping: PCem/vid_svga.c (Graphics Controller register 6 handling).
- VGA register dispatch: PCem/vid_vga.c (vga_in(), vga_out()).

## 7. Explicitly not implemented by this profile document

- Runtime RAM/ROM/VGA read and write handlers.
- VGA register/plane/latch implementation and renderer.
- PIC/PIT/PPI/keyboard/RTC/IDE/FDC/DMA device emulation.
- Guest BIOS banking for images larger than 8 KiB.
- ATM-side physical I/O request service handlers.
- BIOS POST/boot validation on NeoGS.

A source-level address map and compile-time assertions are not BUILD/EMULATOR/HARDWARE PASS for those runtime components.

### PPI / XT keyboard implementation status

The initial runtime slice is being added in neogs_sub/x86_io.asm for ports 0060h–0063h:
- 60h: PPI port A / keyboard scan-code data latch and FIFO consumer.
- 61h: PPI port B / system-control latch, including XT keyboard reset and acknowledge bits.
- 62h: PPI port C input/output composition; board configuration input is a deterministic profile value pending explicit ATM-PC switch definition.
- 63h: PPI mode-set and bit-set/reset control register.
- Initial BIOS mode-0 control word is 99h. PPI mode 1/2 handshake modes and board-specific port-C switch wiring are outside this first slice.
- Keyboard scan-code production is exposed as a software API for the future DMA/IPC input service. It does not access NeoGS physical ports and does not claim a working ATM keyboard path or PIC IRQ1 delivery.
