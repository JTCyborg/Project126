# Project126 — Intel 8086 opcode coverage

This is the progress ledger for the 8086 Real Mode interpreter in Project126.
The reference is `PCem/808x.c`, narrowed to the original 8086 instruction set.
Later 80186/286/386 instructions are not part of the target CPU.

## Progress metric

- Denominator: 256 possible opcode-byte values in the documented original 8086 opcode map, including the 8087 ESC opcode range and undocumented 8086-compatible values where PCem has an execution path.
- Numerator: opcode-byte values with a concrete execution path in the Project126 dispatcher.
- Current numerator: 256.
- **Primary opcode-byte dispatch coverage: 256 / 256 = 100.00%.**
- This is a source-coverage metric, not a claim of full semantic correctness. ModR/M forms, memory addressing, prefixes, flags, interrupt behavior and corner cases are tracked separately and must also be complete before the CPU is called 100%.
- An instruction family is not considered complete merely because one opcode in the family is present.

## Implemented in Project126

| Opcode | Instruction | Source |
|---|---|---|
| 0F | PCem 8086 default unhandled-opcode path (consume as no-op) | `neogs_sub/x86_exec.asm` |
| 60–6F | PCem 8086 conditional-branch aliases | `neogs_sub/x86_exec.asm` |
| 86–87 | XCHG r/m8/16,r8/16 | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| 8F | POP r/m16 (PCem applies the operation for every /n extension) | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| 70–7F | Jcc rel8 (all 16 conditions) | `neogs_sub/x86_exec.asm` |
| 50–57 | PUSH r16 | `neogs_sub/x86_exec.asm` |
| 58–5F | POP r16 | `neogs_sub/x86_exec.asm` |
| 88–8B | MOV r/m8/16 and r8/16 register-memory forms | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| 8C, 8E | MOV segment register to/from r/m16 | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| 8D | LEA r16,m | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| A4–A7 | MOVS/CMPS byte and word string instructions | `neogs_sub/x86_exec.asm` + `x86_alu.asm` |
| AA–AF | STOS/LODS/SCAS byte and word string instructions | `neogs_sub/x86_exec.asm` + `x86_alu.asm` |
| A0–A3 | MOV AL/AX to/from direct data-segment offset (moffs16) | `neogs_sub/x86_exec.asm` |
| A8–A9 | TEST AL/AX, immediate | `neogs_sub/x86_exec.asm` |
| D0–D3 | Group 2 ROL/ROR/RCL/RCR/SHL/SHR/SAR byte/word | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| D4–D6 | AAM, AAD, SALC | `neogs_sub/x86_exec.asm` |
| D8–DF | ESC ModR/M decode; no-8087 operation ignored | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| D7 | XLAT | `neogs_sub/x86_exec.asm` |
| 10–15 | ADC r/m,r and AL/AX, immediate | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 18–1D | SBB r/m,r and AL/AX, immediate | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 08–0D | OR r/m,r and AL/AX, immediate | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 27, 2F | DAA, DAS | `neogs_sub/x86_exec.asm` |
| 37, 3F | AAA, AAS | `neogs_sub/x86_exec.asm` |
| 20–25 | AND r/m,r and AL/AX, immediate | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 30–35 | XOR r/m,r and AL/AX, immediate | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 80–83 | Group 1 immediate ALU: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 84–85 | TEST r/m8/16,r8/16 | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 06–07, 0E, 16–17, 1E–1F | PUSH/POP ES, CS, SS, DS (valid 8086 forms) | `neogs_sub/x86_exec.asm` |
| 26, 2E, 36, 3E | ES/CS/SS/DS segment override prefixes | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| F0–F3 | LOCK/LOCK alias, REPNE, REP/REPE prefix parser | `neogs_sub/x86_exec.asm` |
| 00–05 | ADD r/m,r and AL/AX, immediate | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 28–2D | SUB r/m,r and AL/AX, immediate | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 38–3D | CMP r/m,r and AL/AX, immediate | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| 40–47 | INC r16 | `neogs_sub/x86_exec.asm` |
| 48–4F | DEC r16 | `neogs_sub/x86_exec.asm` |
| 90 | NOP (XCHG AX,AX encoding) | `neogs_sub/x86_exec.asm` |
| 91–97 | XCHG AX,r16 | `neogs_sub/x86_exec.asm` |
| 98–99 | CBW, CWD | `neogs_sub/x86_exec.asm` |
| 9A | CALL FAR ptr16:16 | `neogs_sub/x86_exec.asm` |
| 9B | WAIT (PCem 8086 no-op path) | `neogs_sub/x86_exec.asm` |
| C0–C3 | RET near aliases / RET imm16 | `neogs_sub/x86_exec.asm` |
| CC–CF | INT3, INT imm8, INTO, IRET | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| C4–C5 | LES, LDS far-pointer loads | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| C6–C7 | MOV r/m8/16, immediate (PCem applies the operation for every /n extension) | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| C8–CB | RETF aliases / RETF imm16 | `neogs_sub/x86_exec.asm` |
| 9C–9F | PUSHF, POPF, SAHF, LAHF | `neogs_sub/x86_exec.asm` |
|  B0–B7 | MOV r8,imm8 (AL,CL,DL,BL,AH,CH,DH,BH) | `neogs_sub/x86_exec.asm` |
|  B8–BF | MOV r16,imm16 (AX,CX,DX,BX,SP,BP,SI,DI) | `neogs_sub/x86_exec.asm` |
| E0–E3 | LOOPNE, LOOPE, LOOP, JCXZ | `neogs_sub/x86_exec.asm` |
| E4–E7, EC–EF | IN/OUT immediate-port and DX-port byte/word forms | `neogs_sub/x86_exec.asm` + `x86_io.asm` |
| E8 | CALL rel16 | `neogs_sub/x86_exec.asm` |
| E9 | JMP rel16 | `neogs_sub/x86_exec.asm` |
| EA | JMP ptr16:16 | `neogs_sub/x86_exec.asm` |
| EB | JMP rel8 | `neogs_sub/x86_exec.asm` |
| F6 | Group 3 byte: TEST, NOT, NEG, MUL, IMUL, DIV, IDIV | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| F7 | Group 3 word: TEST, NOT, NEG, MUL, IMUL, DIV, IDIV | `neogs_sub/x86_exec.asm` + `x86_alu.asm` + `x86_modrm.asm` |
| FE–FF | Group 4/5: byte/word INC/DEC, near/far CALL/JMP, PUSH r/m16 | `neogs_sub/x86_exec.asm` + `x86_modrm.asm` |
| F4 | HLT | `neogs_sub/x86_exec.asm` |
| F5 | CMC | `neogs_sub/x86_exec.asm` |
| F8–FD | CLC, STC, CLI, STI, CLD, STD | `neogs_sub/x86_exec.asm` |

