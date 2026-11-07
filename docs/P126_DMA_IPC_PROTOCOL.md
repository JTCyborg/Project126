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

The aperture and direction are hardware-defined. Project126 staging addresses, ATM source/destination buffer placement, paging assumptions and resident memory reservations remain to be assigned by Project126 memory-map/integration work. Do not copy Project125 physical page addresses or stack layout by assumption.

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

A receiver validates the fixed header and declared payload length before copying into a final service buffer. It may DMA first into a bounded staging buffer; the staging address is not yet assigned.

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
| Firmware/BIOS | 00h | ATM to NeoGS | begin image transfer (metadata) |
| Firmware/BIOS | 01h | ATM to NeoGS | image data fragment |
| Firmware/BIOS | 02h | ATM to NeoGS | finish and verify image |
| Firmware/BIOS | 03h | NeoGS to ATM | image transfer result |

BIOS destination addresses, guest ROM mapping, NeoGS image staging addresses, final service ABIs and maximum reassembly buffers are intentionally not defined here; they depend on separate Project126 memory-map and runtime integration decisions.

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

The IPC module is linked into `X86CORE.C` after the x86 state and ALU modules. This makes the dispatcher available in the core artifact, but does **not** claim a complete resident firmware or active main loop. The repository still has no NeoGS startup/loader that establishes WIN0-WIN2 placement and repeatedly calls `p126_ngs_ipc_dispatch_once`. That remains a separate integration milestone.

Verification boundary: CI can verify assembly, symbol placement, and packaging. Only target testing can verify ZXCMD/CBIT timing, DMA writes into page 42h, WIN3 mapping, CRC and timeout behavior.


## 12. Resident startup and GS105a bootstrap

Project126 now has a concrete startup chain:
1. ATM reads the TR-DOS directory before video paging is enabled.
2. ATM locates `P126BOOT.C` and `X86CORE.C` in that preloaded directory and reads their sectors with the established TR-DOS C=5/B=1 sector API.
3. ATM resets NeoGS through GSCTR, probes the stock GS105a ROM with command 20h, and uses ROM commands 14h/13h to load and enter stage-0 at logical 4000h.
4. Stage-0 switches to writable RAM-over-ROM, establishes temporary WIN2/WIN3 mappings and a temporary stack, receives a bounded 1..4000h resident image over the legacy DBIT bootstrap byte channel, then jumps to address 0000h.
5. The resident entry maps WIN0 to physical page 00, WIN1 to physical page 03, places the operational stack at 7FFEh, runs the CRC self-test and publishes A2h as the resident-ready acknowledgement.
6. The resident main loop continuously calls `p126_ngs_ipc_dispatch_once`. E0h arms DMA module 1 at physical 108000h; a complete frame is CRC-checked before the resident emits a valid-frame diagnostic.

DBIT/GSDAT is used only for stock-ROM bootstrap compatibility. After A2h, application payloads use ABI 1.0 DMA; NeoGS does not perform direct physical host I/O. ATM startup file reads occur before ATM video initialization to preserve the established TR-DOS paging constraints.

The resident image must fit within one 16 KiB WIN0 page. The 256 KiB kernel allocation remains reserved for future overlays; this startup revision does not claim that the entire allocation is populated. P126BOOT.C is limited to one 256-byte TR-DOS sector.

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
