"""Wi-Fi, Bluetooth, sound and display for T3 Settings, through the desktop's own tools
(nmcli, bluetoothctl, pactl, kscreen-doctor, KDE ScreenBrightness over D-Bus).
Every command is an argv list (never a shell) and every value from the page is checked first."""
from __future__ import annotations

import json
import re
import shutil
import subprocess


class SysError(Exception):
    """A user-facing error (Thai), returned to the page as {"error": ...}."""


def _run(argv: list[str], timeout: float = 15, check: bool = True) -> str:
    if not shutil.which(argv[0]):
        raise SysError(f"ไม่มีคำสั่ง {argv[0]} ในเครื่อง")
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise SysError(f"{argv[0]} ไม่ตอบ (เกิน {int(timeout)} วินาที)") from None
    if check and r.returncode != 0:
        msg = (r.stderr or r.stdout).strip().splitlines()
        raise SysError(msg[-1] if msg else f"{argv[0]} ล้มเหลว")
    return r.stdout


def _split_terse(line: str) -> list[str]:
    """nmcli -t output: fields split by ':', with '\\:' and '\\\\' escaped inside values."""
    out, cur, esc = [], [], False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


# ---- Wi-Fi -----------------------------------------------------------------
def wifi_status(rescan: bool = False) -> dict:
    radio = _run(["nmcli", "radio", "wifi"]).strip() == "enabled"
    devices = []
    for line in _run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]).splitlines():
        dev, typ, state, conn = (_split_terse(line) + [""] * 4)[:4]
        if typ in ("wifi", "ethernet"):
            devices.append({"device": dev, "type": typ, "connected": state.startswith("connected")
                            and "externally" not in state, "state": state, "connection": conn})
    nets: dict[str, dict] = {}
    if radio and any(d["type"] == "wifi" for d in devices):
        lines = _run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list",
                      "--rescan", "yes" if rescan else "auto"], timeout=25).splitlines()
        for line in lines:
            inuse, ssid, signal, sec = (_split_terse(line) + [""] * 4)[:4]
            if not ssid:
                continue  # hidden network
            n = {"ssid": ssid, "signal": int(signal or 0), "secure": sec not in ("", "--"),
                 "active": inuse.strip() == "*"}
            old = nets.get(ssid)
            if not old or n["active"] or (n["signal"] > old["signal"] and not old["active"]):
                nets[ssid] = n
    saved = {_split_terse(l)[0] for l in _run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]).splitlines()
             if _split_terse(l)[1:2] == ["802-11-wireless"]}
    for n in nets.values():
        n["saved"] = n["ssid"] in saved
    order = sorted(nets.values(), key=lambda n: (not n["active"], -n["signal"]))
    return {"radio": radio, "devices": devices, "networks": order}


def _ssid(s) -> str:
    s = str(s or "")
    if not 1 <= len(s.encode()) <= 32:
        raise SysError("ชื่อ Wi-Fi ไม่ถูกต้อง")
    return s


def wifi_connect(ssid, password=None) -> dict:
    ssid = _ssid(ssid)
    argv = ["nmcli", "device", "wifi", "connect", ssid]
    if password:
        if not 8 <= len(str(password)) <= 63:
            raise SysError("รหัส Wi-Fi ต้องยาว 8–63 ตัว")
        argv += ["password", str(password)]
    try:
        _run(argv, timeout=45)
    except SysError as e:
        if "Secrets were required" in str(e) or "password" in str(e).lower():
            raise SysError("รหัสผ่านไม่ถูก หรือยังไม่ได้ใส่รหัส") from None
        raise
    return {"ok": True}


def wifi_disconnect(device) -> dict:
    devs = [d["device"] for d in wifi_status()["devices"] if d["type"] == "wifi"]
    if device not in devs:
        raise SysError("ไม่พบอุปกรณ์ Wi-Fi นี้")
    _run(["nmcli", "device", "disconnect", device])
    return {"ok": True}


def wifi_forget(ssid) -> dict:
    _run(["nmcli", "connection", "delete", "id", _ssid(ssid)])
    return {"ok": True}


def wifi_radio(on: bool) -> dict:
    _run(["nmcli", "radio", "wifi", "on" if on else "off"])
    return {"ok": True}


# ---- Bluetooth -------------------------------------------------------------
_MAC = re.compile(r"[0-9A-F]{2}(:[0-9A-F]{2}){5}")


def _mac(addr) -> str:
    a = str(addr or "").upper()
    if not _MAC.fullmatch(a):
        raise SysError("ที่อยู่อุปกรณ์บลูทูธไม่ถูกต้อง")
    return a


def _bt_info(addr: str) -> dict:
    info = {}
    for line in _run(["bluetoothctl", "info", addr], check=False).splitlines():
        if ":" in line and line.startswith("\t"):
            k, v = line.strip().split(":", 1)
            info[k.strip()] = v.strip()
    return info


