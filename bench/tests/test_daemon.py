"""benchd HTTP tests: origin guard and settings API."""
import asyncio

import pytest
from aiohttp.test_utils import TestClient, TestServer


@pytest.fixture(autouse=True)
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("BENCH_HOME", str(tmp_path / "home"))
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "cfg"))
    monkeypatch.setenv("BENCH_SIM", "1")


def run(coro_fn):
    async def go():
        from bench import daemon
        # random port; the Host header below still claims the real benchd address
        client = TestClient(TestServer(daemon.make_app()))
        await client.start_server()
        try:
            return await coro_fn(client, f"127.0.0.1:{daemon.PORT}")
        finally:
            await client.close()
    return asyncio.run(go())


def test_guard_blocks_foreign_origin_and_host():
    async def t(c, host):
        own = {"Host": host}
        assert (await c.get("/api/settings", headers=own)).status == 200
        assert (await c.get("/api/settings", headers={"Host": "evil.example:7300"})).status == 403
        r = await c.post("/api/launch", json={"app": "files"},
                         headers={**own, "Origin": "https://evil.example", "X-T3": "1"})
        assert r.status == 403
        r = await c.post("/api/launch", json={"app": "nope"}, headers={**own, "Origin": f"http://{host}"})
        assert r.status == 403  # browser POST without X-T3
        r = await c.get("/pty", headers={**own, "Origin": "https://evil.example",
                                         "Upgrade": "websocket", "Connection": "Upgrade",
                                         "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
                                         "Sec-WebSocket-Version": "13"})
        assert r.status == 403
    run(t)


def test_settings_ai_roundtrip_and_validation():
    async def t(c, host):
        h = {"Host": host, "Origin": f"http://{host}", "X-T3": "1"}
        r = await c.post("/api/settings/ai", headers=h, json={
            "local": {"url": "http://192.168.1.50:1234/v1", "model": "qwen"},
            "router": {"mode": "local", "ask_before_cloud": False}})
        ai = (await r.json())["ai"]
        assert ai["local"]["url"] == "http://192.168.1.50:1234/v1" and ai["router"]["mode"] == "local"
        assert ai["router"]["ask_before_cloud"] is False
        got = await (await c.get("/api/settings", headers={"Host": host})).json()
        assert got["ai"]["local"]["model"] == "qwen"
        bad = await c.post("/api/settings/ai", headers=h, json={"local": {"url": "ftp://x"}})
        assert bad.status == 400
        r = await c.post("/api/launch", headers=h, json={"app": "rm -rf"})
        assert (await r.json())["ok"] is False
    run(t)
