#!/usr/bin/env python3
"""Verify the pinned PCem reference snapshot used by Project126.

Version: P126-PCEM-REFERENCE-AUDIT-1.0.0
The verifier uses Git's blob SHA-1 object format, not a plain file SHA-1.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

TOOL_VERSION = "P126-PCEM-REFERENCE-AUDIT-1.0.0"
REFERENCE_TREE = "6e2021e66d6be53f6cadf168f56da2062e91455a"

# Git blob object IDs captured from the Project126/main reference tree.
EXPECTED_BLOBS = {
    "PCem/808x.c": "ec3bba9577cb388f6b346c43e5c5146c79a74a58",
    "PCem/x86_ops.h": "67f6fb927faa3e88844b68195e4f579439403c21",
    "PCem/cpu.h": "d4bea605fbac7f8559dc7444c2261ab531e2b0f4",
    "PCem/mem.c": "66eb41adc60ae5537f7db4394a5253218bcabf50",
    "PCem/io.c": "238e93d6fab0715e23261836447b789b819183de",
    "PCem/pic.c": "9cb9d92faeed327366d30e610ab7b98334280770",
    "PCem/timer.c": "565e51daadc80b25759dc0a52724a5122715d45c",
    "PCem/keyboard.c": "7c2c63c792feaa2cc0aa8a2f33f9e1a332afc873",
    "PCem/vid_vga.c": "5887132370284f3c1a21499db82a0bc53d329907",
    "PCem/vid_vga.h": "329195b8d97195042aa8684ed5ab97734316bfcc",
    "PCem/vid_svga.c": "c0bb1337ae4b47c537f208e454bba6d54625f155",
    "PCem/vid_svga.h": "d592bbd6e7510f323f41679db11756cdc27b7086",
    "PCem/vid_svga_render.c": "d30ef9b8e18455f12b18bea629c81ae8e0f29c70",
    "PCem/vid_cga.c": "09ee4b333d3c8a8cffd82ce4bc03fd26260d1dfb",
    "PCem/vid_ega.c": "9408be51f4fd0f13e2fef71841fa3b02253c1300",
}


def git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Project126 repository root (defaults to the parent of tools/)",
    )
    args = parser.parse_args()
    root = args.root.resolve()

    print(f"[VERSION] {TOOL_VERSION}")
    print(f"[PCEM_REFERENCE_TREE] {REFERENCE_TREE}")
    print(f"[PROJECT_ROOT] {root}")

    failures = 0
    for relative_path, expected_sha in EXPECTED_BLOBS.items():
        path = root / relative_path
        if not path.is_file():
            print(f"[PCEM REF MISSING] {relative_path}")
            failures += 1
            continue

        actual_sha = git_blob_sha1(path.read_bytes())
        if actual_sha != expected_sha:
            print(
                f"[PCEM REF MISMATCH] {relative_path} "
                f"expected={expected_sha} actual={actual_sha}"
            )
            failures += 1
        else:
            print(f"[PCEM REF OK] {relative_path} blob={actual_sha}")

    if failures:
        print(f"[PCEM REF FAIL] mismatches_or_missing={failures}")
        return 1

    print(f"[PCEM REF PASS] files={len(EXPECTED_BLOBS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
