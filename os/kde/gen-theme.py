#!/usr/bin/env python3
"""Generate the T3 icon theme (dock tiles) and the T3 window decoration (Aurorae,
red/yellow/green buttons) from the T3 Desktop design. Re-run after changing a colour:
    python3 os/kde/gen-theme.py
Writes os/kde/icons-theme/T3/ and os/kde/aurorae/T3/ (installed by os/install.sh)."""
from pathlib import Path

K = Path(__file__).resolve().parent

# ---- dock tiles: icon name(s) -> (tile colour, glyph colour, 24px stroke path) -------------
TILES = {
    ("t3-apps",): ("#3a3d42", "#e6e8ea", "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z"),
    ("org.kde.dolphin", "system-file-manager"): ("#2f6fb3", "#ffffff", "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"),
    ("google-chrome",): ("#e8eaed", "#1b1c1f", "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18"),
    ("vscode", "code", "com.visualstudio.code"): ("#1f5fa8", "#ffffff", "M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16"),
    ("utilities-terminal", "org.kde.konsole"): ("#17181a", "#56d364", "M5 7l5 5-5 5M12 18h7"),
    ("t3-bench",): ("#1f6f35", "#ffffff", "M7 7h10v10H7zM9 3v4M15 3v4M9 17v4M15 17v4M3 9h4M3 15h4M17 9h4M17 15h4"),
    ("t3-scope",): ("#15181a", "#3fb950", "M3 12h3l2-6 4 12 3-9 2 3h4"),
    ("cc.arduino.IDE2", "arduino"): ("#0f7c7e", "#ffffff", "M4 6h16v12H4zM12 15V9M9 12l3-3 3 3"),
    ("kicad", "org.kicad.kicad"): ("#33415c", "#ffffff", "M4 4h16v16H4zM8 8h3v3H8zM11 9.5h5v5M16 14.5v2"),
    ("plasmadiscover", "org.kde.discover"): ("#2b5797", "#ffffff", "M5 8h14l-1 12H6zM9 8V6a3 3 0 0 1 6 0v2"),
    ("preferences-system", "systemsettings"): ("#4a4d52", "#ffffff", "M4 7h16M4 12h16M4 17h16M9 5v4M15 10v4M11 15v4"),
    ("user-trash", "user-trash-full"): ("#3a3d42", "#e6e8ea", "M5 7h14M10 7V5h4v2M7 7l1 13h8l1-13"),
}


