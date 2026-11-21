"""Logbook: every bench event is appended as one JSON line.

Location: $BENCH_HOME/logbook.jsonl, default ~/.local/share/bench (Linux)
or %LOCALAPPDATA%/bench (Windows).
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path


def home() -> Path:
    if env := os.environ.get("BENCH_HOME"):
        p = Path(env)
    elif sys.platform == "win32":
        p = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "bench"
    else:
        p = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "bench"
    p.mkdir(parents=True, exist_ok=True)
    return p


def path() -> Path:
    return home() / "logbook.jsonl"


def write(kind: str, msg: str, board: str | None = None, **extra) -> dict:
    entry = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "kind": kind, "board": board, "msg": msg}
    entry.update(extra)
    with path().open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return entry


def tail(n: int = 20, kind: str | None = None) -> list[dict]:
    p = path()
    if not p.exists():
        return []
    out = []
    for line in p.read_text(encoding="utf-8").splitlines():
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if kind is None or e.get("kind") == kind:
            out.append(e)
    return out[-n:]