C0h is the PCem 8086 near-RET alias; F1h is the PCem LOCK alias; 0Fh follows PCem's default no-op path. The 7 opcodes 98h–9Ah and 9Ch–9Fh are implemented; 9Ah (far immediate CALL) was added in commit `98cb5efe6f5be565fd44533aba11884a20c426c4`. It pushes the post-immediate return IP and old CS to SS:SP through the Project126 memory backend before transferring CS:IP. The 6 opcodes 98h, 99h, 9Ch–9Fh were added in commits `374c661e8bf3adf7390d06032c30a9d8bfc796c2` and `b1665b8a96764f77b9f5b7d6267babebf00c270d`: CBW/CWD, PUSHF/POPF, SAHF/LAHF. Stack flag operations use SS:SP through the Project126 guest-memory interface and follow PCem's 8086 flag masks.
XLAT (`D7`) and flag-control instructions CMC/CLC/STC/CLI/STI/CLD/STD (`F5`, `F8`–`FD`) were added in commit `0e20421bb3c203e85a20a6b5d54fc57d56dbb8dc`. XLAT uses DS:(BX+AL) through the Project126 guest-memory backend; flag-control instructions update CF/IF/DF only. TEST accumulator-immediate (`A8`–`A9`) was added in commits `884ddaaa9abe323d0286e23a006595edd7b3fb72` and `45252944d8b681cd95392e9c08eba151a0c2cdef`; it updates SF/ZF/PF and clears CF/OF/AF without changing the accumulator. LOOPNE/LOOPE/LOOP/JCXZ (`E0`–`E3`) were added in commit `f63ee592a60356254926333b5859bac0d3a3c151`. LOOP variants decrement CX without modifying FLAGS; JCXZ only tests CX. Near CALL `E8` was added in commit `5acb6d3b6d658cf1e1558099b3509bb57b25e6dc`; near RET aliases `C1/C3`, `RET imm16` (`C2`), far RET aliases `C8/C9/CB` and `RETF imm16` (`CA`), plus WAIT (`9B`), were added in commit `e7652be5d5c7d4ac9510aeb277f78f95448f7a9d`. Return instructions restore IP (and CS for far return) from SS:SP and apply immediate stack cleanup where encoded.
The 32 conditional branch opcode bytes 60h–7Fh were added in commits `a7379c6fa55f9c87746bb25670be72b7cdf6aa47` and `f9909dcead0de8ca297a79c16e8c888e05343a34`. Conditions use OF, CF, ZF, SF and PF from the guest FLAGS word; all branches consume the signed displacement even when not taken. The 60h–6Fh aliases follow the PCem 8086 execution path and are not treated as 80186 PUSHA/POPA.
The 16 PUSH/POP register opcodes 50h–5Fh were added in commit `6279ab0c9182574c9782b4bbb1222d777838467d`. Stack accesses use SS:SP via the Project126 guest-memory backend, wrap the 16-bit stack offset, and preserve PCem's original 8086 PUSH SP / POP SP ordering.
The 16 MOV-immediate opcodes were added in commit `28575e385d5d2a66c5ca448e72f7b4e2f01d2391`.
The 4 direct-offset MOV opcodes A0–A3 were added in commit `f8111740994d26d55cbad90391456daf096345c6`; byte/word transfers use the Project126 guest-memory backend and DS as the default segment, with active segment override support.
The 7 XCHG AX,r16 opcodes were added in commit `1a257238d23d31d897137518f6bfe47c5657ef13`.
PUSH/POP segment-register instructions (`06h`, `07h`, `0Eh`, `16h`, `17h`, `1Eh`, `1Fh`) were added in commit `a823db1e33a008fba0467b532a70999b99d8bfaf`; POP SS sets the pending one-instruction interrupt-inhibit latch. DAA/DAS/AAA/AAS (`27h`, `2Fh`, `37h`, `3Fh`) were added in commit `676b8e9330c41bbbc6802825c7941cfa39498b86`, following the PCem 8086 adjustment rules for AF/CF and SZP handling.
F6 Group 3 byte MUL/IMUL/DIV/IDIV extensions /4–/7 were added in commits `1d8ec38f0b2cd718f676307038f529686b98e77d`, `af57b8fc42c488abb62f8fb3595630fbcc04d7ff` and `082df6cdc7712d94c756d90cee5017db7259f162`. The byte divide helpers follow PCem's 8086 behavior: divide-by-zero enters vector 0; quotient is truncated to AL and remainder stored in AH. F7 word MUL/IMUL/DIV/IDIV /4–/7 were added in commits `5129127ff36913c344ffab5817fccefbdfdd5aa8` and `6ed4246737024ab41058591a3ce625c7e6e76b71`. The 16x16 multiply and 32/16 restoring divide paths preserve the PCem 8086 quotient truncation behavior; divide-by-zero enters vector 0. Group 3 /0–/7 is now covered for both F6 byte and F7 word forms.
FE/FF Group 4/5 support was added in commits `5c233c9c56feeab5d15968fcbd27395012f41678` and `5f600de347b07ec1229d53bf6b6e8d71455be7f4`: FE /0 byte INC and /1-/7 byte DEC (PCem treats any nonzero extension as DEC); FF /0-/1 word INC/DEC, /2 near CALL, /3 far memory CALL, /4 near JMP, /5 far memory JMP, /6 PUSH r/m16; /7 consumes ModR/M and does nothing as in PCem. INC/DEC preserve CF; far pointer forms require memory operands.
Group 1 immediate opcodes `80h`–`83h` were added in commits `dcc8af7fe1a5b73b9e40194eed658802d9ff0952` and `35e8ae8d1e5c91e710cdedf8d3fd08ba27d19a46`. The /0–/7 extension field selects ADD/OR/ADC/SBB/AND/SUB/XOR/CMP; 83h sign-extends its byte immediate to 16 bits. ADC (`10h`–`15h`) and SBB (`18h`–`1Dh`) register/memory and accumulator-immediate forms were added in commits `e77b5e31087e6788953463acde4c2f4042254930`, `74927444438a57edc7d2a27fa09235278db9e31e` and `d8fd9af6bae2b70887404d38871e0a39465e2e22`. They capture guest CF as carry/borrow input and propagate it across both bytes for word operations. OR (`08h`–`0Dh`), AND (`20h`–`25h`), XOR (`30h`–`35h`) and TEST (`84h`–`85h`) were added in commits `12c177661869d3d463f141afa32c55287759a7b2`, `8e06a7f2a163ddbf8373e446689250a119a6ba06` and `02819be2c824700714656cf5b02a59f149edde9f`. Logical operations update SF/ZF/PF and clear CF/AF/OF; TEST does not write its destination. ADD (`00h`–`05h`), SUB (`28h`–`2Dh`) and CMP (`38h`–`3Dh`) register/memory and accumulator-immediate forms were added in commits `8861c3c510e0792d9187f13ef9867b8b9c3ed9f3` and `413d98ac389b7ad25c3911ba8e7643e6ef4ac365`. They use the existing 8/16-bit ALU routines and ModR/M operand helpers; CMP updates flags without writing the destination.
The 16 register INC/DEC opcodes were added in commits `75a3e69da4549ffe2f2346b86cac5d8263a61ca4` and `e4dfd3b34d26c778e4a8029484ad67b76c560e83`. INC/DEC use the existing 16-bit ALU flag engine and explicitly preserve CF.

