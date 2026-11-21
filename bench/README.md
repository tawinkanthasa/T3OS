# bench — T3 OS hardware core

The same code runs on Windows today and becomes T3's system tool later.

## Commands
| Command | What it does |
|---|---|
| `bench boards` | List connected boards (ESP32 / Pico / Arduino, matched by USB VID:PID) |
| `bench serial [PORT] [-t SEC]` | Read serial output. Brownouts and crashes show in red and are logged to the logbook |
| `bench flash FILE [PORT]` | Show the flash plan and ask y/n before writing (ESP32 = esptool, Pico = UF2) |
| `bench pins esp32` | Pin pitfalls: boot strap pins, input-only pins, pins that are off-limits |
| `bench log` | Show the event log (plug / flash / alert / note) |
| `bench watch` | Watch for USB plug/unplug and record events (the seed of the daemon) |

No board connected? `set BENCH_SIM=1` (PowerShell: `$env:BENCH_SIM=1`) gives you simulated boards: SIM0 = ESP32, SIM1 = Pico.

## Claude Code
`T3OS/.mcp.json` registers the `bench` MCP server. Tools: `list_boards`, `read_serial`, `get_pinout`,
`flash_plan`, `flash` (requires confirm=true), `logbook_tail`, `logbook_note`.
Once a real board is connected, remove `"BENCH_SIM": "1"` from `.mcp.json`.

## Dev
```
.venv\Scripts\python -m pytest -q tests
```
Logbook: `%LOCALAPPDATA%\bench\logbook.jsonl` (Linux: `~/.local/share/bench/`)
