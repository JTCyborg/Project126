# Project126 implementation status

This document records actual artifacts and their verification state; it is not a projection of the roadmap.

## Build pipeline foundation

- Assembler: repository-pinned `tools/sjasmplus.exe` (SjASMPlus 1.23.1).
- Translation unit: `neogs_sub/x86_cpu_state_assemble.asm` (unit version v0.4.0); it assembles the architectural-state and ALU modules.
- CI: `.github/workflows/neogs-assembly.yml`.
- CI checks assembler exit status and the independent 256 KiB NeoGS firmware size ceiling, then publishes the assembled binary and symbol table.
- Status: **BUILD PASS** for current build commit `0e53ce36bb4a6a4052aac8e3886f62546861b52b`; GitHub Actions run `42273068373` completed successfully: SjASMPlus 1.23.1, 674 source lines, 0 assembler errors, 0 warnings, 1155-byte output, and the 256 KiB size check passed.
- This is an assembly pass only. The translation unit is not a runtime image and defines no NeoGS load address, startup entrypoint, stack placement or memory-bank mapping. No NeoGS runtime or hardware pass is claimed.

## PCem reference integrity tooling

- `docs/PCEM_REFERENCE_MAP.md`
- `tools/verify_pcem_reference.py`
- Status: committed. The verifier has not yet been executed in a local checkout.
- Purpose: pin the CPU, memory, I/O, interrupt, timer, keyboard and VGA reference files by Git blob identity.

## x86 CPU architectural state foundation

- Source: `neogs_sub/x86_cpu_state.asm`
- Assembly unit: `neogs_sub/x86_cpu_state_assemble.asm`
- Runtime version emitter: `x86_cpu_emit_version`, string `[P126 X86_CPU_STATE v0.1.0]`. Startup call is not wired because the Project126 firmware entry point and NeoGS memory map are not yet defined.
- PCem comparison points: `PCem/808x.c:resetx86()`, `PCem/cpu.h:CPU_8086`.
- Implemented in source: deterministic register reset, 8086 reset vector FFFF:0000, FLAGS=0002h, 20-bit segment:offset physical-address calculation and target-side self-test vectors.
- Status: source successfully assembled in CI run `42272784210`; address test vectors independently checked against 20-bit arithmetic. The target-side self-test has not been executed on NeoGS.
- Not implemented by this module: instruction decoding/execution, memory-region mapping, interrupt delivery, timing or device models.

## x86 ALU foundation

- Source: `neogs_sub/x86_alu.asm`, version `P126 / X86_ALU v0.2.0`.
- PCem comparison points: `PCem/808x.c:setadd8()`, `setsub8()` and adjacent flag helpers.
- Implemented in source: 8-bit and 16-bit ADD/SUB; CF, PF, AF, ZF, SF and OF translation into guest FLAGS; preservation of non-arithmetic flags. A runtime version emitter reports the ALU component on NeoGS #EF.
- Included target-side regression vectors: 8-bit and 16-bit signed overflow, carry/borrow, auxiliary carry/borrow, zero, sign, parity and preservation of TF/IF/DF.
- Status: assembled successfully in CI run `42272784210`; regression vectors are present in source but have not yet been executed on NeoGS. An independent arithmetic-equation cross-check covered 65,536 operand combinations for each 8-bit operation and 200,000 randomized operand pairs for each 16-bit operation; this does not substitute for executing the assembled routines.

## Verification policy

A committed source file is not automatically a successful runtime or hardware test. Keep assembly, emulator, NeoGS runtime and ATM hardware results separate. The current CPU-state and ALU modules have BUILD PASS only; they do not yet constitute an executable x86 CPU.
