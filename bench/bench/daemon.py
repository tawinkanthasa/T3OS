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

from . import boards as B, logbook, pins as P, serialmon, settings as ST

PORT = int(os.environ.get("BENCHD_PORT", "7300"))
def _ui_dir() -> Path:
    if os.environ.get("T3_UI"):
        return Path(os.environ["T3_UI"])
    repo = Path(__file__).resolve().parents[2] / "ui"   # running from the repo
    return repo if (repo / "index.html").exists() else Path("/usr/share/t3/ui")  # system install


UI_DIR = _ui_dir()
METRIC_RE = re.compile(r"(temp|vcc|hum)=([-\d.]+)")


class Hub:
    def __init__(self) -> None:
        self.clients: set[web.WebSocketResponse] = set()
        self.boards: dict[str, B.Board] = {}
        self.readers: dict[str, asyncio.Task] = {}
        self.paused: set[str] = set()
        self.ai: dict = {}
        self.last_notify: dict[str, float] = {}
        self.ai_changed = asyncio.Event()

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
                        notify(f"{now[p].name} เชื่อมต่อแล้ว", f"{p} · Super+B เปิดโต๊ะ")
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
                alert = any(p in item for p in serialmon.ALERT_PATTERNS)
                msg = {"type": "serial", "port": board.port, "line": item, "alert": alert}
                if alert:
                    now = asyncio.get_running_loop().time()
                    if now - self.last_notify.get(board.port, -1e9) > 300:  # max one per board per 5 min
                        self.last_notify[board.port] = now
                        notify(f"{board.name}: มีปัญหา", item[:120] + "\nดูต่อใน Logbook (Super+L)")
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
        while True:
            cfg = ST.read_ai()
            url = cfg["local"]["url"]
            local = {"configured": bool(url), "url": url, "up": False}
            if url:
                local["up"] = await asyncio.to_thread(_ping, url.rstrip("/") + "/models")
            ai = {"local": local, "claude": {"installed": shutil.which("claude") is not None},
                  "mode": cfg["router"]["mode"]}
            if ai != self.ai:
                self.ai = ai
                await self.send({"type": "ai", "ai": ai})
            self.ai_changed.clear()
            try:
                await asyncio.wait_for(self.ai_changed.wait(), 15)
            except asyncio.TimeoutError:
                pass


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


def _ai_status(hub: "Hub") -> dict:
    l = hub.ai.get("local", {})
    c = hub.ai.get("claude", {})
    parts = []
    if l.get("configured"):
        parts.append("local ●" if l.get("up") else "local ✕")
    if c.get("installed"):
        parts.append("claude ●")
    return {"text": "  ".join(parts), "tooltip": l.get("url") or "",
            "class": "down" if l.get("configured") and not l.get("up") else "ok"}


def _board_status(hub: "Hub") -> dict:
    bs = list(hub.boards.values())
    names = {"esp32": "ESP32", "rp2040": "Pico", "avr": "AVR"}
    text = "  ".join(f"{names.get(b.family, b.family)} ●" for b in bs) or "no board"
    recent_alert = any(e["kind"] == "alert" for e in logbook.tail(5))
    return {"text": text, "tooltip": "\n".join(f"{b.port}  {b.name}" for b in bs),
            "class": "alert" if recent_alert else ("ok" if bs else "none")}


async def api_status(request: web.Request) -> web.Response:
    """Menu-bar widget feed: boards + AI, each {text, tooltip, class}."""
    hub: Hub = request.app["hub"]
    return web.json_response({"boards": _board_status(hub), "ai": _ai_status(hub)})


