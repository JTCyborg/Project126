# Project126 — unified DMA/IPC protocol

Version: P126 DMA/IPC ABI 1.0
Status: normative specification baseline. Runtime implementation and hardware verification are separate milestones.

## 1. Scope and ownership

ATM Turbo 2+ Z80 is the sole owner of physical hardware and host services. NeoGS Z80 owns the guest 8086 machine and its software device models. NeoGS never accesses ATM peripherals or physical host ports directly.

There is one transport for all application traffic: firmware/BIOS blocks, host-service requests and responses, keyboard events, video frames, storage, clock snapshots and diagnostics. Services differ by service_id and operation, not by transport.

The transport has two planes:
- Control plane: one-byte GSCOM command/doorbell and CBIT READY/end handshake.
- Data plane: ZX DMA memory window. All frame headers and payload bytes use DMA. DBIT/GSDAT are not application payload transport.

ATM may access only documented ATM-facing ports #BB, #B3 and #33. NeoGS-local DMA registers are accessed only by NeoGS firmware.

## 2. Hardware DMA contract

NeoGS-local registers:

| Register | Port | Contract |
|---|---:|---|
| DMA_MOD | #1B | Select DMA module; ZX module = 1 |
| DMA_HAD | #1C | Physical NeoGS address bits 21..16 |
| DMA_MAD | #1D | Physical NeoGS address bits 15..8 |
| DMA_LAD | #1E | Physical NeoGS address bits 7..0 |
| DMA_CST | #1F | Bit 7 enables ZX DMA; zero disables it |

The ATM-visible ZX DMA aperture is 0000h..3FFFh (16 KiB), as documented by the NeoGS DMA specification and used by Project125. HAD/MAD/LAD contain a NeoGS physical RAM address, not an ATM address. The ATM driver must never write ports #1B..#1F.

DMA writes deposit host-written aperture bytes at the NeoGS destination. DMA reads expose NeoGS source bytes through the same host aperture. No dummy write is required. The first read from the aperture is a dummy read and must be discarded before collecting the first valid byte. Read and write directions must not be interleaved in one armed DMA transaction.

The aperture and direction are hardware-defined. Project126 production staging is page 42h (physical 108000h), as reserved in docs/P126_NEOGS_MEMORY_MAP.md. The current page-42 diagnostic maps that page into WIN3 through MPAGEX port #10 before arming DMA, using the Project125 selector encoding (rotate-right circular: physical page bit 0 moves to selector bit 7, implemented by `RRCA`); PG3 port #23 is not the WIN3 selector; resident code/data/stack remain outside WIN3. This new mapping is a separate hardware validation stage and is not covered by the page-03 Project125 parity PASS.

For the current hardware-parity diagnostic only, the endpoints deliberately use the known Project125 physical addresses: ATM→NeoGS destination 00D000h and NeoGS→ATM source 00E000h (both in physical page 03h). The Project126 resident maps physical page 03h into WIN1 through PG1 port #21, exactly as Project125 does. The 274-byte diagnostic buffers occupy D000h..D111h and E000h..E111h; they are explicit carve-outs and do not overlap the operational stack at 7FFEh. This temporary diagnostic placement must not be mistaken for the production ABI staging allocation or generalized to arbitrary full-aperture frames. The ATM reverse reader performs DI before its mandatory dummy read, matching Project125 and preventing IM1 from fetching DMA bytes at #0038h.

Project125's DMA rules remain normative: host→NeoGS writes have no dummy write; NeoGS→host reads require ROM visible at 0000h..3FFFh and exactly one discarded first read; DMA directions are not interleaved; stop DMA before changing direction. The GS105a-specific post-enable settling delay is not automatically imposed on the resident endpoint.

## 3. Control commands and transaction lifecycle

These private GSCOM commands are reserved for the Project126 resident protocol endpoint. They are not sent to stock GS105a ROM handlers:

| Value | Name | Meaning |
|---:|---|---|
| E0h | P126_CMD_HOST_FRAME | ATM writes one frame to NeoGS by DMA |
| E1h | P126_CMD_NGS_FRAME | ATM reads one frame from NeoGS by DMA |
| E2h | P126_CMD_RESYNC | Start/restart protocol session negotiation |
| E3h | P126_CMD_CAPABILITIES | Request protocol/capability frame |
| FFh | P126_CMD_DMA_END | Host end marker; control only, never payload |

These commands are valid only while the Project126 resident firmware owns GSCOM.

### 3.1 ATM to NeoGS frame