def bt_status() -> dict:
    show = _run(["bluetoothctl", "show"], check=False)
    if "Controller" not in show:
        return {"present": False, "powered": False, "devices": []}
    powered = bool(re.search(r"^\s*Powered: yes", show, re.M))
    devices = []
    for line in _run(["bluetoothctl", "devices"], check=False).splitlines():
        m = re.match(r"Device (\S+) (.*)", line)
        if not m or not _MAC.fullmatch(m.group(1).upper()):
            continue
        info = _bt_info(m.group(1))
        devices.append({"addr": m.group(1), "name": info.get("Alias") or m.group(2),
                        "paired": info.get("Paired") == "yes", "connected": info.get("Connected") == "yes",
                        "icon": info.get("Icon", ""), "battery": _battery(info)})
    devices.sort(key=lambda d: (not d["connected"], not d["paired"], d["name"].lower()))
    return {"present": True, "powered": powered, "devices": devices}


def _battery(info: dict):
    m = re.search(r"\((\d+)\)", info.get("Battery Percentage", ""))
    return int(m.group(1)) if m else None


def bt_power(on: bool) -> dict:
    _run(["bluetoothctl", "power", "on" if on else "off"])
    return {"ok": True}


def bt_scan(seconds: int = 8) -> dict:
    """Look for nearby devices for a few seconds; they then show up in bt_status()."""
    _run(["bluetoothctl", "--timeout", str(max(3, min(int(seconds), 20))), "scan", "on"],
         timeout=30, check=False)
    return bt_status()


def bt_action(action: str, addr) -> dict:
    addr = _mac(addr)
    if action == "pair":
        _run(["bluetoothctl", "--timeout", "25", "pair", addr], timeout=35)
        _run(["bluetoothctl", "trust", addr], check=False)
        _run(["bluetoothctl", "--timeout", "15", "connect", addr], timeout=25, check=False)
    elif action in ("connect", "disconnect"):
        _run(["bluetoothctl", "--timeout", "15", action, addr], timeout=25)
    elif action == "remove":
        _run(["bluetoothctl", "remove", addr])
    else:
        raise SysError("คำสั่งบลูทูธไม่รู้จัก")
    info = _bt_info(addr)
    if action in ("pair", "connect") and info.get("Connected") != "yes":
        raise SysError("ต่อไม่สำเร็จ: ลองเปิดอุปกรณ์ให้อยู่ในโหมดจับคู่ แล้วกดใหม่")
    return {"ok": True}


# ---- Sound -----------------------------------------------------------------
def _pa_list(kind: str) -> list[dict]:
    return json.loads(_run(["pactl", "-f", "json", "list", kind]) or "[]")


def _vol(dev: dict) -> int:
    vals = [int(str(c.get("value_percent", "0")).rstrip("%")) for c in (dev.get("volume") or {}).values()]
    return round(sum(vals) / len(vals)) if vals else 0


def sound_status() -> dict:
    default = {"sinks": _run(["pactl", "get-default-sink"]).strip(),
               "sources": _run(["pactl", "get-default-source"]).strip()}
    out = {}
    for kind in ("sinks", "sources"):
        out[kind] = [{"name": d["name"], "label": d.get("description") or d["name"], "volume": _vol(d),
                      "mute": bool(d.get("mute")), "default": d["name"] == default[kind]}
                     for d in _pa_list(kind)
                     if not (kind == "sources" and d.get("monitor_source") == "" and ".monitor" in d["name"])
                     and not d["name"].endswith(".monitor")]
    return out


def sound_set(kind, name, volume=None, mute=None, default=None) -> dict:
    if kind not in ("sinks", "sources"):
        raise SysError("ชนิดอุปกรณ์เสียงไม่ถูกต้อง")
    if name not in {d["name"] for d in _pa_list(kind)}:
        raise SysError("ไม่พบอุปกรณ์เสียงนี้")
    one = kind[:-1]  # sink / source
    if volume is not None:
        v = max(0, min(int(volume), 150))
        _run(["pactl", f"set-{one}-volume", name, f"{v}%"])
    if mute is not None:
        _run(["pactl", f"set-{one}-mute", name, "1" if mute else "0"])
    if default:
        _run(["pactl", f"set-default-{one}", name])
    return {"ok": True}


# ---- Display ---------------------------------------------------------------
SCALES = [1.0, 1.25, 1.5, 1.75, 2.0]


def _kscreen() -> dict:
    return json.loads(_run(["kscreen-doctor", "-j"]))


def _brightness() -> dict:
    """{output label: {"obj": dbus path, "value": %}} from KDE's ScreenBrightness (Plasma 6.2+)."""
    out = {}
    q = shutil.which("qdbus6") or shutil.which("qdbus")
    if not q:
        return out
    r = subprocess.run([q, "org.kde.ScreenBrightness", "/org/kde/ScreenBrightness",
                        "org.kde.ScreenBrightness.DisplaysDBusNames"], capture_output=True, text=True, timeout=5)
    for name in r.stdout.split():
        if not re.fullmatch(r"[A-Za-z0-9_]+", name):
            continue
        path = f"/org/kde/ScreenBrightness/{name}"

        def prop(p):
            return subprocess.run([q, "org.kde.ScreenBrightness", path, f"org.kde.ScreenBrightness.Display.{p}"],
                                  capture_output=True, text=True, timeout=5).stdout.strip()
        try:
            mx, cur = int(prop("MaxBrightness")), int(prop("Brightness"))
        except ValueError:
            continue
        out[name] = {"label": prop("Label"), "value": round(cur * 100 / mx) if mx else 0, "max": mx}
    return out


