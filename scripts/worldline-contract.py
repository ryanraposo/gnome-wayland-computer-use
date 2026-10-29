#!/usr/bin/env python3
"""Refuse a WORLDLINE that cannot serve the op GWCU acts on.

Reads the JSON printed by `worldline.py request --json '{"op":"features"}'`.
A daemon that answers discovery but has no `receipt` op would let install
succeed and fail only mid-action, so both install and doctor fail closed here.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REQUIRED = "receipt"


def main() -> int:
    try:
        features = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    except (IndexError, OSError, ValueError) as exc:
        print(f"WORLDLINE features unreadable: {exc}", file=sys.stderr)
        return 1
    ops = features.get("ops") if isinstance(features, dict) else None
    if (
        not isinstance(features, dict)
        or not features.get("ok")
        or REQUIRED not in (ops or [])
    ):
        print(
            f"WORLDLINE does not advertise {REQUIRED}: {json.dumps(features)[:512]}",
            file=sys.stderr,
        )
        return 1
    print(
        "WORLDLINE",
        features.get("protocol"),
        features.get("domain_id"),
        features.get("receipt_schema"),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
