"""bench-mcp: exposes the bench to Claude Code over MCP (stdio).

Register with:  claude mcp add bench -- <venv>/bin/bench-mcp
Flashing is a two-step action: flash_plan shows what will happen; flash only
runs with confirm=true, and Claude Code's own permission prompt guards it too.
"""
from __future__ import annotations

from pathlib import Path

from mcp.server.mcpserver import MCPServer

from . import boards as B, flash as F, logbook, pins as P, serialmon

mcp = MCPServer("bench")


@mcp.tool()
def list_boards() -> list[dict]:
    """List microcontroller boards plugged into this machine (port, family, name, USB ids)."""
    return [b.to_dict() for b in B.list_boards()]


@mcp.tool()
def read_serial(port: str | None = None, seconds: float = 3.0, baud: int = 115200,
                max_lines: int = 200) -> dict:
    """Read serial output from a board for a few seconds. Crash/brownout lines are flagged."""
    board = B.find(port)
    out = serialmon.read(board, baud, seconds=min(seconds, 30), max_lines=max_lines)
    alerts = [l for l in out if any(p in l for p in serialmon.ALERT_PATTERNS)]
    return {"port": board.port, "lines": out, "alerts": alerts}


@mcp.tool()
def get_pinout(family_or_port: str) -> dict:
    """Pinout gotchas (boot straps, input-only pins, power limits) for esp32, rp2040, avr, or a port."""
    fam = family_or_port if family_or_port in P.PINOUTS else B.find(family_or_port).family
    return P.get(fam)


@mcp.tool()
def flash_plan(firmware: str, port: str | None = None, addr: str | None = None) -> dict:
    """Describe a flash without doing it. Always call this and show the user before flash()."""
    board = B.find(port)
    return F.plan(board, Path(firmware), int(addr, 0) if addr else None)


@mcp.tool()
def flash(firmware: str, port: str | None = None, addr: str | None = None,
          confirm: bool = False) -> dict:
    """Flash firmware to a board. Requires confirm=true, set ONLY after the user approved the plan."""
    board = B.find(port)
    if not confirm:
        return {"refused": "set confirm=true only after the user approves",
                "plan": F.plan(board, Path(firmware), int(addr, 0) if addr else None)}
    logs: list[str] = []
    r = F.flash(board, Path(firmware), int(addr, 0) if addr else None, log=logs.append)
    r["log"] = logs[-20:]
    return r


@mcp.tool()
def logbook_tail(n: int = 30, kind: str | None = None) -> list[dict]:
    """Recent bench events (plug, unplug, flash, alert). Use to answer 'what happened?'."""
    return logbook.tail(n, kind)


@mcp.tool()
def logbook_note(msg: str, board: str | None = None) -> dict:
    """Add a note to the logbook (e.g. a fix you found), so it's remembered next time."""
    return logbook.write("note", msg, board=board)


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