1. ATM sends E0h through GSCOM.
2. NeoGS validates command/state, selects ZX DMA, programs its own destination address, enables DMA, then clears CBIT to signal READY.
3. ATM waits for CBIT=0 with a bounded timeout and writes exactly the declared frame byte count to aperture 0000h..3FFFh.
4. ATM sends FFh through GSCOM as the end marker.
5. NeoGS observes CBIT=1, disables DMA, validates the complete frame (including CRC and bounds), then clears CBIT to acknowledge completion.
6. ATM waits for CBIT=0. Only this final acknowledgement completes the DMA transaction.

### 3.2 NeoGS to ATM frame

1. ATM sends E1h through GSCOM.
2. NeoGS validates command/state, selects ZX DMA, programs its own source address and enables DMA, then clears CBIT to signal READY.
3. ATM waits for CBIT=0, discards exactly one dummy aperture read, then reads the fixed 18-byte header first.
4. ATM validates magic/version/type/flags and checks that 18 + payload_length fits the 16 KiB aperture and destination capacity. If invalid, it terminates the DMA transaction immediately with FFh and discards the frame.
5. For a valid header, ATM reads exactly payload_length more bytes; it then sends FFh through GSCOM.
6. NeoGS observes CBIT=1, disables DMA and clears CBIT to acknowledge completion.
7. ATM waits for CBIT=0 before releasing the destination buffer, then validates the complete frame CRC before dispatch.

A receiver validates the fixed header and declared payload length before copying into a final service buffer. NeoGS production DMA staging is page 42h / physical 108000h (WIN3 logical C000h in the current diagnostic); ATM-side final source/destination buffer placement remains separately assigned by its host memory map.

### 3.3 Failure and recovery

- Every wait is bounded.
- Every timeout, cancellation, malformed frame, reset and error path disables an armed DMA engine on the NeoGS side before releasing the transaction.
- ATM must not issue another frame command while DMA is active.
- A lost READY or completion acknowledgement is a transaction failure, not success inferred from byte count.
- RESYNC is issued only after the endpoint is safe; the endpoint disables DMA, clears stale command state and negotiates a new session.
- A processor reset invalidates all in-flight frames, partial reassembly and duplicate-cache entries. Both sides renegotiate before service traffic resumes.

## 4. Frame ABI 1.0

All multibyte integers are unsigned little-endian. Fixed header: exactly 18 bytes.

| Offset | Size | Field | Meaning |
|---:|---:|---|---|
| 00h | 4 | Magic | ASCII P126 |
| 04h | 1 | Major | 01h |
| 05h | 1 | Minor | 00h |
| 06h | 1 | Message type | 01=request, 02=response, 03=event, 04=cancel |
| 07h | 1 | Service ID | Service namespace |
| 08h | 1 | Operation | Operation within service |
| 09h | 1 | Flags | Defined below |
| 0Ah | 2 | Sequence | Per-direction transaction sequence |
| 0Ch | 2 | Payload length | Payload bytes, excluding header |
| 0Eh | 2 | Status | Zero in request/event; result in response |
| 10h | 2 | CRC16 | CRC-16/CCITT-FALSE, little-endian |

DMA frame size is 18 + payload_length bytes. It must fit wholly within one 16 KiB DMA aperture transaction; maximum payload per frame is 16366 bytes. A frame never crosses a DMA window boundary.

Flags:
- bit 0 ACK_REQUIRED;
- bit 1 FRAGMENT;
- bit 2 IDEMPOTENT;
- bits 3..7 reserved and must be zero in ABI 1.0.

CRC-16/CCITT-FALSE: polynomial 1021h, initial value FFFFh, no reflection, xorout 0000h. Calculate over header bytes 00h..0Fh followed by exactly payload_length payload bytes. CRC field 10h..11h is excluded. Standard ASCII vector 123456789 must produce 29B1h.

Validation order: frame/aperture bound; magic; major/minor compatibility; message type and reserved flags; service/operation support; sequence/session rules; payload bounds; CRC. No service handler consumes a frame before validation succeeds.

## 5. Fragmentation

A logical message larger than one frame is carried as independently CRC-checked frames. Every fragment has FRAGMENT set and begins with this 10-byte little-endian extension:

| Offset in fragment payload | Size | Field |
|---:|---:|---|
| 00h | 2 | Message ID |
| 02h | 2 | Fragment index, zero-based |
| 04h | 2 | Fragment count |
| 06h | 4 | Total logical payload length |

Remaining payload bytes are fragment data. Fragment data per frame is at most 16356 bytes. All fragments share service, operation, message ID, fragment count and total length; each frame has its own sequence and CRC. ABI 1.0 accepts fragments in index order only. Reassembly rejects inconsistent metadata, missing/duplicate/out-of-order fragments, overflow and totals beyond the receiver's configured buffer limit. Capacity must be reserved before accepting the first fragment. Maximum logical message size is limited by reserved memory, not inferred from the 24-bit DMA address space.

## 6. Sequence, duplicate and session rules

