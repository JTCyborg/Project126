# Project126 — Intel 8086 opcode coverage

This is the progress ledger for the 8086 Real Mode interpreter in Project126.
The reference is `PCem/808x.c`, narrowed to the original 8086 instruction set.
Later 80186/286/386 instructions are not part of the target CPU.

## Progress metric

- Denominator: 256 possible opcode-byte values in the documented original 8086 opcode map, including the 8087 ESC opcode range and undocumented 8086-compatible values where PCem has an execution path.
- Numerator: opcode-byte values with a concrete execution path in the Project126 dispatcher.
- Current numerator: 116.
- **Opcode-byte dispatch coverage: 116 / 256 = 45.31%.**
- This is a source-coverage metric, not a claim of full semantic correctness. ModR/M forms, memory addressing, prefixes, flags, interrupt behavior and corner cases are tracked separately and must also be complete before the CPU is called 100%.
- An instruction family is not considered complete merely because one opcode in the family is present.

## Implemented in Project126

| Opcode | Instruction | Source |
|---|---|---|
| 60–6F | PCem 8086 conditional-branch aliases | `neogs_sub/x86_exec.asm` |
| 70–7F | Jcc rel8 (all 16 conditions) | `neogs_sub/x86_exec.asm` |
| 50–57 | PUSH r16 | `neogs_sub/x86_exec.asm` |
| 58–5F | POP r16 | `neogs_sub/x86_exec.asm` |
| A0–A3 | MOV AL/AX to/from direct DS offset (moffs16) | `neogs_sub/x86_exec.asm` |
| 40–47 | INC r16 | `neogs_sub/x86_exec.asm` |
| 48–4F | DEC r16 | `neogs_sub/x86_exec.asm` |
| 90 | NOP (XCHG AX,AX encoding) | `neogs_sub/x86_exec.asm` |
| 91–97 | XCHG AX,r16 | `neogs_sub/x86_exec.asm` |
| 98–99 | CBW, CWD | `neogs_sub/x86_exec.asm` |
| 9A | CALL FAR ptr16:16 | `neogs_sub/x86_exec.asm` |
| 9B | WAIT (PCem 8086 no-op path) | `neogs_sub/x86_exec.asm` |
| C1–C3 | RET near aliases / RET imm16 | `neogs_sub/x86_exec.asm` |
| C8–CB | RETF aliases / RETF imm16 | `neogs_sub/x86_exec.asm` |
| 9C–9F | PUSHF, POPF, SAHF, LAHF | `neogs_sub/x86_exec.asm` |
|  B0–B7 | MOV r8,imm8 (AL,CL,DL,BL,AH,CH,DH,BH) | `neogs_sub/x86_exec.asm` |
|  B8–BF | MOV r16,imm16 (AX,CX,DX,BX,SP,BP,SI,DI) | `neogs_sub/x86_exec.asm` |
| E0–E3 | LOOPNE, LOOPE, LOOP, JCXZ | `neogs_sub/x86_exec.asm` |
| E8 | CALL rel16 | `neogs_sub/x86_exec.asm` |
| E9 | JMP rel16 | `neogs_sub/x86_exec.asm` |
| EA | JMP ptr16:16 | `neogs_sub/x86_exec.asm` |
| EB | JMP rel8 | `neogs_sub/x86_exec.asm` |
| F4 | HLT | `neogs_sub/x86_exec.asm` |