def notify(title: str, body: str, urgent: bool = False) -> None:
    """Desktop notification via notify-send (mako). Silently skipped if unavailable."""
    if not shutil.which("notify-send"):
        return
    import subprocess
    subprocess.Popen(["notify-send", "-a", "T3", "-u", "critical" if urgent else "normal", title, body],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


async def api_settings_get(request: web.Request) -> web.Response:
    return web.json_response({"ai": ST.read_ai(), "prefs": ST.read_prefs(), "system": ST.system_info(),
                              "apps": sorted(ST.APPS)})


async def api_settings_ai(request: web.Request) -> web.Response:
    try:
        ai = ST.write_ai(await request.json())
    except ValueError as e:
        return web.json_response({"error": str(e)}, status=400)
    request.app["hub"].ai_changed.set()
    logbook.write("note", f"ตั้งค่า AI: local={ai['local']['url'] or '-'} mode={ai['router']['mode']}")
    return web.json_response({"ai": ai})


async def api_ai_test(request: web.Request) -> web.Response:
    body = await request.json()
    return web.json_response(await asyncio.to_thread(ST.test_local, str(body.get("url", ""))))


async def api_prefs(request: web.Request) -> web.Response:
    prefs = ST.write_prefs(await request.json())
    applied = ST.apply_wallpaper(prefs["wallpaper"])
    return web.json_response({"prefs": prefs, "applied": applied})


async def api_launch(request: web.Request) -> web.Response:
    return web.json_response(ST.launch(str((await request.json()).get("app", ""))))


ALLOWED_HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}


@web.middleware
async def guard(request: web.Request, handler):
    """benchd exposes a shell and settings, so only T3's own pages may talk to it.
    - Host must be localhost (blocks DNS-rebinding)
    - Origin, when a browser sends one, must be T3 itself (blocks other websites, incl. WebSocket hijacking)
    - state-changing calls from browsers must carry X-T3 (a cross-site page can't add it without CORS)"""
    if request.host not in ALLOWED_HOSTS:
        return web.Response(status=403, text="forbidden host")
    origin = request.headers.get("Origin")
    if origin is not None and origin.split("://", 1)[-1] not in ALLOWED_HOSTS:
        return web.Response(status=403, text="forbidden origin")
    if request.method == "POST" and origin is not None and request.headers.get("X-T3") != "1":
        return web.Response(status=403, text="missing X-T3")
    return await handler(request)


async def index(_: web.Request) -> web.FileResponse:
    return web.FileResponse(UI_DIR / "index.html", headers={"Cache-Control": "no-cache"})


def make_app() -> web.Application:
    app = web.Application(middlewares=[guard])
    hub = Hub()
    app["hub"] = hub

    async def start_bg(app):
        ST.apply_wallpaper(ST.read_prefs()["wallpaper"])
        app["bg"] = [asyncio.create_task(c) for c in (hub.watch_boards(), hub.watch_log(), hub.watch_ai())]

    async def stop_bg(app):
        for t in app["bg"] + list(hub.readers.values()):
            t.cancel()

    app.on_startup.append(start_bg)
    app.on_cleanup.append(stop_bg)
    app.add_routes([web.get("/", index), web.get("/ws", ws_events), web.get("/pty", ws_pty),
                    web.get("/api/pins/{family}", api_pins), web.get("/api/status", api_status),
                    web.post("/api/release", api_release),
                    web.get("/api/settings", api_settings_get), web.post("/api/settings/ai", api_settings_ai),
                    web.post("/api/ai/test", api_ai_test), web.post("/api/settings/prefs", api_prefs),
                    web.post("/api/launch", api_launch),
                    web.static("/", UI_DIR)])
    return app


def main() -> None:
    host = os.environ.get("BENCHD_HOST", "127.0.0.1")
    print(f"benchd on http://{host}:{PORT}  (ui: {UI_DIR})", flush=True)
    import signal
    # nothing to flush (logbook writes are per-line); serial threads can block shutdown, so exit hard
    signal.signal(signal.SIGTERM, lambda *_: os._exit(0))
    signal.signal(signal.SIGINT, lambda *_: os._exit(0))
    web.run_app(make_app(), host=host, port=PORT, print=None, handle_signals=False)
    # serial reader threads may sit in a blocking read; don't let them keep the process alive
    os._exit(0)


if __name__ == "__main__":
    main()