- One DMA transaction is active at a time; ABI 1.0 does not require parallel or out-of-order transactions.
- Each direction has an independent 16-bit sequence counter. Sequence 0000h is reserved for session negotiation; normal traffic starts at 0001h and wraps FFFFh to 0001h.
- A response echoes the request sequence. Events use the sender's sequence space.
- Receiver remembers the most recently completed request sequence and its CRC/result. Same sequence and CRC is a duplicate and must not repeat a non-idempotent host operation; cached response may be replayed. Same sequence with different CRC is SEQUENCE_ERROR.
- Stale sequences are rejected. A sliding window is not required.
- RESYNC discards partial frames/reassembly and resets sequence state only after both endpoints enter resynchronization. HELLO/capabilities exchange establishes the session before service traffic.
- A response status is authoritative only after its entire frame is received and validated.

## 7. Message types, services and result codes

Message types: REQUEST (01h), RESPONSE (02h), EVENT (03h), CANCEL (04h).

Initial service IDs (reserved namespace; defining an ID does not mean the service is implemented):

| ID | Service |
|---:|---|
| 00h | Protocol/session control |
| 01h | Host input / keyboard |
| 02h | Video presenter |
| 03h | Storage |
| 04h | Clock |
| 05h | Diagnostics |
| 06h | Machine configuration/capabilities |
| 07h | Firmware and BIOS image transfer |

Response status codes:

| Code | Name |
|---:|---|
| 0000h | OK |
| 0001h | BAD_MAGIC |
| 0002h | UNSUPPORTED_VERSION |
| 0003h | BAD_FRAME |
| 0004h | CRC_ERROR |
| 0005h | SEQUENCE_ERROR |
| 0006h | UNSUPPORTED_SERVICE |
| 0007h | UNSUPPORTED_OPERATION |
| 0008h | NO_BUFFER |
| 0009h | HOST_IO_ERROR |
| 000Ah | TIMEOUT |
| 000Bh | CANCELLED |
| 000Ch | ADDRESS_RANGE |
| 000Dh | BUSY |
| 000Eh | RESET_REQUIRED |
| 000Fh | BAD_FRAGMENT |

## 8. Initial operations

| Service | Operation | Direction | Purpose |
|---|---:|---|---|
| Protocol/session | 00h | bidirectional | HELLO/version negotiation |
| Protocol/session | 01h | bidirectional | capability exchange |
| Protocol/session | 02h | bidirectional | resynchronize |
| Diagnostics | 00h | NeoGS to ATM | structured diagnostic record |
| IMAGE | 00h | ATM to NeoGS | begin image transfer (metadata) |
| IMAGE | 01h | ATM to NeoGS | image data fragment |
| IMAGE | 02h | ATM to NeoGS | finish and verify image |
| IMAGE | 03h | NeoGS to ATM | image transfer result (reserved; response frame not yet implemented) |

### Initial SYSBIOS transfer profile

The first implemented image profile is an 8 KiB system BIOS:

- `IMAGE_BEGIN` payload is exactly 6 bytes: message ID (u16 LE), image kind (u8; 00h = SYSBIOS), reserved byte (00h), image size (u16 LE; 2000h).
- `IMAGE_FRAGMENT` must set the ABI FRAGMENT flag. Its payload begins with the standard 10-byte extension from section 5: message ID, fragment index, fragment count, total logical data length. The initial profile accepts exactly one fragment: index 0, count 1, total length 2000h; the remaining 8192 payload bytes are the image.
- `IMAGE_FINISH` payload is exactly the 2-byte message ID. It succeeds only after the expected fragment has been installed.
- Message ID for the initial single-image boot transaction is 0001h. Normal ABI frame sequence values are 0001h, 0002h and 0003h for BEGIN, FRAGMENT and FINISH.
- SYSBIOS destination is physical NeoGS page 10h (base 040000h), offset 0000h. The guest-visible ROM overlay remains FE000h–FFFFFh; reset vector FFFF0h is image offset 1FF0h.
- DMA staging remains physical page 42h (108000h). The resident handler copies the validated fragment to page 10h through WIN3 MPAGEX #10 selectors 21h (page 42h) and 08h (page 10h). No DBIT/GSDAT application payload is used.
- The receiver keeps CBIT asserted until the IMAGE service handler has completed; the host DMA completion wait uses eight independent #FFFF windows for the post-receive copy.

This is the initial fixed-size SYSBIOS profile, not a general image reassembly implementation. IMAGE_RESULT (03h), multi-fragment images, VGA BIOS image installation, and service-level response frames remain unimplemented. Source build success does not prove physical page-10 installation; that requires a target log.

### Fixed-origin overlay transfer profiles

The first fixed-origin overlay is the XT I/O model, with image kind `01h` (`P126_IMAGE_KIND_X86IO`):

