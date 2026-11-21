"""benchd: serves the T3 desktop UI and streams live bench state over WebSocket.

  GET  /              UI (T3OS/ui/index.html)
  WS   /ws            events: hello, boards, log, serial, metric, ai
  WS   /pty           real login shell (Linux only)
  GET  /api/pins/{f}  pinout notes
  POST /api/release   free a serial port (bench flash calls this before flashing)
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import shutil
import sys
import tomllib
import urllib.request
from pathlib import Path

from aiohttp import WSMsgType, web

from . import boards as B, logbook, pins as P, serialmon

PORT = int(os.environ.get("BENCHD_PORT", "7300"))
UI_DIR = Path(os.environ.get("T3_UI", Path(__file__).resolve().parents[2] / "ui"))
METRIC_RE = re.compile(r"(temp|vcc|hum)=([-\d.]+)")


class Hub:
    def __init__(self) -> None:
        self.clients: set[web.WebSocketResponse] = set()
        self.boards: dict[str, B.Board] = {}
        self.readers: dict[str, asyncio.Task] = {}
        self.paused: set[str] = set()
        self.ai: dict = {}

    async def send(self, msg: dict) -> None:
        data = json.dumps(msg, ensure_ascii=False)
        for ws in list(self.clients):
            try:
                await ws.send_str(data)
            except ConnectionError:
                self.clients.discard(ws)

    def hello(self) -> dict:
        return {"type": "hello", "boards": [b.to_dict() for b in self.boards.values()],
                "log": logbook.tail(40), "ai": self.ai, "host": os.uname().nodename if hasattr(os, "uname") else "t3"}

    # -- boards ------------------------------------------------------------
    async def watch_boards(self) -> None:
        first = True
        while True:
            now = {b.port: b for b in await asyncio.to_thread(B.list_boards)}
            added, removed = now.keys() - self.boards.keys(), self.boards.keys() - now.keys()
            if added or removed or first:
                for p in added:
                    if not first:
                        logbook.write("plug", f"{now[p].name} connected", board=p, family=now[p].family)
                    self.start_reader(now[p])
                for p in removed:
                    logbook.write("unplug", f"{self.boards[p].name} removed", board=p)
                    self.stop_reader(p)
                self.boards = now
                await self.send({"type": "boards", "boards": [b.to_dict() for b in now.values()],
                                 "added": sorted(added) if not first else []})
                first = False
            await asyncio.sleep(1)

    # -- serial ------------------------------------------------------------
    def start_reader(self, board: B.Board) -> None:
        if board.port not in self.readers and board.port not in self.paused:
            self.readers[board.port] = asyncio.create_task(self.read_serial(board))

    def stop_reader(self, port: str) -> None:
        t = self.readers.pop(port, None)
        if t:
            t.cancel()

    async def read_serial(self, board: B.Board) -> None:
        loop = asyncio.get_running_loop()
        q: asyncio.Queue = asyncio.Queue()
        stop = [False]

        def pump():
            try:
                for line in serialmon.lines(board, stop=lambda: stop[0], sim_delay=0.4):
                    loop.call_soon_threadsafe(q.put_nowait, line)
            except Exception as e:  # port busy, unplugged...
                loop.call_soon_threadsafe(q.put_nowait, e)

        fut = loop.run_in_executor(None, pump)
        try:
            while True:
                item = await q.get()
                if isinstance(item, Exception):
                    await self.send({"type": "serial", "port": board.port, "line": f"[bench] {item}", "err": True})
                    return
                msg = {"type": "serial", "port": board.port, "line": item,
                       "alert": any(p in item for p in serialmon.ALERT_PATTERNS)}
                await self.send(msg)
                m = dict((k, float(v)) for k, v in METRIC_RE.findall(item))
                if m:
                    await self.send({"type": "metric", "port": board.port, **m})
        except asyncio.CancelledError:
            raise
        finally:
            stop[0] = True
            fut.cancel()

    # -- logbook tail --------------------------------------------------------
    async def watch_log(self) -> None:
        path = logbook.path()
        pos = path.stat().st_size if path.exists() else 0
        while True:
            await asyncio.sleep(0.5)
            if not path.exists():
                continue
            size = path.stat().st_size
            if size < pos:
                pos = 0
            if size > pos:
                with path.open("r", encoding="utf-8") as f:
                    f.seek(pos)
                    chunk = f.read()
                    pos = f.tell()
                for line in chunk.splitlines():
                    try:
                        await self.send({"type": "log", "entry": json.loads(line)})
                    except json.JSONDecodeError:
                        pass

    # -- AI endpoints --------------------------------------------------------
    async def watch_ai(self) -> None:
        cfg_path = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "bench" / "ai.toml"
        while True:
            cfg = {}
            if cfg_path.exists():
                try:
                    cfg = tomllib.loads(cfg_path.read_text(encoding="utf-8"))
                except tomllib.TOMLDecodeError:
                    pass
            url = cfg.get("ai", {}).get("local", {}).get("url")
            local = {"configured": bool(url), "url": url, "up": False}
            if url:
                local["up"] = await asyncio.to_thread(_ping, url.rstrip("/") + "/models")
            ai = {"local": local, "claude": {"installed": shutil.which("claude") is not None}}
            if ai != self.ai:
                self.ai = ai
                await self.send({"type": "ai", "ai": ai})
            await asyncio.sleep(15)


def _ping(url: str) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            return r.status == 200
    except Exception:
        return False


# -- HTTP / WS handlers ------------------------------------------------------
async def ws_events(request: web.Request) -> web.WebSocketResponse:
    hub: Hub = request.app["hub"]
    ws = web.WebSocketResponse(heartbeat=20)
    await ws.prepare(request)
    hub.clients.add(ws)
    await ws.send_str(json.dumps(hub.hello(), ensure_ascii=False))
    async for msg in ws:
        if msg.type != WSMsgType.TEXT:
            continue
        cmd = json.loads(msg.data)
        if cmd.get("type") == "note":
            logbook.write("note", cmd["msg"], board=cmd.get("board"))
    hub.clients.discard(ws)
    return ws


async def ws_pty(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    if sys.platform == "win32":
        await ws.send_str("\r\n[benchd] real shell needs Linux (run benchd inside WSL / T3)\r\n")
        await ws.close()
        return ws
    import fcntl, pty, struct, termios

    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(TERM="xterm-256color", T3_DESKTOP="1",
                          PATH=os.path.dirname(sys.executable) + os.pathsep + os.environ.get("PATH", ""))
        os.chdir(os.environ.get("HOME", "/"))
        shell = os.environ.get("SHELL", "/bin/bash")
        os.execvp(shell, [shell, "-l"])
    loop = asyncio.get_running_loop()
    q: asyncio.Queue = asyncio.Queue()

    def readable():
        try:
            data = os.read(fd, 65536)
        except OSError:
            data = b""
        q.put_nowait(data)

    loop.add_reader(fd, readable)

    async def pump_out():
        while True:
            data = await q.get()
            if not data:
                await ws.close()
                return
            await ws.send_bytes(data)

    out_task = asyncio.create_task(pump_out())
    try:
        async for msg in ws:
            if msg.type == WSMsgType.BINARY:
                os.write(fd, msg.data)
            elif msg.type == WSMsgType.TEXT:
                m = json.loads(msg.data)
                if m.get("type") == "resize":
                    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", m["rows"], m["cols"], 0, 0))
                elif m.get("type") == "input":
                    os.write(fd, m["data"].encode())
    finally:
        out_task.cancel()
        loop.remove_reader(fd)
        try:
            os.kill(pid, 9)
            os.waitpid(pid, 0)
        except (ProcessLookupError, ChildProcessError):
            pass
        os.close(fd)
    return ws


async def api_pins(request: web.Request) -> web.Response:
    try:
        return web.json_response(P.get(request.match_info["family"]))
    except KeyError as e:
        return web.json_response({"error": str(e)}, status=404)


async def api_release(request: web.Request) -> web.Response:
    """Pause our serial reader on a port for N seconds (so esptool can use it)."""
    hub: Hub = request.app["hub"]
    port = request.query.get("port", "")
    secs = float(request.query.get("seconds", "60"))
    hub.paused.add(port)
    hub.stop_reader(port)
    await asyncio.sleep(0.3)

    async def resume():
        await asyncio.sleep(secs)
        hub.paused.discard(port)
        if port in hub.boards:
            hub.start_reader(hub.boards[port])

    asyncio.create_task(resume())
    return web.json_response({"released": port, "seconds": secs})


async def index(_: web.Request) -> web.FileResponse:
    return web.FileResponse(UI_DIR / "index.html", headers={"Cache-Control": "no-cache"})


def make_app() -> web.Application:
    app = web.Application()
    hub = Hub()
    app["hub"] = hub

    async def start_bg(app):
        app["bg"] = [asyncio.create_task(c) for c in (hub.watch_boards(), hub.watch_log(), hub.watch_ai())]

    async def stop_bg(app):
        for t in app["bg"] + list(hub.readers.values()):
            t.cancel()

    app.on_startup.append(start_bg)
    app.on_cleanup.append(stop_bg)
    app.add_routes([web.get("/", index), web.get("/ws", ws_events), web.get("/pty", ws_pty),
                    web.get("/api/pins/{family}", api_pins), web.post("/api/release", api_release),
                    web.static("/", UI_DIR)])
    return app


def main() -> None:
    host = os.environ.get("BENCHD_HOST", "127.0.0.1")
    print(f"benchd on http://{host}:{PORT}  (ui: {UI_DIR})", flush=True)
    web.run_app(make_app(), host=host, port=PORT, print=None)


if __name__ == "__main__":
    main()
