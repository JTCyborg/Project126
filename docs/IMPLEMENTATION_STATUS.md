# Project126 implementation status

This document records actual artifacts and their verification state; it is not a projection of the roadmap.

## Build pipeline foundation

- Assembler: repository-pinned `tools/sjasmplus.exe`.
- Translation unit: `neogs_sub/x86_cpu_state_assemble.asm`.
- CI: `.github/workflows/neogs-assembly.yml`.
- The translation unit assembles the architectural-state module only. It is deliberately not a runtime image: no NeoGS load address, startup entrypoint, stack placement or memory-bank mapping has been assumed.
- CI checks assembler exit status and the independent 256 KiB NeoGS firmware size ceiling, then publishes the assembled binary and symbol table.
- Status: workflow committed; first GitHub Actions result pending. Do not mark BUILD PASS until the run completes successfully.

## PCem reference integrity tooling

- `docs/PCEM_REFERENCE_MAP.md`
- `tools/verify_pcem_reference.py`
- Status: committed. The verifier has not yet been executed in a local checkout.
- Purpose: pin the CPU, memory, I/O, interrupt, timer, keyboard and VGA reference files by Git blob identity.

## x86 CPU architectural state foundation

- Source: `neogs_sub/x86_cpu_state.asm`
- Assembly unit: `neogs_sub/x86_cpu_state_assemble.asm`
- Runtime version emitter: `x86_cpu_emit_version`, string `[P126 X86_CPU_STATE v0.1.0]` (startup call is not wired yet because the Project126 firmware entry point does not exist).
- PCem comparison points: `PCem/808x.c:resetx86()`, `PCem/cpu.h:CPU_8086`.
- Implemented in source: deterministic register reset, 8086 reset vector FFFF:0000, FLAGS=0002h, 20-bit segment:offset physical-address calculation and target-side self-test vectors.
- Status: source committed; address test vectors independently checked against 20-bit arithmetic; not yet assembled or executed on NeoGS. The new CI workflow is intended to establish the assembly result.
- Not implemented by this module: instruction decoding/execution, memory-region mapping, interrupt delivery, timing or device models.

## Verification policy

A committed source file is not automatically a successful build or runtime test. Record source review, build result, emulator/target result and hardware result separately. Do not promote the CPU-state component to BUILD PASS until the Project126 build assembles it, or to HARDWARE PASS until its self-test runs on the target NeoGS.