- TR-DOS file: `X86IO.C`; fixed assembly origin: logical `8000h`; current image size: 796 bytes.
- IMAGE_BEGIN payload is exactly 6 bytes: message ID `0001h`, kind `01h`, reserved byte `00h`, image size as u16 LE. The receiver accepts 1..1000h bytes for this profile.
- IMAGE_FRAGMENT is exactly one fragment: index 0, count 1, total logical length u32 LE equal to the IMAGE_BEGIN size, followed by the complete X86IO image. The frame carries the normal ABI FRAGMENT flag and CRC.
- ATM loads the TR-DOS file after the resident A2h acknowledgement. The first 256-byte sector is copied backwards from C000h to C01Ch so that the frame header remains intact despite overlap; subsequent sectors are read directly into the following data area.
- NeoGS copies the validated fragment from DMA staging page 42h to physical kernel page 04h through WIN3 and compares every installed byte against the source still in page 42h.
- IMAGE_FINISH runs a reversible WIN2 mapping/read/write test at BFFFh across pages04/05, then a temporary page05 test stub calls the resident X86IO wrapper on page04. The RET trampoline must restore page05 so the stub resumes; the original page05 bytes are restored, WIN2 is returned to page04, and only then IO_OVERLAY_READY is published. The combined target log is `[NGS] WIN2 MAP/GATE TEST PASS`.
- CPU-facing X86IO entry points are resident wrappers through the WIN2 call gate; implementation code remains fixed at logical 8000h on page04. The gate saves/restores the prior selector on the WIN1 stack and supports stack-nested page switches, but has no dynamic module table/allocator or unload policy.
- BIOS execution is gated until IO_OVERLAY_READY, X86ALU_READY and BIOS_IMAGE_READY are all set.

### X86ALU fixed-origin transfer profile

The second overlay is the 8086 arithmetic/flags implementation, image kind 02h (P126_IMAGE_KIND_X86ALU):

- TR-DOS file X86ALU.C; logical origin 8000h; current image size 1,187 bytes.
- Destination is physical kernel page05, selected through WIN3 with MPAGEX selector82h (ROR8(05h)); maximum size is 4096 bytes.
- ATM uses the same fixed-profile loader and one-fragment ABI1.0 IMAGE transaction as X86IO.
- NeoGS performs byte-for-byte readback. IMAGE_FINISH calls x86_alu_overlay_probe through the resident gate, checks input A=3C/C=1/HL=1234, output A=A5/HL=5AA5, and confirms WIN2 returns to page04 before publishing X86ALU_READY.
- The ten ALU entry points used by x86_exec are resident wrappers; internal helpers remain within page05.

These are two separate single-fragment pinned profiles, not a generic manifest/reassembly service. CI passes; ATM/NeoGS transfer and both gate tests still require target verification.

## 9. Compatibility and migration

- ABI 1.0 is available only after Project126 resident firmware has started and owns GSCOM.
- Existing ATM p126_ipc_send_byte / p126_ipc_receive_byte remain low-level legacy helpers for stock ROM/bootstrap compatibility. They are not used for ABI 1.0 application payloads.
- CBIT/DBIT polling may remain as hardware primitives, but DBIT/GSDAT is not an alternate application data channel.
- No independent transport may be introduced for video, BIOS, keyboard, storage, clock or diagnostics.
- Before services are enabled, both DMA directions require deterministic full-content hardware tests, including first/last byte, 16 KiB boundary, timeout and DMA-disable checks.

## 10. Implementation boundaries and next work

This document fixes the ABI and lifecycle contract, not the runtime memory map. Remaining work:
1. CRC primitives and local-buffer frame validation are implemented on both processors; sequence/session state remains pending.
2. ATM sender and callable NeoGS receive endpoint are implemented; wire the receiver into the resident command dispatcher and verify both directions on hardware.
3. Reserve and assert staging buffers and DMA source/destination windows in the Project126 4 MiB NeoGS map and ATM host memory map.
4. Add deterministic DMA write/read tests and full-frame CRC tests on hardware.
5. Migrate application payloads from DBIT/GSDAT to DMA frames.
6. Implement bounded service dispatch and service-specific ABIs.

This specification alone does not imply BUILD PASS, EMULATOR PASS or HARDWARE PASS.


## 11. First callable NeoGS command dispatcher

The NeoGS IPC module exports `p126_ngs_ipc_dispatch_once`. It samples ZXSTAT/CBIT, returns immediately when no command is pending, reads ZXCMD when CBIT is asserted, and routes E0h to the DMA receive endpoint. Unimplemented command IDs are acknowledged by clearing CBIT and return `NO_OPERATION`, preventing the ATM sender from waiting forever on an unsupported doorbell.

