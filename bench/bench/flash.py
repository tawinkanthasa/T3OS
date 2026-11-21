"""Flashing. ESP32 via esptool; RP2040 via UF2 copy to the BOOTSEL drive.

Approval is the caller's job (CLI asks y/n, MCP requires confirm=True).
"""
from __future__ import annotations

import shutil
import string
import subprocess
import sys
import time
from pathlib import Path

from . import logbook
from .boards import Board


class FlashError(RuntimeError):
    pass


def default_addr(firmware: Path) -> int:
    n = firmware.name.lower()
    return 0x0 if ("merged" in n or "factory" in n) else 0x10000


def plan(board: Board, firmware: Path, addr: int | None = None) -> dict:
    """Describe what flash() would do, without doing it."""
    if not firmware.exists() and not board.simulated:
        raise FlashError(f"firmware not found: {firmware}")
    if board.family == "esp32":
        a = default_addr(firmware) if addr is None else addr
        return {"method": "esptool", "port": board.port, "file": str(firmware), "addr": hex(a)}
    if board.family == "rp2040":
        if firmware.suffix.lower() != ".uf2":
            raise FlashError("RP2040 needs a .uf2 file")
        return {"method": "uf2-copy", "port": board.port, "file": str(firmware),
                "note": "hold BOOTSEL while plugging in; board shows up as drive RPI-RP2"}
    raise FlashError(f"flashing '{board.family}' boards is not supported yet")


def _find_rpi_drive() -> Path | None:
    if sys.platform == "win32":
        candidates = [Path(f"{d}:/") for d in string.ascii_uppercase]
    else:
        candidates = list(Path("/media").glob("*/RPI-RP2")) + list(Path("/run/media").glob("*/RPI-RP2"))
    for c in candidates:
        try:
            if (c / "INFO_UF2.TXT").exists():
                return c
        except OSError:
            continue
    return None


def flash(board: Board, firmware: Path, addr: int | None = None, log=print) -> dict:
    p = plan(board, firmware, addr)
    t0 = time.monotonic()
    if board.simulated:
        for pct in (0, 25, 50, 75, 100):
            log(f"[sim] writing {p['file']} ... {pct}%")
            time.sleep(0.1)
    elif p["method"] == "esptool":
        cmd = [sys.executable, "-m", "esptool", "--port", board.port, "--baud", "460800",
               "write_flash", p["addr"], str(firmware)]
        log("$ " + " ".join(cmd))
        r = subprocess.run(cmd)
        if r.returncode != 0:
            logbook.write("flash_fail", f"esptool exit {r.returncode}", board=board.port, file=p["file"])
            raise FlashError(f"esptool failed (exit {r.returncode})")
    else:
        drive = _find_rpi_drive()
        if not drive:
            raise FlashError("RPI-RP2 drive not found: " + p["note"])
        shutil.copy(firmware, drive / firmware.name)
    p["seconds"] = round(time.monotonic() - t0, 1)
    logbook.write("flash", f"flashed {Path(p['file']).name}", board=board.port, **p)
    return p
