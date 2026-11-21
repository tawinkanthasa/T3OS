"""bench: T3 command line.

  bench boards                 list connected boards
  bench serial [PORT]          stream serial output (Ctrl+C to stop)
  bench flash FILE [PORT]      flash firmware (asks y/n unless --yes)
  bench pins [FAMILY|PORT]     pinout gotchas
  bench log [-n N]             show the logbook
  bench watch                  log plug/unplug events (daemon seed)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

from . import boards as B, flash as F, logbook, pins as P, serialmon

C = {"dim": "\033[2m", "amber": "\033[33m", "green": "\033[32m", "red": "\033[31m", "off": "\033[0m"}
if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
    C = {k: "" for k in C}


def _err(msg: str) -> int:
    print(f"{C['red']}bench: {msg}{C['off']}", file=sys.stderr)
    return 1


def cmd_boards(a) -> int:
    bs = B.list_boards(include_unknown=a.all)
    if a.json:
        print(json.dumps([b.to_dict() for b in bs], indent=2))
        return 0
    if not bs:
        print(f"{C['dim']}no boards. plug one in, or try BENCH_SIM=1{C['off']}")
        return 0
    for b in bs:
        sim = f" {C['dim']}(sim){C['off']}" if b.simulated else ""
        print(f"{C['amber']}{b.port:<14}{C['off']} {b.family:<8} {b.name}  "
              f"{C['dim']}{b.vid}:{b.pid} {b.chip}{C['off']}{sim}")
    return 0


def cmd_serial(a) -> int:
    board = B.find(a.port)
    print(f"{C['dim']}-- {board.port} @ {a.baud}, Ctrl+C to stop --{C['off']}")
    try:
        for line in serialmon.lines(board, a.baud, seconds=a.seconds):
            alert = any(p in line for p in serialmon.ALERT_PATTERNS)
            print(f"{C['red'] if alert else ''}{line}{C['off'] if alert else ''}", flush=True)
    except KeyboardInterrupt:
        pass
    return 0


def cmd_flash(a) -> int:
    board = B.find(a.port)
    fw = Path(a.file)
    p = F.plan(board, fw, int(a.addr, 0) if a.addr else None)
    print(f"{C['amber']}flash plan{C['off']}")
    for k, v in p.items():
        print(f"  {k:<7} {v}")
    if not a.yes:
        if input("proceed? [y/N] ").strip().lower() not in ("y", "yes"):
            print("cancelled")
            logbook.write("flash_cancel", "user declined", board=board.port)
            return 1
    r = F.flash(board, fw, int(a.addr, 0) if a.addr else None)
    print(f"{C['green']}done in {r['seconds']}s{C['off']}")
    return 0


def cmd_pins(a) -> int:
    fam = a.target
    if fam is None or fam not in P.PINOUTS:
        fam = B.find(fam).family
    d = P.get(fam)
    print(f"{C['amber']}{d['board']}{C['off']}  logic {d['logic']}")
    for pin, note in d["pins"].items():
        warn = any(w in note for w in ("DO NOT", "INPUT ONLY", "boot fails", "strap"))
        print(f"  {(C['red'] if warn else '')}{pin:<10}{C['off']} {note}")
    print(f"{C['dim']}power: {d['power']}{C['off']}")
    return 0


def cmd_log(a) -> int:
    for e in logbook.tail(a.n, a.kind):
        board = f" [{e['board']}]" if e.get("board") else ""
        color = C["red"] if e["kind"] in ("alert", "flash_fail") else C["amber"]
        print(f"{C['dim']}{e['ts']}{C['off']} {color}{e['kind']:<12}{C['off']}{board} {e['msg']}")
    return 0


def cmd_watch(a) -> int:
    seen: dict[str, B.Board] = {}
    print(f"{C['dim']}watching USB every {a.interval}s, Ctrl+C to stop{C['off']}")
    try:
        while True:
            now = {b.port: b for b in B.list_boards()}
            for port in now.keys() - seen.keys():
                b = now[port]
                logbook.write("plug", f"{b.name} connected", board=port, family=b.family)
                print(f"{C['green']}+ {port}{C['off']} {b.name}")
            for port in seen.keys() - now.keys():
                logbook.write("unplug", f"{seen[port].name} removed", board=port)
                print(f"{C['red']}- {port}{C['off']} {seen[port].name}")
            seen = now
            time.sleep(a.interval)
    except KeyboardInterrupt:
        return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="bench", description="T3 bench: boards, flash, serial, logbook")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("boards", help="list connected boards")
    s.add_argument("--json", action="store_true")
    s.add_argument("--all", action="store_true", help="include unknown serial devices")
    s.set_defaults(fn=cmd_boards)

    s = sub.add_parser("serial", help="stream serial output")
    s.add_argument("port", nargs="?")
    s.add_argument("-b", "--baud", type=int, default=115200)
    s.add_argument("-t", "--seconds", type=float)
    s.set_defaults(fn=cmd_serial)

    s = sub.add_parser("flash", help="flash firmware")
    s.add_argument("file")
    s.add_argument("port", nargs="?")
    s.add_argument("--addr", help="flash offset, e.g. 0x10000 (ESP32)")
    s.add_argument("-y", "--yes", action="store_true", help="skip confirmation")
    s.set_defaults(fn=cmd_flash)

    s = sub.add_parser("pins", help="pinout gotchas")
    s.add_argument("target", nargs="?", help="family (esp32/rp2040/avr) or port")
    s.set_defaults(fn=cmd_pins)

    s = sub.add_parser("log", help="show logbook")
    s.add_argument("-n", type=int, default=20)
    s.add_argument("--kind")
    s.set_defaults(fn=cmd_log)

    s = sub.add_parser("watch", help="log plug/unplug events")
    s.add_argument("--interval", type=float, default=1.0)
    s.set_defaults(fn=cmd_watch)
    return ap


def main(argv: list[str] | None = None) -> int:
    if sys.platform == "win32":
        os.system("")  # enable ANSI colors in Windows console
        sys.stdout.reconfigure(encoding="utf-8")
    a = build_parser().parse_args(argv)
    try:
        return a.fn(a)
    except (LookupError, F.FlashError, KeyError) as e:
        return _err(str(e).strip("'\""))


if __name__ == "__main__":
    sys.exit(main())