The receiver restores the validated frame pointer and exact byte count after the validator returns (the validator clobbers BC/HL). A valid frame returns HL=C000h and BC=18+payload_length; errors return carry set and the ABI status in A. Version mismatches use the shared `BAD_VERSION` status.

The IPC module is linked into `X86CORE.C` after x86 state, execution and ModR/M. The ALU implementation is a separate page05 overlay; resident wrappers link its public entry points to the call gate. The resident startup maps WIN0/page 00 and WIN1/page 03, establishes the stack at 7FFEh, and repeatedly calls `p126_ngs_ipc_dispatch_once`. WIN2 is initialized to page 01 until the X86IO overlay is installed; WIN3 remains the guest-memory aperture.

After the resident A2h acknowledgement, ATM reads `X86IO.C` and `X86ALU.C` from TR-DOS and sends both IMAGE transactions through ABI 1.0 DMA. NeoGS installs them at physical pages04/05 through WIN3 and verifies every byte. The resident gate maps page04 or page05 into WIN2 on each public call. BIOS execution is gated until X86IO, X86ALU and SYSBIOS are all ready.

Verification boundary: CI verifies assembly, split-image sizes, and TR-DOS packaging. Only target testing can verify both overlay DMA transfers/readbacks, the page04/page05 gate probes, ZXCMD/CBIT timing, DMA page42 behavior, and subsequent BIOS I/O/ALU execution.


## 12. Resident startup and GS105a bootstrap

Project126 now has a concrete startup chain:
1. ATM reads the TR-DOS directory before video paging is enabled.
2. ATM locates `P126BOOT.C` and `X86CORE.C` in that preloaded directory and reads their sectors with the established TR-DOS C=5/B=1 sector API.
3. ATM resets NeoGS through GSCTR, probes the stock GS105a ROM with command 20h, and uses ROM commands 14h/13h to load and enter stage-0 at logical 4000h.
4. Stage-0 switches to writable RAM-over-ROM, establishes temporary WIN2/WIN3 mappings and a temporary stack, receives a bounded 1..4000h resident image over the legacy DBIT bootstrap byte channel, then jumps to address 0000h.
5. The resident entry maps WIN0 to physical page 00, WIN1 to physical page 03, initializes WIN2 to page 01, places the operational stack at 7FFEh, runs the CRC self-test and publishes A2h as the resident-ready acknowledgement.
6. The resident main loop continuously calls `p126_ngs_ipc_dispatch_once`. After A2h, ATM loads `X86IO.C` and `X86ALU.C` and sends their IMAGE transactions; NeoGS installs them at physical pages 04 and 05, performs byte-for-byte readback, and uses the resident gate to map either into WIN2.
7. Subsequent SYSBIOS IMAGE traffic uses the same ABI 1.0 DMA path. BIOS execution starts only when X86IO, X86ALU and SYSBIOS images are ready.

DBIT/GSDAT is used only for stock-ROM bootstrap compatibility. After A2h, application payloads use ABI 1.0 DMA; NeoGS does not perform direct physical host I/O. ATM startup file reads occur before ATM video initialization to preserve the established TR-DOS paging constraints.

The resident `X86CORE.C` must fit within one 16 KiB WIN0 page; the current build is 15,632 bytes. `X86IO.C` (796 bytes) is pinned to physical page04 and `X86ALU.C` (1,187 bytes) to page05; both use logical origin 8000h and resident wrappers. Pages06h–0Fh remain reserved for future dynamic overlays and are not yet managed by a general allocator. P126BOOT.C is limited to one 256-byte TR-DOS sector.

Hardware verification remains outstanding: stock-ROM reset/probe timing, #14/#13 transfer, DBIT turnaround, RAM-over-ROM paging, stack page 03, A2 ready acknowledgement and the first E0/DMA/FF frame exchange must be exercised on target hardware.


## DMA/IPC end-to-end diagnostic trace (2026-11-07)

The ATM host and NeoGS resident emit independent trace messages directly to their own physical debug port #EF. The identical port number does not mean a shared CPU channel; do not synthesize one processor's messages from the other processor.

ATM sender trace, in expected order:
- [ATM IPC] DMA TX BEGIN
- FRAME VALID or FRAME VALIDATION FAILED
- SEND E0, followed by E0 ACK / READY (or E0 ACK TIMEOUT)
- DMA COPY BEGIN / DMA COPY DONE
- SEND FF, followed by DMA TX COMPLETE (or FF ACK TIMEOUT)

NeoGS receiver trace, in expected order:
- DMA E0 RECEIVED
- DMA CONFIG BEGIN, DMA ARMED, DMA READY (after CBIT release)
- DMA HOST END DETECTED, DMA STOPPED, DMA PAGE 42 MAPPED, DMA END RECEIVED
- DMA FRAME VALID, or DMA FRAME REJECTED STATUS=HH
- Explicit DMA WAIT TIMEOUT and invalid-frame-length diagnostics are emitted on those error paths.

