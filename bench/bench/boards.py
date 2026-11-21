"""Board detection by USB VID:PID.

Set BENCH_SIM=1 to add simulated boards (useful when no hardware is plugged in).
"""
from __future__ import annotations

import os
from dataclasses import dataclass, asdict

from serial.tools import list_ports

# (vid, pid) -> (family, guess, chip)
KNOWN: dict[tuple[int, int], tuple[str, str, str]] = {
    (0x10C4, 0xEA60): ("esp32", "ESP32 DevKit (CP210x)", "CP2102"),
    (0x1A86, 0x7523): ("esp32", "ESP32 / Arduino clone (CH340)", "CH340"),
    (0x1A86, 0x55D4): ("esp32", "ESP32 DevKit (CH9102)", "CH9102"),
    (0x303A, 0x1001): ("esp32", "ESP32-S3/C3 (native USB)", "USB-JTAG"),
    (0x303A, 0x0002): ("esp32", "ESP32-S2 (native USB)", "USB-CDC"),
    (0x2E8A, 0x0005): ("rp2040", "Raspberry Pi Pico (MicroPython)", "RP2040"),
    (0x2E8A, 0x000A): ("rp2040", "Raspberry Pi Pico (SDK CDC)", "RP2040"),
    (0x2E8A, 0x0003): ("rp2040", "Raspberry Pi Pico (BOOTSEL)", "RP2040"),
    (0x2341, 0x0043): ("avr", "Arduino Uno", "ATmega16U2"),
    (0x2341, 0x0001): ("avr", "Arduino Uno", "ATmega8U2"),
    (0x2341, 0x0042): ("avr", "Arduino Mega 2560", "ATmega16U2"),
    (0x0403, 0x6001): ("generic", "FTDI USB-Serial", "FT232R"),
}

SIM_BOARDS = [
    {"port": "SIM0", "vid": 0x10C4, "pid": 0xEA60, "serial": "sim-esp32-01"},
    {"port": "SIM1", "vid": 0x2E8A, "pid": 0x0005, "serial": "sim-pico-01"},
]


@dataclass
class Board:
    port: str
    family: str
    name: str
    chip: str
    vid: str
    pid: str
    serial: str | None
    simulated: bool = False

    def to_dict(self) -> dict:
        return asdict(self)


def sim_enabled() -> bool:
    return os.environ.get("BENCH_SIM", "") not in ("", "0")


def _make(port, vid, pid, serial, simulated=False) -> Board | None:
    if vid is None:
        return None
    family, name, chip = KNOWN.get((vid, pid), ("unknown", "Unknown USB serial device", "?"))
    return Board(port, family, name, chip, f"{vid:04X}", f"{pid:04X}", serial, simulated)


def list_boards(include_unknown: bool = True) -> list[Board]:
    boards = []
    for p in list_ports.comports():
        b = _make(p.device, p.vid, p.pid, p.serial_number)
        if b and (include_unknown or b.family != "unknown"):
            boards.append(b)
    if sim_enabled():
        boards += [_make(s["port"], s["vid"], s["pid"], s["serial"], True) for s in SIM_BOARDS]
    return boards


def find(port_or_family: str | None) -> Board:
    """Resolve a port name ('COM7', '/dev/ttyUSB0', 'SIM0') or family ('esp32')."""
    boards = list_boards()
    if not boards:
        raise LookupError("no boards connected (tip: BENCH_SIM=1 for simulated boards)")
    if port_or_family is None:
        if len(boards) > 1:
            raise LookupError("several boards connected; pick one: " + ", ".join(b.port for b in boards))
        return boards[0]
    key = port_or_family.lower()
    for b in boards:
        if b.port.lower() == key:
            return b
    matches = [b for b in boards if b.family == key]
    if len(matches) == 1:
        return matches[0]
    if matches:
        raise LookupError(f"several {key} boards: " + ", ".join(b.port for b in matches))
    raise LookupError(f"no board matches '{port_or_family}'")
