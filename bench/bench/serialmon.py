"""Serial reading. Simulated boards produce a realistic ESP32 boot + sensor stream."""
from __future__ import annotations

import itertools
import random
import time
from typing import Iterator

import serial

from . import logbook
from .boards import Board

ALERT_PATTERNS = ("Brownout detector", "Guru Meditation", "panic", "abort()",
                  "WDT_RESET", "TG0WDT", "TG1WDT", "Task watchdog", "BROWNOUT_RST")

_SIM_BOOT = [
    "ets Jun  8 2016 00:22:57",
    "rst:0x1 (POWERON_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)",
    "I (29) boot: ESP-IDF v5.3 2nd stage bootloader",
    "I (312) wifi: connecting to bench-lab ...",
    "I (1840) wifi: got ip 192.168.1.77",
]


def _sim_lines(board: Board) -> Iterator[str]:
    yield from _SIM_BOOT
    for i in itertools.count():
        t = 24.0 + random.uniform(-0.6, 0.6)
        yield f"temp={t:.2f}C hum={55 + random.uniform(-3, 3):.1f}% vcc={3.30 - random.uniform(0, 0.05):.2f}V"
        if i % 17 == 16:
            yield "Brownout detector was triggered"
            yield from _SIM_BOOT[:2]


def lines(board: Board, baud: int = 115200, seconds: float | None = None,
          max_lines: int | None = None, stop=None, sim_delay: float = 0.05) -> Iterator[str]:
    """Yield decoded lines until `seconds` or `max_lines` is reached. Alerts go to the logbook."""
    deadline = time.monotonic() + seconds if seconds else None
    count = 0

    def done() -> bool:
        return (deadline is not None and time.monotonic() >= deadline) or \
               (max_lines is not None and count >= max_lines) or \
               (stop is not None and stop())

    if board.simulated:
        for line in _sim_lines(board):
            if done():
                return
            time.sleep(sim_delay)
            count += 1
            _check_alert(board, line)
            yield line
        return

    with serial.Serial(board.port, baud, timeout=0.2) as ser:
        buf = b""
        while not done():
            chunk = ser.read(256)
            if not chunk:
                continue
            buf += chunk
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                line = raw.decode("utf-8", "replace").rstrip("\r")
                count += 1
                _check_alert(board, line)
                yield line
                if done():
                    return


def _check_alert(board: Board, line: str) -> None:
    if any(p in line for p in ALERT_PATTERNS):
        logbook.write("alert", line, board=board.port)


def read(board: Board, baud: int = 115200, seconds: float = 3.0, max_lines: int = 200) -> list[str]:
    return list(lines(board, baud, seconds=seconds, max_lines=max_lines))
