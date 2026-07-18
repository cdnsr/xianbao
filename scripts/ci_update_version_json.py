#!/usr/bin/env python3
"""Update publish/version.json for client update checks (CI)."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def main() -> int:
    version = (os.environ.get("VERSION_NAME") or "").strip()
    desc = os.environ.get("VERSION_DESC") or ""
    if not version:
        print("VERSION_NAME is required", file=sys.stderr)
        return 1

    path = Path("publish/version.json")
    old: dict = {}
    if path.exists():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                old = loaded
        except Exception as exc:  # noqa: BLE001
            print(f"warn: could not parse existing version.json: {exc}", file=sys.stderr)

    history: list = []
    if isinstance(old.get("history"), list):
        history = list(old["history"])

    prev_ver = str(old.get("version") or "").strip()
    if prev_ver:
        history.insert(0, {"version": prev_ver, "desc": str(old.get("desc") or "")})

    seen: set[str] = set()
    deduped: list[dict] = []
    for item in history:
        if not isinstance(item, dict):
            continue
        ver = str(item.get("version") or "").strip()
        if not ver or ver in seen:
            continue
        seen.add(ver)
        deduped.append({"version": ver, "desc": str(item.get("desc") or "")})
    history = deduped[:20]

    data = {
        "version": version,
        "desc": desc,
        "history": history,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {path} -> {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())