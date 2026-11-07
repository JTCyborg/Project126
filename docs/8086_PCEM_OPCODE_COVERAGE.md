# Project126 — Intel 8086 opcode coverage

This is the progress ledger for the 8086 Real Mode interpreter in Project126.
The reference is `PCem/808x.c`, narrowed to the original 8086 instruction set.
Later 80186/286/386 instructions are not part of the target CPU.

## Progress metric

- Denominator: 236 distinct opcode-byte values in the documented original 8086 opcode map, including the 8087 ESC opcode range and undocumented 8086-compatible values where PCem has an execution path.
- Numerator: opcode-byte values with a concrete execution path in the Project126 dispatcher.
- Current numerator: 21.
- **Opcode-byte dispatch coverage: 21 / 236 = 8.90%.**
- This is a source-coverage metric, not a claim of full semantic correctness. ModR/M forms, memory addressing, prefixes, flags, interrupt behavior and corner cases are tracked separately and must also be complete before the CPU is called 100%.
- An instruction family is not considered complete merely because one opcode in the family is present.

## Implemented in Project126

| Opcode | Instruction | Source |
|---|---|---|
| 90 | NOP (XCHG AX,AX encoding) | `neogs_sub/x86_exec.asm` |
|  B0–B7 | MOV r8,imm8 (AL,CL,DL,BL,AH,CH,DH,BH) | `neogs_sub/x86_exec.asm` |
|  B8–BF | MOV r16,imm16 (AX,CX,DX,BX,SP,BP,SI,DI) | `neogs_sub/x86_exec.asm` |
| E9 | JMP rel16 | `neogs_sub/x86_exec.asm` |
| EA | JMP ptr16:16 | `neogs_sub/x86_exec.asm` |
| EB | JMP rel8 | `neogs_sub/x86_exec.asm` |
| F4 | HLT | `neogs_sub/x86_exec.asm` |

The 16 MOV-immediate opcodes were added in commit `28575e385d5d2a66c5ca448e72f7b4e2f01d2391`.

## Not yet implemented

All other original 8086 opcode families remain open, including:
- arithmetic/logical operations and full 8086 flag behavior;
- register and memory INC/DEC, shifts/rotates, multiply/divide;
- all ModR/M operand forms and 8086 effective-address calculations;
- register/memory/immediate MOV, segment-register operations, LEA, LES/LDS, XCHG;
- stack operations, PUSHF/POPF, LAHF/SAHF, CBW/CWD;
- conditional branches, LOOP family, near/far CALL/RET/JMP variants;
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
