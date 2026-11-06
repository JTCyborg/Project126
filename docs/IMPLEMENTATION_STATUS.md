# Project126 implementation status

This document records actual artifacts and their verification state; it is not a projection of the roadmap.

## Build pipeline and address-placement audit

- Assembler: repository-pinned `tools/sjasmplus.exe` (SjASMPlus 1.23.1).
- Local build entry point: `tools/build_project126.ps1`.
- CI: `.github/workflows/neogs-assembly.yml`; CI invokes the same PowerShell build script as a local build.
- Every successful assembly must produce:
  - `build/x86_cpu_state.bin` — assembled image;
  - `build/NEOGS.lst` — SjASMPlus source listing with addresses/opcodes;
  - `build/NEOGS.map` — sorted symbol/address map.
- The script deletes old outputs before assembling and fails if any of the three products is missing. This prevents stale listing/map files from being mistaken for the current build.
- Assembly translation unit: `neogs_sub/x86_cpu_state_assemble.asm`, version v0.5.0. It exports explicit start/end labels for the CPU-state and ALU modules and displays each module's start, end and size, plus the complete image end and size.
- Assembly-time assertions enforce non-empty modules, contiguous placement (ALU begins exactly at CPU-state end), and total image size no greater than 256 KiB.
- **Address-space qualification:** these are offsets in the current ORG 0000h assembly image. They are not a claim about the final physical NeoGS RAM bank/load address; that runtime memory map has not yet been fixed.
- CI publishes the binary, listing and map together as one artifact.

## Last verified assembly before listing/map integration

- GitHub Actions run `42273068373`, commit `0e53ce36bb4a6a4052aac8e3886f62546861b52b`: SjASMPlus 1.23.1, 674 source lines, 0 errors, 0 warnings, 1155-byte output, size limit passed.
- The listing/map build changes are newer and require their own CI pass. Do not treat the previous result as verification of the new build script.

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
- Status: source assembled successfully in CI run `42273068373`; target-side self-test has not been executed on NeoGS.
- Not implemented by this module: instruction decoding/execution, memory-region mapping, interrupt delivery, timing or device models.

## x86 ALU foundation

- Source: `neogs_sub/x86_alu.asm`, version `P126 / X86_ALU v0.2.0`.
- PCem comparison points: `PCem/808x.c:setadd8()`, `setsub8()` and adjacent flag helpers.
- Implemented in source: 8-bit and 16-bit ADD/SUB; CF, PF, AF, ZF, SF and OF translation into guest FLAGS; preservation of non-arithmetic flags. A runtime version emitter reports the ALU component on NeoGS #EF.
- Included target-side regression vectors: 8-bit and 16-bit signed overflow, carry/borrow, auxiliary carry/borrow, zero, sign, parity and preservation of TF/IF/DF.
- Status: assembled successfully in CI run `42273068373`; target-side regression vectors have not yet been executed on NeoGS.

## Verification policy

A committed source file is not automatically a successful runtime or hardware test. Keep assembly, emulator, NeoGS runtime and ATM hardware results separate. The current CPU-state and ALU modules have BUILD PASS only; they do not yet constitute an executable x86 CPU.
