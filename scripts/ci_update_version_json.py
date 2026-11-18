#!/usr/bin/env python3
"""Update publish/version.json for client update checks (CI).

`desc` 就是 App 更新弹窗里「更新说明」显示的内容（`lib/widgets/update_dialog.dart`
直接原样渲染），所以它必须带更新摘要——早期这里只写了一句模板
「线报酷 x.y.z / 由 tag … 自动构建」，App 里就只剩版本号和构建信息，看不到
这次改了什么。

摘要来源是**附注 tag 的说明**（工作流的 `steps.version.outputs.notes`，与
GitHub Release 页「本次更新」同一份），由 `VERSION_NOTES` 传进来。
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# 轻量 tag 没有说明时，工作流会塞一句 markdown 引用当占位——不能原样发给客户端。
_PLACEHOLDER_MARKERS = ("本次构建未提供更新摘要",)


def _clean_notes(raw: str) -> str:
    text = (raw or "").strip()
    if not text:
        return ""
    if any(marker in text for marker in _PLACEHOLDER_MARKERS):
        return ""
    # 占位文案是 "> xxx" 形式的 markdown 引用，真摘要不会以它开头。
    if text.startswith(">"):
        return ""
    return text


def compose_desc(version: str, notes: str, tag: str, short_sha: str) -> str:
    """拼出 App 里显示的更新说明：摘要在上，构建来源在下。"""
    parts: list[str] = []
    clean = _clean_notes(notes)
    parts.append(clean if clean else f"线报酷 {version}")
    if tag:
        origin = f"由 tag {tag} 自动构建"
        if short_sha:
            origin += f"（{short_sha}）"
        parts.append(origin)
    return "\n\n".join(parts)


def main() -> int:
    version = (os.environ.get("VERSION_NAME") or "").strip()
    if not version:
        print("VERSION_NAME is required", file=sys.stderr)
        return 1

    # VERSION_DESC 是显式覆盖（人工补写时用）；默认由 tag 说明拼出来。
    desc = os.environ.get("VERSION_DESC") or ""
    if not desc:
        desc = compose_desc(
            version,
            os.environ.get("VERSION_NOTES") or "",
            (os.environ.get("VERSION_TAG") or "").strip(),
            (os.environ.get("VERSION_SHA") or "").strip(),
        )

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