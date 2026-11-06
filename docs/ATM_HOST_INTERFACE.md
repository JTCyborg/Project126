# Project126 — ATM host module and program interface

## 1. Responsibility boundary

The ATM Turbo 2+ host Z80 (7 MHz) owns physical hardware and host-side services: physical keyboard input, TR-DOS and storage access, RTC/time source, and final display output. The NeoGS Z80 (240 MHz) owns the x86 machine, virtual devices, VGA emulation and frame rendering.

The ATM module is a transport/host-services layer. It must not contain x86 CPU execution or VGA rendering. NeoGS has no direct physical-device access; requests for host resources cross this interface.

ATM and NeoGS retain independent debug channels at port #EF.

## 2. Source modules

- `atm_host/neogs_ipc.inc` — public port definitions and calling convention.
- `atm_host/neogs_ipc.asm` — ATM-side IPC transport driver.
- `atm_host/neogs_ipc_assemble.asm` — relocatable assembly unit and placement labels.
- `build/ATM_IPC.bin` — assembled ATM transport module.
- `build/ATM.lst`, `build/ATM.map` — listing and symbol/address map.

The current assembly origin is `ORG 0000h`, used only to produce auditable image-relative offsets. It does not assign a final physical ATM load address. That address depends on the ATM memory map and integration with the TR-DOS/host program, which are not yet fixed.

## 3. Physical IPC transport

The driver uses the documented Spectrum/ATM-facing NeoGS ports:

| Port | Direction from ATM | Meaning |
|---|---|---|
| #BB | OUT | GSCOM command; sets CBIT |
| #BB | IN | GSSTAT; CBIT is bit 0, DBIT is bit 7 |
| #B3 | OUT | GSDAT host-to-NeoGS byte |
| #B3 | IN | GSDAT NeoGS-to-host byte |
| #33 | OUT | GSCTR control; not used by this driver |

The handshake follows the established Project125 host transport v2 implementation:

- A command is written to #BB; the caller waits until CBIT clears.
- A host data byte is written to #B3 only when DBIT is clear; the sender waits until DBIT clears again before considering the byte consumed.
- A byte from NeoGS is read only after DBIT becomes set. Reading #B3 acknowledges/consumes the published byte.
- CBIT and DBIT are independent signals and must never be substituted for one another.
- Every wait is bounded by a 16-bit polling timeout. A timeout is reported with Carry set; the last GSSTAT sample remains available in `p126_ipc_last_status`.

The driver does not issue a hardware reset automatically. Reset ownership and recovery policy belong to the system startup state machine.

## 4. Public Z80 calling convention

All entry points are callable with `CALL`. The module is assembled as a relocatable byte image; after integration, callers use the linked labels.

| Entry point | Input | Output |
|---|---|---|
| `p126_ipc_read_status` | — | A=status; updates last status |
| `p126_ipc_wait_cbit_clear` | — | Carry clear when CBIT=0; set on timeout; A=last status |
| `p126_ipc_wait_dbit_clear` | — | Carry clear when DBIT=0; set on timeout; A=last status |
| `p126_ipc_wait_dbit_set` | — | Carry clear when DBIT=1; set on timeout; A=last status |
| `p126_ipc_send_command` | A=command | Waits for CBIT clear |
| `p126_ipc_send_argument` | A=argument | Preloads GSDAT before command dispatch; intended for legacy GS105a #13/#14 ABI |
| `p126_ipc_send_byte` | A=data | Sends one byte and waits for DBIT clear |
| `p126_ipc_receive_byte` | — | A=data after DBIT set and GSDAT read |
| `p126_ipc_emit_version` | — | Writes `[P126 ATM_IPC v0.1.0]` to ATM #EF; preserves AF/BC/HL |

Wait routines clobber BC. The byte routines use private module storage and are not re-entrant; only one ATM caller may use the transport at a time. The caller must serialize transactions.

## 5. Deliberately not implemented yet

This is the first ATM-side transport module, not the completed system protocol. The following remain open and must be agreed/implemented before host services are exposed to the x86 machine:

- Application command IDs and request/response message schema.
- Protocol version negotiation, request sequence IDs, payload lengths and CRC.
- Retry, duplicate suppression, timeout recovery and independent-reset resynchronization.
- ATM DMA aperture/memory mapping and the exact ATM-side transfer procedure for large blocks.
- DMA buffer ownership and allowed address ranges.
- Keyboard event encoding, RTC snapshot ABI, storage request ABI and video-frame transfer ABI.
- Final ATM module load address and integration point in the host startup program.

The module intentionally does not write NeoGS-local DMA registers (#1B..#1F), because those are NeoGS-side registers, not ATM-side ports. Bulk DMA must be initiated/owned according to the agreed NeoGS DMA protocol and ATM hardware mapping; this source does not pretend that mapping has already been defined.

## 6. Version and verification

- Source version: `P126 ATM_IPC v0.1.0`.
- Listing and map are generated on every successful build alongside the NeoGS listing/map.
- CI build PASS: run `42274548106`, SjASMPlus 1.23.1, 235 source lines, 0 errors, 0 warnings, binary size 181 bytes; listing 14,766 bytes; map 1,407 bytes. [Build artifact](https://github.com/JTCyborg/Project126/actions/runs/42274548106).
- Assembly success proves syntax and image-boundary assertions only. It does not prove live ATM↔NeoGS handshake on hardware.