## Decoder foundation

AAM/AAD (`D4h`/`D5h`) and undocumented SALC (`D6h`) were added in commits `4aa0a0f00c18897c388126fff512b0d1e9e61793` and `21a49ef2278fa98ac62274e5dd0d24ae4a92ebf1`. AAM base zero routes through divide-error vector 0. ESC (`D8h`–`DFh`) decodes ModR/M/displacement and performs no coprocessor action because Project126 has no 8087.
IN/OUT opcodes E4h–E7h and ECh–EFh were added in commits `4c42f31171d5227d46aac919ced64d390c604477`, `82c8bdd429796fab4b8326b5be27fb873fdabda7` and `5191f19be7ba4bd13b88bd7c16d50de87ced4b40`. They route only through the software virtual I/O backend: port 00E0h is a deterministic test latch and unmapped reads return FFh/FFFFh; no physical NeoGS IN/OUT is issued. External device bridging through DMA/IPC remains pending.
Group 2 shift/rotate opcodes D0h–D3h were added in commits `c3908954816b2cecea231c97ed79e5c19e2ac19f` and `27abfc5b6df962c34880658765d283764f690e39`. The implementation uses unmasked 8086 CL counts, preserves flags for zero count, and applies per-operation CF/OF/SZP/AF updates. Software interrupt instructions INT3/INT/INTO and IRET (`CCh`–`CFh`) were added in commit `d614503ad5e6cff3d15c957416a1036cabeb2ad8`. Interrupt entry pushes FLAGS|F000, CS and post-instruction IP, clears IF/TF, then loads IP:CS from the guest IVT; IRET restores IP, CS and the 8086 FLAGS image. Asynchronous NMI and maskable IRQ boundary checks are now present: NMI uses vector 2; IRQ requires IF and uses `x86_irq_vector` (reset default 8); HLT is released by accepted interrupts. MOV SS and POP SS arm the one-boundary `noint` inhibit latch; STI sets IF but does not arm `noint` in PCem's 8086 core. The CPU boundary now snapshots TF before instruction/prefix fetch and, at the following boundary, raises vector 1 only when TF was set before the instruction and remains set afterward; the boundary order is TF trap, then NMI, then maskable IRQ, matching PCem. The `noint` latch suppresses TF and maskable IRQ but does not mask NMI. This source-level implementation has not yet passed assembler/link or functional verification. The host/IPC event producer that sets pending IRQ/NMI and supplies the PIC vector is not yet connected.

