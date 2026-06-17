#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


AMXD_HEADER = b"ampf\x04\x00\x00\x00aaaa"
AMXD_META_CHUNK = b"meta" + struct.pack("<I", 4) + struct.pack("<I", 1)
DEFAULT_PATCHER_FIELDS = {
    "openrect": [0.0, 0.0, 0.0, 169.0],
    "latency": 0,
    "is_mpe": 0,
    "external_mpe_tuning_enabled": 0,
    "minimum_live_version": "",
    "minimum_max_version": "",
    "platform_compatibility": 0,
    "saved_attribute_attributes": {"default_plcolor": {"expression": ""}},
}


def load_patch(path: Path) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    patcher = document.get("patcher")
    if not isinstance(patcher, dict):
        raise ValueError(f"{path} does not contain a top-level 'patcher' object")
    for key, value in DEFAULT_PATCHER_FIELDS.items():
        patcher.setdefault(key, value)
    return document


def build_amxd_bytes(document: dict) -> bytes:
    payload = json.dumps(document, indent=1, ensure_ascii=False).encode("utf-8")
    ptch_chunk = b"ptch" + struct.pack("<I", len(payload) + 1) + payload + b"\x00"
    return AMXD_HEADER + AMXD_META_CHUNK + ptch_chunk


def main() -> int:
    parser = argparse.ArgumentParser(description="Pack a Max patch as a Max for Live .amxd device")
    parser.add_argument("input", type=Path, help="Source .maxpat file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output .amxd file (defaults to input basename with .amxd extension)",
    )
    args = parser.parse_args()

    input_path = args.input.resolve()
    if input_path.suffix.lower() != ".maxpat":
        raise SystemExit("Input file must be a .maxpat patch")

    output_path = (args.output or input_path.with_suffix(".amxd")).resolve()
    document = load_patch(input_path)
    output_path.write_bytes(build_amxd_bytes(document))
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
