#!/usr/bin/env python3
"""Fail closed unless WORLDLINE exposes the protocol GWCU relies on."""
from __future__ import annotations

import json
import sys
from pathlib import Path

PROTOCOL = 1
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
        or features.get("protocol") != PROTOCOL
        or REQUIRED not in (ops or [])
    ):
        print(
            f"WORLDLINE does not satisfy protocol {PROTOCOL} + {REQUIRED}: "
            f"{json.dumps(features)[:512]}",
            file=sys.stderr,
        )
        return 1
    print(
        "WORLDLINE",
        features.get("version", "unknown"),
        features.get("protocol"),
        features.get("domain_id"),
        features.get("receipt_schema"),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