Interpretation: if ATM reports local FRAME VALIDATION FAILED, the receiver was never called. If ATM reaches SEND E0 but NeoGS has no DMA E0 RECEIVED, inspect command/CBIT visibility. If NeoGS reports READY but ATM times out waiting for E0 acknowledgement, inspect CBIT release. If ATM reports COPY DONE but NeoGS never sees HOST END DETECTED, inspect the DMA transfer/end-marker path. If NeoGS reports FRAME REJECTED STATUS=04, compare the frame bytes and CRC calculation; statuses 01/02/03 identify magic/version/structural rejection.

Both frame validators now keep the frame pointer intact during CRC calculation and begin payload CRC at byte offset 18, after the two stored CRC bytes. This correction applies to non-empty payloads as well as the zero-payload smoke frame.

Diagnostic output adds timing overhead, especially around the DMA copy. It is intentionally placed at transaction boundaries rather than inside polling loops. If timing-sensitive hardware behavior changes, retain the stage markers but disable or reduce verbose strings for the final transport implementation.

- **Verification:** GitHub Actions run [42351776510](https://github.com/JTCyborg/Project126/actions/runs/42351776510), commit `d9b2a391ddaf0bbf4ccd918b34a58cbecc17f40e`, completed successfully. ATM IPC and NeoGS assembly, including the new trace code, passed; TR-DOS image packaging and artifact publication also completed. This is BUILD PASS only. No hardware trace or DMA runtime PASS is claimed.


### 2026-11-07 — локализация ATM CRC_ERROR и сверка с Project125

- **Аппаратный лог пользователя:** ATM выводит `[ATM IPC] FRAME VALIDATION FAILED`, затем `DMA FAIL STAGE=1` и `DMA VALIDATOR ERROR=04`. Это `P126_STATUS_CRC_ERROR`; отказ происходит в локальном ATM валидаторе до команды E0. NeoGS receiver и DMA engine на этом запуске ещё не задействованы.
- **Сверка с Project125:** изучены `PROJECT125_DMA_IPC.md`, `NeoGS/dma_zx_doc.txt`, `NeoGS/ports.inc`, `zx_main/neogs_transport_v2.asm` и `shared/neogs_io.inc`. Для ATM→NeoGS запись Project125 использует host write в DMA aperture `0000h..3FFFh`; NeoGS настраивает DMA module 1, HAD/MAD/LAD и CST bit 7. Dummy read из документа относится к обратному направлению NeoGS→ATM; dummy write перед ATM→NeoGS не требуется. Отдельно учтено предупреждение Project125 о задержке после включения DMA в сценариях, где управление DMA идёт через штатный GS105a ROM. Текущий P126 обмен выполняется уже резидентной прошивкой, поэтому это предупреждение проверяется на аппаратном этапе, а не объявляется причиной текущего CRC отказа.
- **Изменено:** `atm_host/neogs_ipc.asm` — перед сравнением CRC теперь выводятся две независимые величины: CRC, рассчитанный ATM валидатором, и CRC, сохранённый в байтах 16–17 кадра. Это позволит определить, ошибка ли в вычислении или в подготовке/записи кадра.
- **Эталон smoke frame:** первые 16 байт `50313236010001050000010000000000`; CRC-16/CCITT-FALSE должен быть `FF5B`, хранение little-endian — `5B FF`. Это рассчитано независимо и соответствует стандартному алгоритму Project125 bootstrap.
- **Следующий диагностический критерий:** сравнить в новом логе `CRC CALCULATED=FFFF`-формат и `FRAME CRC=FFFF`-формат. Если отличаются — локализовать вычисление/подготовку; если оба `FF5B`, но валидатор всё равно возвращает 04 — проверять саму последовательность сравнения/адресацию.
- **Проверка диагностического патча:** GitHub Actions run [42352070894](https://github.com/JTCyborg/Project126/actions/runs/42352070894), commit `6cf8fd152fb492d2c5f6c7979386cb4bde643354`, completed with BUILD PASS (ATM/NeoGS assembly and TR-DOS image packaging). Аппаратное подтверждение значений CRC ожидается от следующего запуска пользователя.
- **Статус:** исходная аппаратная ошибка подтверждена логом; вычисленный и сохранённый CRC ещё требуется сопоставить на реальном ATM. DMA аппаратный PASS не заявляется.


## ATM validator correction — 2026-11-07

The ATM frame validator must preserve the CRC accumulator in `HL` while switching from header traversal to payload traversal. The payload pointer saved on the stack is restored directly into `IX` (`pop ix`); restoring it through `HL` destroys the accumulated CRC. This is a local implementation constraint and does not change ABI 1.0: CRC still covers header bytes 00h..0Fh followed by exactly `payload_length` bytes, excluding CRC bytes 10h..11h. The zero-payload regression frame must validate to `FF5B`.


### 2026-11-07 — DMA проходит, NeoGS отклоняет magic

- Новый аппаратный лог подтверждает, что локальный ATM validator прошёл (CRC CALCULATED=FF5B FRAME CRC=FF5B, FRAME VALID), NeoGS принял E0, включил DMA, ATM выполнил копирование и FF, NeoGS остановил DMA и освободил CBIT.
- NeoGS затем вернул DMA FRAME REJECTED STATUS=01 (BAD_MAGIC). Значит, ошибка находится после DMA-передачи — в содержимом, видимом через WIN3/page 42, либо в отображении/адресации staging buffer. CRC/handshake больше не являются текущим препятствием.
- Добавлена временная диагностика в neogs_sub/p126_ipc.asm: сразу после остановки DMA и отображения страницы 42 выводятся первые четыре байта, реально прочитанные из C000h..C003h как [NGS] DMA RX FIRST4=...
- По следующему логу: 50313236 означает, что magic P126 присутствует; тогда надо проверять путь/содержимое при валидации. 00000000, FFFFFFFF или другие значения покажут, что DMA-буфер не содержит ожидаемые первые байты, и позволят локализовать физический адрес/направление/окно.
- Пока не менялись DMA-регистры, адрес 108000h, ABI или handshake: сначала снимаем фактические байты, не подменяя диагностику предположением.
- Проверка: аппаратный лог пользователя подтверждает завершение транзакции, но frame validation пока FAIL. Временная диагностическая сборка должна пройти CI до следующего аппаратного теста.


## 2026-11-07 — hardware receive-buffer diagnostics

For the ATM→NeoGS smoke transaction, the configured destination is physical address 108000h (page 42h, offset 0000h). The host writes its frame to the 0000h..3FFFh DMA aperture; NeoGS stops DMA and maps page 42h into WIN3 at C000h.

The latest target log reached the end marker but showed 00000000 at the first four bytes read through WIN3, followed by BAD_MAGIC. This proves command/CBIT lifecycle only; it does not prove payload delivery to NeoGS RAM. The next diagnostic build reports post-stop DMA address-register readback, performs a reversible WIN3 RAM test at C100h outside the 18-byte smoke frame, and dumps all 16 fixed header bytes. Address-register readback is observational until confirmed against the hardware's documented register semantics. No DMA address or ABI change is implied by these diagnostics.


## DMA destination pre-map diagnostic (2026-11-07)

The latest hardware log reports DMA address readback 108012 after an 18-byte write to target 108000, WIN3 RW TEST=PASS, but a zero-filled received header. This confirms the selected CPU window is writable while leaving the DMA payload path unproven.

Project125's established command_load_x86 sequence maps its destination page into the CPU window before arming ZX DMA and keeps that mapping stable throughout the transfer. Project126 is aligned with that ordering for page 42: WIN3 is selected before DMA register setup and is not switched after DMA stop. Resident code/data/stack remain outside WIN3. The DMA address, module, aperture, ABI and CBIT/FF handshake are unchanged.

This is a diagnostic ordering alignment, not a claim that CPU window mapping controls the DMA physical destination. If the next header dump remains zero, investigation must continue at the host aperture write/data-capture path.


## Reverse DMA diagnostic using ABI command E1h (2026-11-07)

The E1h control-plane command is exercised as the ABI 1.0 NGS_FRAME direction. NeoGS constructs a complete 274-byte response frame in physical page 42h at 108000h: the fixed 18-byte ABI header followed by 256 deterministic payload bytes (00h..FFh), with CRC-16/CCITT-FALSE over header bytes 00h..0Fh and the payload. It then arms ZX DMA module 1 for the reverse direction.

ATM waits for CBIT clear (DMA ready), performs and discards the first memory read from the 0000h DMA aperture as required by the NeoGS hardware documentation, then reads exactly 274 bytes. It sends FFh through GSCOM to terminate the transfer. NeoGS stops DMA and acknowledges by clearing CBIT. ATM validates the complete frame CRC and independently checks the 256-byte payload sequence.

This diagnostic does not change ABI 1.0, DMA module, physical staging address (108000h), or the ATM->NeoGS E0h transaction. It requires the normal ROM mapping to remain visible in ATM address range 0000h..3FFFh during the reverse read; if RAM is mapped there, NeoGS cannot drive the DMA read cycles. A successful build is not a hardware PASS: both independent debug streams must show the E1h exchange and ATM must report DMA RX PATTERN PASS.


## 9.1 Production page-42 DMA validation procedure (2026-11-07)

The diagnostic implementation now tests the reserved production staging page independently of the proven page-03 Project125 parity path:

1. NeoGS selects WIN3 through MPAGEX port #10 before DMA setup. It uses the exact Project125 selector sequence `LD A,42h / RRCA / OUT (10h),A` (encoded selector 21h); PG3 port #23 is not used for WIN3. The mapped CPU view is C000h-FFFFh; resident code, data and stack stay in WIN0-WIN2.
2. For ATM→NeoGS, NeoGS arms DMA module 1 at physical 108000h (HAD=10h, MAD=80h, LAD=00h). ATM sends a 274-byte frame (18-byte header + 256-byte 00h..FFh payload). NeoGS stops DMA at FF/end, derives the declared frame size, enforces the 16 KiB page bound and validates the full CRC from C000h.
3. For NeoGS→ATM, NeoGS constructs the same-size deterministic response in page 42h through C000h and arms DMA read at 108000h. ATM keeps the Project125 reverse sequence: DI, one discarded read from ROM aperture 0000h, then exactly 274 data bytes, FF/end, full-frame CRC and payload-pattern validation.
4. A complete target PASS requires both directions, full payload integrity and the expected physical DMA address progression 108000h→108112h. The earlier page-03 Project125 parity PASS remains a separate result and must not be conflated with page-42 validation.

This is a diagnostic test only; it does not yet implement ABI multi-frame fragmentation/reassembly or sustained streaming.


## WIN3 page-selector correction — 2026-11-07

The first production page-42 implementation used port 23h (PG3) and wrote the raw page number 42h. This did not reproduce Project125's WIN3 mapping. Project125 uses MPAGEX port 10h for the C000h–FFFFh window and rotates the physical page number right once before writing the selector. Project126 now follows that exact sequence for both DMA directions. The physical DMA destination/source remains 108000h; no DMA register, host aperture, dummy-read rule, or E0/FF handshake change is made.

The 09:44 target log showed the reverse transfer CRC as 7C1C, identical to the ATM request frame, although the NeoGS response frame (RESPONSE header plus payload 00h..FFh) must have CRC D867. This means the earlier reverse PATTERN PASS was not proof that the response had been constructed in the selected production page; the reverse direction must be revalidated after correcting WIN3 selection. Production page-42 HARDWARE PASS remains pending.



## Production page 42h hardware result — 2026-11-07

Physical ATM/NeoGS log at 09:52:27 confirms both directions on the corrected production mapping. Forward: 274-byte ATM request CRC 7C1C, DMA 108000h→108112h, NeoGS header 50313236010001050000010000010000 and DMA FRAME VALID. Reverse: readback 108113h (discarded first ROM-aperture read plus 274 frame bytes), ATM CRC D867 matches frame CRC, and DMA RX PATTERN PASS validates payload 00h..FFh. The page-42 MPAGEX #10 / RRCA correction is now HARDWARE PASS for this smoke-frame size. Larger frames, fragmentation/reassembly and sustained streaming remain pending.


## Maximum-size frame validation stage — 2026-11-07

Before enabling fragmentation, the target diagnostic sends one ABI 1.0 frame of exactly 4000h bytes (18-byte header + 3FEEh payload) in each direction. The payload repeats 00h..FFh and is checked byte-for-byte on reverse reception; CRC-16/CCITT-FALSE covers the complete payload on both endpoints. The forward DMA counter must read 10C000h after the transfer. The reverse counter must read 10C001h, accounting for the single discarded ROM-aperture read. ATM reuses its C000h..FFFFh RAM page-0 TR-DOS staging window for TX and RX sequentially. This is a diagnostic extension only: ABI 1.0, page-42 mapping, module 1, and E0/E1/FF handshake are unchanged. A successful 274-byte hardware test does not imply the 16 KiB test has passed.


## ATM max-frame test staging requirement

The ATM host binary is packaged only through `p126_host_program_end` (currently constrained to `A800h`). A staging buffer at `C000h` is runtime RAM and must not rely on static `db/defs` bytes placed outside the packaged host image. The max-frame test must initialize its complete 18-byte header at runtime before payload fill and CRC calculation. The 2026-11-07 hardware diagnostic `PTR=C000 DATA=20444D41` exposed this exact defect; commit `b366a37318d89f02f613e848e106db9f3fcf219c` implements the runtime header initialization. Build and target verification remain pending.


## ATM transmit preflight

The ATM sender performs structural validation only before E0/READY: frame bounds, P126 magic, ABI version, REQUEST message type, reserved flags, and declared payload length. It deliberately does not recalculate the outgoing payload CRC in the pre-transfer path. The frame builder calculates CRC-16/CCITT-FALSE, and NeoGS validates the complete received frame after DMA closes. ATM still performs full CRC validation on reverse-DMA frames. This preserves the Project125 host transport sequence and avoids a redundant 16 KiB CRC pass before DMA startup.