The 7 opcodes 98h–9Ah and 9Ch–9Fh are implemented; 9Ah (far immediate CALL) was added in commit `98cb5efe6f5be565fd44533aba11884a20c426c4`. It pushes the post-immediate return IP and old CS to SS:SP through the Project126 memory backend before transferring CS:IP. The 6 opcodes 98h, 99h, 9Ch–9Fh were added in commits `374c661e8bf3adf7390d06032c30a9d8bfc796c2` and `b1665b8a96764f77b9f5b7d6267babebf00c270d`: CBW/CWD, PUSHF/POPF, SAHF/LAHF. Stack flag operations use SS:SP through the Project126 guest-memory interface and follow PCem's 8086 flag masks.
LOOPNE/LOOPE/LOOP/JCXZ (`E0`–`E3`) were added in commit `f63ee592a60356254926333b5859bac0d3a3c151`. LOOP variants decrement CX without modifying FLAGS; JCXZ only tests CX. Near CALL `E8` was added in commit `5acb6d3b6d658cf1e1558099b3509bb57b25e6dc`; near RET aliases `C1/C3`, `RET imm16` (`C2`), far RET aliases `C8/C9/CB` and `RETF imm16` (`CA`), plus WAIT (`9B`), were added in commit `e7652be5d5c7d4ac9510aeb277f78f95448f7a9d`. Return instructions restore IP (and CS for far return) from SS:SP and apply immediate stack cleanup where encoded.
The 32 conditional branch opcode bytes 60h–7Fh were added in commits `a7379c6fa55f9c87746bb25670be72b7cdf6aa47` and `f9909dcead0de8ca297a79c16e8c888e05343a34`. Conditions use OF, CF, ZF, SF and PF from the guest FLAGS word; all branches consume the signed displacement even when not taken. The 60h–6Fh aliases follow the PCem 8086 execution path and are not treated as 80186 PUSHA/POPA.
The 16 PUSH/POP register opcodes 50h–5Fh were added in commit `6279ab0c9182574c9782b4bbb1222d777838467d`. Stack accesses use SS:SP via the Project126 guest-memory backend, wrap the 16-bit stack offset, and preserve PCem's original 8086 PUSH SP / POP SP ordering.
The 16 MOV-immediate opcodes were added in commit `28575e385d5d2a66c5ca448e72f7b4e2f01d2391`.
The 4 direct-offset MOV opcodes A0–A3 were added in commit `f8111740994d26d55cbad90391456daf096345c6`; byte/word transfers use the Project126 guest-memory backend and DS as the default segment (segment overrides are pending).
The 7 XCHG AX,r16 opcodes were added in commit `1a257238d23d31d897137518f6bfe47c5657ef13`.
The 16 register INC/DEC opcodes were added in commits `75a3e69da4549ffe2f2346b86cac5d8263a61ca4` and `e4dfd3b34d26c778e4a8029484ad67b76c560e83`. INC/DEC use the existing 16-bit ALU flag engine and explicitly preserve CF.

## Not yet implemented

All other original 8086 opcode families remain open, including:
- arithmetic/logical operations and full 8086 flag behavior;
- register and memory INC/DEC, shifts/rotates, multiply/divide;
- all ModR/M operand forms and 8086 effective-address calculations;
- register/memory/immediate MOV, segment-register operations, LEA, LES/LDS, XCHG;
- remaining stack operations, PUSHF/POPF, LAHF/SAHF, CBW/CWD;
- remaining near/far CALL/RET/JMP variants;
- software interrupts, INTO, IRET and interrupt frame semantics;
- string instructions and REP/REPE/REPNE;
- IN/OUT as virtual guest ports, with no physical NeoGS device I/O;
- segment/LOCK/REP prefixes, XLAT, WAIT and ESC/8087 handling;
- invalid-opcode behavior and all documented 8086 corner cases.

## Architectural constraints

- CPU profile is Intel 8086 Real Mode only, 20-bit physical address with 1 MiB wrap.
- Guest memory must go through Project126's `x86_guest_mem_read8/write8` backend and custom machine map.
- External devices are not accessed directly by NeoGS. Guest I/O is virtualized; any host service is routed through Project126 DMA/IPC.
- Project125's Z80 implementation is a reference for reusable instruction semantics, not a drop-in memory or device backend.
- **No CPU functional tests or BIOS execution are to be started until the complete 8086 implementation is ported and the coverage ledger reaches 100%.** Assembly-only checks may be used to catch syntax/link/size errors; they are not CPU tests.