String opcodes A4h–A7h and AAh–AFh are implemented with SI/DI updates controlled by DF, ES-fixed destinations, and DS/segment-override sources. REP/REPE/REPNE loops decrement CX and apply ZF termination for CMPS/SCAS. The interpreter yields after each repeated iteration, restores IP to the first prefix byte when repetition continues, and checks the normal IRQ/NMI boundary before the next iteration. REPE/REPNE initialize ZF as PCem does, including the CX=0 case.

The 8Eh MOV Sreg,r/m16 handler accepts the CS selector (/1), matching PCem's original 8086 path; this encoding differs from later x86 profiles. Reserved /4-/7 selectors are ignored as in PCem. The 8Ch handler likewise ignores /4-/7. PCem's 8Eh path arms its one-instruction maskable-IRQ inhibit latch for every selector, including ignored /4-/7; the 8Ch store form does not. All x86_exec call sites for ModR/M r/m byte/word reads now immediately propagate carry on guest-memory faults; write-helper call sites and direct guest-memory accesses were source-audited for the same behavior.

The instruction entry now consumes segment override (`26h`, `2Eh`, `36h`, `3Eh`), LOCK/LOCK alias (`F0h`/`F1h`) and REPNE/REP (`F2h`/`F3h`) prefixes before dispatch. Segment overrides are applied to ModR/M effective addresses and direct-offset/XLAT data accesses. REP state is recorded for string execution; LOCK state is recorded, with no external bus-lock side effect in the single-guest-CPU model. REP string execution is still pending.