def tile(bg, fg, d):
    # 64px tile, 16px corners (the design's 52px/13px), glyph drawn on a 24px grid scaled to 36px
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="2" y="2" width="60" height="60" rx="15" fill="{bg}"/>
<rect x="2.5" y="2.5" width="59" height="59" rx="14.5" fill="none" stroke="#ffffff" stroke-opacity="0.1"/>
<g transform="translate(14 14) scale(1.5)" fill="none" stroke="{fg}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="{d}"/></g>
</svg>
'''


def icon_theme():
    out = K / "icons-theme" / "T3"
    apps = out / "scalable" / "apps"
    apps.mkdir(parents=True, exist_ok=True)
    for names, (bg, fg, d) in TILES.items():
        for n in names:
            (apps / f"{n}.svg").write_text(tile(bg, fg, d))
    (out / "index.theme").write_text("""[Icon Theme]
Name=T3
Comment=T3 dock tiles over Breeze Dark
Inherits=breeze-dark,hicolor
Directories=scalable/apps

[scalable/apps]
Size=64
MinSize=16
MaxSize=512
Type=Scalable
Context=Applications
""")


# ---- window decoration (Aurorae) --------------------------------------------------------------
TITLE_H, R = 34, 10           # title bar height, top corner radius
ACTIVE, INACTIVE, EDGE = "#26272a", "#1e1f22", "#3a3d42"
BUTTONS = {"close": "#f85149", "minimize": "#d29922", "maximize": "#3fb950", "restore": "#3fb950"}
GLYPH = {  # drawn on hover, 14px button
    "close": "M4.5 4.5l5 5M9.5 4.5l-5 5",
    "minimize": "M4 7h6",
    "maximize": "M4.5 9.5l5-5M6 4.5h3.5V8",
    "restore": "M9.5 4.5l-5 5M8 9.5H4.5V6",
}


def frame(prefix, fill):
    """FrameSvg pieces for one state: rounded top corners, flat 1px sides and bottom."""
    o = []
    add = lambda name, x, y, w, h, body: o.append(
        f'<g id="{prefix}-{name}" transform="translate({x} {y})">{body}</g>')
    # top row (title bar)
    add("topleft", 0, 0, R, TITLE_H,
        f'<path d="M0 {R}A{R} {R} 0 0 1 {R} 0V{TITLE_H}H0z" fill="{fill}"/>')
    add("top", 20, 0, 10, TITLE_H, f'<rect width="10" height="{TITLE_H}" fill="{fill}"/>')
    add("topright", 40, 0, R, TITLE_H,
        f'<path d="M0 0A{R} {R} 0 0 1 {R} {R}V{TITLE_H}H0z" fill="{fill}"/>')
    # sides and bottom: a 1px hairline in the edge colour
    add("left", 0, 50, 1, 10, f'<rect width="1" height="10" fill="{EDGE}"/>')
    add("center", 20, 50, 10, 10, f'<rect width="10" height="10" fill="{fill}" fill-opacity="0"/>')
    add("right", 40, 50, 1, 10, f'<rect width="1" height="10" fill="{EDGE}"/>')
    add("bottomleft", 0, 70, 1, 1, f'<rect width="1" height="1" fill="{EDGE}"/>')
    add("bottom", 20, 70, 10, 1, f'<rect width="10" height="1" fill="{EDGE}"/>')
    add("bottomright", 40, 70, 1, 1, f'<rect width="1" height="1" fill="{EDGE}"/>')
    return "\n".join(o)


def button(kind):
    c = BUTTONS[kind]
    states = {
        "active": (c, None), "hover": (c, "#4d0d08"), "pressed": (c, "#000000"),
        "inactive": ("#4a4d52", None), "deactivated": ("#3a3d42", None),
    }
    parts = []
    for i, (state, (fill, glyph)) in enumerate(states.items()):
        g = (f'<path d="{GLYPH[kind]}" fill="none" stroke="{glyph}" stroke-opacity="0.75" '
             f'stroke-width="1.4" stroke-linecap="round"/>') if glyph else ""
        op = ' fill-opacity="0.8"' if state == "pressed" else ""
        parts.append(f'<g id="{state}-center" transform="translate({i * 20} 0)">'
                     f'<rect width="14" height="14" fill="none"/>'
                     f'<circle cx="7" cy="7" r="6.5" fill="{fill}"{op}/>{g}</g>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="14" viewBox="0 0 100 14">\n'
            + "\n".join(parts) + "\n</svg>\n")


def aurorae():
    out = K / "aurorae" / "T3"
    out.mkdir(parents=True, exist_ok=True)
    (out / "decoration.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="60" height="80" viewBox="0 0 60 80">\n'
        + frame("decoration", ACTIVE) + "\n" + frame("decoration-inactive", INACTIVE) + "\n</svg>\n")
    for kind in BUTTONS:
        (out / f"{kind}.svg").write_text(button(kind))
    (out / "metadata.desktop").write_text("""[Desktop Entry]
Name=T3
Comment=T3 window frame: dark title bar, red/yellow/green buttons
X-KDE-PluginInfo-Name=T3
X-KDE-PluginInfo-Author=T3
X-KDE-PluginInfo-Version=1.0
X-KDE-PluginInfo-License=GPL
""")
    (out / "T3rc").write_text(f"""[General]
ActiveTextColor=201,205,209
InactiveTextColor=120,125,130
TitleAlignment=Center
TitleVerticalAlignment=Center
Animation=180
Shadow=true
HaloActive=false
HaloInactive=false

[Layout]
BorderLeft=1
BorderRight=1
BorderBottom=1
TitleEdgeTop=0
TitleEdgeBottom=0
TitleEdgeLeft=12
TitleEdgeRight=12
TitleBorderLeft=8
TitleBorderRight=8
TitleHeight={TITLE_H}
ButtonWidth=14
ButtonHeight=14
ButtonSpacing=8
ButtonMarginTop={(TITLE_H - 14) // 2}
ExplicitButtonSpacer=10
PaddingTop=0
PaddingBottom=0
PaddingLeft=0
PaddingRight=0
""")


if __name__ == "__main__":
    icon_theme()
    aurorae()
    print("ok:", K / "icons-theme" / "T3", K / "aurorae" / "T3")
