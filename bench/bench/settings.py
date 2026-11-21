"""T3 settings: AI endpoints (ai.toml), desktop prefs (settings.json), system info, safe app launching."""
from __future__ import annotations

import json
import os
import re
import platform
import shutil
import subprocess
import time
import tomllib
import urllib.request
from pathlib import Path


def config_dir() -> Path:
    p = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "bench"
    p.mkdir(parents=True, exist_ok=True)
    return p


AI_DEFAULT = {
    "local": {"url": "", "model": ""},
    "claude": {"model": "claude-sonnet-5-5"},
    "router": {"mode": "auto", "ask_before_cloud": True},
}


def read_ai() -> dict:
    out = json.loads(json.dumps(AI_DEFAULT))
    p = config_dir() / "ai.toml"
    if p.exists():
        try:
            data = tomllib.loads(p.read_text(encoding="utf-8")).get("ai", {})
        except tomllib.TOMLDecodeError:
            data = {}
        for sec, vals in data.items():
            if sec in out and isinstance(vals, dict):
                out[sec].update({k: v for k, v in vals.items() if k in out[sec]})
    return out


def _toml_val(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    return json.dumps(str(v), ensure_ascii=False)  # JSON string escaping is valid TOML basic string


def write_ai(new: dict) -> dict:
    cur = read_ai()
    for sec in cur:
        for k in cur[sec]:
            if k in new.get(sec, {}):
                v = new[sec][k]
                cur[sec][k] = bool(v) if isinstance(cur[sec][k], bool) else str(v).strip()
    if cur["router"]["mode"] not in ("local", "auto", "claude"):
        cur["router"]["mode"] = "auto"
    url = cur["local"]["url"]
    if url and not url.startswith(("http://", "https://")):
        raise ValueError("URL ต้องขึ้นต้นด้วย http:// หรือ https://")
    lines = ["# written by T3 Settings"]
    for sec, vals in cur.items():
        lines.append(f"\n[ai.{sec}]")
        lines += [f"{k} = {_toml_val(v)}" for k, v in vals.items()]
    (config_dir() / "ai.toml").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return cur


def test_local(url: str) -> dict:
    """Probe an OpenAI-compatible endpoint (LM Studio): list models."""
    if not url.startswith(("http://", "https://")):
        return {"ok": False, "error": "URL ต้องขึ้นต้นด้วย http:// หรือ https://"}
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(url.rstrip("/") + "/models", timeout=4) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
        models = [m.get("id") for m in data.get("data", []) if isinstance(m, dict)]
        return {"ok": True, "models": models, "ms": round((time.monotonic() - t0) * 1000)}
    except Exception as e:  # noqa: BLE001 - report any failure to the user
        return {"ok": False, "error": str(e)}


# ---- desktop prefs ---------------------------------------------------------
PREFS_DEFAULT = {"wallpaper": "#0a0d0b"}


def read_prefs() -> dict:
    p = config_dir() / "settings.json"
    out = dict(PREFS_DEFAULT)
    if p.exists():
        try:
            out.update(json.loads(p.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            pass
    return out


def write_prefs(new: dict) -> dict:
    cur = read_prefs()
    cur.update({k: v for k, v in new.items() if k in PREFS_DEFAULT})
    (config_dir() / "settings.json").write_text(json.dumps(cur, indent=2), encoding="utf-8")
    return cur


def apply_wallpaper(value: str) -> bool:
    """#rrggbb colour or an image path; applied live to every Plasma desktop over D-Bus."""
    if not shutil.which("dbus-send"):
        return False
    if re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        plugin, group, key, val = "org.kde.color", "General", "Color", value
    elif Path(value).expanduser().is_file():
        plugin, group, key, val = "org.kde.image", "General", "Image", "file://" + str(Path(value).expanduser())
    else:
        return False
    script = ("desktops().forEach(function(d){d.wallpaperPlugin=%s;"
              "d.currentConfigGroup=['Wallpaper',%s,%s];d.writeConfig(%s,%s);});"
              % tuple(json.dumps(x) for x in (plugin, plugin, group, key, val)))
    cmd = ["dbus-send", "--session", "--type=method_call", "--dest=org.kde.plasmashell",
           "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", "string:" + script]
    return subprocess.run(cmd, capture_output=True).returncode == 0


# ---- launching system tools (whitelist only) -------------------------------
APPS = {
    "wifi": ["systemsettings", "kcm_networkmanagement"],
    "bluetooth": ["systemsettings", "kcm_bluetooth"],
    "sound": ["systemsettings", "kcm_pulseaudio"],
    "display": ["systemsettings", "kcm_kscreen"],
    "thai": ["systemsettings", "kcm_keyboard"],
    "apps": ["plasma-discover"],
    "files": ["dolphin"],
    "update": ["plasma-discover", "--mode", "update"],
    "snapshots": ["timeshift-launcher"],
    "system": ["systemsettings"],
}


def launch(name: str) -> dict:
    cmd = APPS.get(name)
    if not cmd:
        return {"ok": False, "error": f"unknown app '{name}'"}
    exe = cmd[0] if os.path.isabs(cmd[0]) else shutil.which(cmd[0])
    if not exe or not os.path.exists(exe):
        return {"ok": False, "error": f"{cmd[0]} ยังไม่ได้ติดตั้ง"}
    subprocess.Popen([exe, *cmd[1:]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    return {"ok": True}


def system_info() -> dict:
    info = {"hostname": platform.node(), "kernel": platform.release(), "python": platform.python_version()}
    try:
        osr = dict(l.split("=", 1) for l in Path("/etc/os-release").read_text().splitlines() if "=" in l)
        info["os"] = osr.get("PRETTY_NAME", "").strip('"')
    except OSError:
        info["os"] = platform.system()
    try:
        mem = dict(l.split(":", 1) for l in Path("/proc/meminfo").read_text().splitlines())
        info["mem_gb"] = round(int(mem["MemTotal"].split()[0]) / 1048576, 1)
        info["uptime_h"] = round(float(Path("/proc/uptime").read_text().split()[0]) / 3600, 1)
    except (OSError, KeyError, ValueError):
        pass
    du = shutil.disk_usage(Path.home())
    info["disk_free_gb"], info["disk_total_gb"] = round(du.free / 1e9), round(du.total / 1e9)
    info["claude_code"] = shutil.which("claude") is not None
    return info