`neogs_sub/x86_modrm.asm` is linked into the resident image. It fetches ModR/M and displacement bytes through the Project126 CS:IP fetch path, decodes the 8086 BX/BP/SI/DI effective-address forms, applies signed disp8 or disp16, and selects DS versus SS for BP-based addressing. It now also provides byte/word register and r/m operand accessors, including AH/CH/DH/BH mapping and guest-memory access through the Project126 mapper. MOV 88h–8Bh, MOV segment-register 8Ch/8Eh, XCHG 86h–87h, POP 8Fh, LEA 8Dh, LES/LDS C4h/C5h and MOV-immediate C6h/C7h use these helpers. These are supported ModR/M forms; all remaining EA and invalid-extension edge cases still require source-level review. XCHG memory/register forms preserve FLAGS; POP r/m16 resolves the destination EA before applying the stack increment. MOV SS arms `x86_irq_inhibit`; the interrupt-boundary dispatcher that consumes this one-instruction inhibit is still pending. LES/LDS require memory operands and load the offset word followed by the segment word.

## Remaining semantic and integration work

The primary opcode-byte dispatcher now has an explicit path for every byte value. This **does not mean the CPU core is complete**. The remaining work is semantic, integration and corner-case validation:

- Complete source-by-source review of all PCem 8086 instruction forms, ModR/M subfunctions, invalid encodings and undocumented behavior; the byte-slot matrix alone cannot prove every form correct.
- Connect host/IPC event production to `x86_pending_irq`, `x86_pending_nmi` and `x86_irq_vector`; the CPU-side NMI/IRQ boundary logic exists, but the PIC/host producer is not wired.
- Connect external virtual I/O devices to DMA/IPC. The current software I/O backend only provides the deterministic E0h test latch and open-bus behavior; it never issues physical NeoGS IN/OUT.
- Add interrupt servicing between REP string iterations. Current REP/REPE/REPNE loops complete within one interpreter step.
- Verify the new TF single-step/trap implementation against PCem, including TF changes by POPF/IRET, INT entry, TF-versus-NMI priority, HLT and the one-boundary `noint` shadow; complete remaining NMI/IRQ/HLT edge cases.
- Review exact undefined/reserved FLAGS behavior and all arithmetic/shift/decimal-adjust flag corner cases against PCem, including POPF/IRET restrictions.
- Review 20-bit wrap, segment-offset wrap, memory faults and all ModR/M default-segment/override corner cases.
- Define remaining LOCK behavior and external bus serialization if the virtual machine later models concurrent bus masters. In the current single-guest-CPU model the prefix is parsed and recorded.
- 8087 is not present: ESC instructions consume ModR/M/displacement but perform no coprocessor operation.
- Confirm PCem's default invalid-opcode behavior for every unsupported encoding and preserve the 8086-only profile (no 80186+ extensions).

**No CPU functional tests, BIOS POST or guest program execution have been run.** The resident loop also gates automatic execution after BIOS image installation and only logs that the image is ready; the reset-vector probe routine remains dormant. Only compile/package CI is permitted until the semantic and integration work above is complete and explicitly reviewed.

## Architectural constraints

- CPU profile is Intel 8086 Real Mode only, 20-bit physical address with 1 MiB wrap.
- Guest memory must go through Project126's `x86_guest_mem_read8/write8` backend and custom machine map.
- External devices are not accessed directly by NeoGS. Guest I/O is virtualized; any host service is routed through Project126 DMA/IPC.
- Project125's Z80 implementation is a reference for reusable instruction semantics, not a drop-in memory or device backend.
- **No CPU functional tests or BIOS execution are to be started until the complete 8086 implementation is ported and the coverage ledger reaches 100%.** Assembly-only checks may be used to catch syntax/link/size errors; they are not CPU tests.