def display_status() -> dict:
    outs = []
    for o in _kscreen().get("outputs", []):
        if not o.get("connected"):
            continue
        modes = {}
        for m in o.get("modes", []):
            key = (m["size"]["width"], m["size"]["height"], round(m["refreshRate"]))
            modes.setdefault(key, m["id"])  # one entry per resolution@Hz
        cur = next((m for m in o.get("modes", []) if m["id"] == o.get("currentModeId")), None)
        outs.append({"name": o["name"], "enabled": o.get("enabled", False), "scale": o.get("scale", 1),
                     "mode": o.get("currentModeId"),
                     "current": f'{cur["size"]["width"]}×{cur["size"]["height"]} @ {round(cur["refreshRate"])} Hz' if cur else "",
                     "modes": [{"id": i, "label": f"{w}×{h} @ {hz} Hz"}
                               for (w, h, hz), i in sorted(modes.items(), key=lambda kv: (-kv[0][0] * kv[0][1], -kv[0][2]))]})
    bright = [{"id": k, **v} for k, v in _brightness().items()]
    return {"outputs": outs, "scales": SCALES, "brightness": bright}


def display_set(output, scale=None, mode=None) -> dict:
    """Returns the previous values so the page can offer 'undo' (and undo by itself if not confirmed)."""
    o = next((x for x in _kscreen().get("outputs", []) if x["name"] == output and x.get("connected")), None)
    if not o:
        raise SysError("ไม่พบจอนี้")
    prev = {"output": output, "scale": o.get("scale"), "mode": o.get("currentModeId")}
    args = []
    if scale is not None:
        s = float(scale)
        if not 0.5 <= s <= 3:
            raise SysError("scale ต้องอยู่ระหว่าง 50% ถึง 300%")
        args.append(f"output.{output}.scale.{s:g}")
    if mode is not None:
        if str(mode) not in {m["id"] for m in o.get("modes", [])}:
            raise SysError("ไม่มีความละเอียดนี้ในจอนี้")
        args.append(f"output.{output}.mode.{mode}")
    if args:
        _run(["kscreen-doctor", *args], timeout=20)
    return {"ok": True, "previous": prev}


def brightness_set(display, percent) -> dict:
    b = _brightness()
    if display not in b:
        raise SysError("ปรับความสว่างจอนี้ไม่ได้")
    p = max(1, min(int(percent), 100))
    q = shutil.which("qdbus6") or shutil.which("qdbus")
    _run([q, "org.kde.ScreenBrightness", f"/org/kde/ScreenBrightness/{display}",
          "org.kde.ScreenBrightness.Display.SetBrightness", str(round(b[display]["max"] * p / 100)), "0"])
    return {"ok": True}


# ---- Keyboard: which key switches EN / TH ----------------------------------
# value -> xkb options. caps_toggle: Caps Lock switches language, Shift+Caps Lock is the real Caps Lock.
LANG_KEYS = {
    "alt_shift": "grp:alt_shift_toggle",
    "caps": "grp:caps_toggle",
    "both": "grp:alt_shift_toggle,grp:caps_toggle",
}


def keyboard_status() -> dict:
    opts = _run(["kreadconfig6", "--file", "kxkbrc", "--group", "Layout", "--key", "Options"], check=False).strip()
    have = {o for o in opts.split(",") if o.startswith("grp:")}
    cur = next((k for k, v in LANG_KEYS.items() if set(v.split(",")) == have), "other" if have else "alt_shift")
    return {"lang_key": cur, "options": opts}


def keyboard_set(lang_key) -> dict:
    if lang_key not in LANG_KEYS:
        raise SysError("ไม่รู้จักปุ่มสลับภาษานี้")
    opts = _run(["kreadconfig6", "--file", "kxkbrc", "--group", "Layout", "--key", "Options"], check=False).strip()
    keep = [o for o in opts.split(",") if o and not o.startswith("grp:")]  # keep the user's other xkb options
    new = ",".join(keep + LANG_KEYS[lang_key].split(","))
    w = ["kwriteconfig6", "--file", "kxkbrc", "--group", "Layout", "--key"]
    _run([*w, "Options", new])
    _run([*w, "ResetOldOptions", "--type", "bool", "true"])
    _run([*w, "Use", "--type", "bool", "true"])
    if not _run(["kreadconfig6", "--file", "kxkbrc", "--group", "Layout", "--key", "LayoutList"], check=False).strip():
        _run([*w, "LayoutList", "us,th"])
    # KWin re-reads kxkbrc on this signal (what KDE's own keyboard page sends)
    _run(["dbus-send", "--session", "--type=signal", "/Layouts", "org.kde.keyboard.reloadConfig"], check=False)
    return {"ok": True, "options": new}
