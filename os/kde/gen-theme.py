#!/usr/bin/env python3
"""Generate the T3 icon theme (dock tiles) and the T3 window decoration (Aurorae,
red/yellow/green buttons) from the T3 Desktop design. Re-run after changing a colour:
    python3 os/kde/gen-theme.py
Writes os/kde/icons-theme/T3/ and os/kde/aurorae/T3/ (installed by os/install.sh)."""
import json
from pathlib import Path

K = Path(__file__).resolve().parent

# ---- dock tiles: icon name(s) -> (tile colour, glyph colour, 24px stroke path) -------------
# Only T3's own and the system apps get a T3 tile; other apps (Chrome, VS Code, Arduino, KiCad, ...)
# keep their real logo, which is easier to recognise.
TILES = {
    ("t3-apps",): ("#3a3d42", "#e6e8ea", "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z"),
    ("org.kde.dolphin", "system-file-manager"): ("#2f6fb3", "#ffffff", "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"),
    ("utilities-terminal", "org.kde.konsole"): ("#17181a", "#56d364", "M5 7l5 5-5 5M12 18h7"),
    ("t3-bench",): ("#1f6f35", "#ffffff", "M7 7h10v10H7zM9 3v4M15 3v4M9 17v4M15 17v4M3 9h4M3 15h4M17 9h4M17 15h4"),
    ("t3-scope",): ("#15181a", "#3fb950", "M3 12h3l2-6 4 12 3-9 2 3h4"),
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
    for old in apps.glob("*.svg"):      # drop tiles no longer in TILES
        old.unlink()
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


SHADOW = 20                   # px of soft shadow around every window (Aurorae "padding")
SHADOW_A = {"decoration": 0.42, "decoration-inactive": 0.24}   # darkest, right at the window edge
CW, TH = SHADOW + R, SHADOW + TITLE_H   # corner tile width, top row height


def frame(prefix, fill):
    """FrameSvg pieces for one state: rounded dark title bar on top, no side/bottom border (apps fill
    the window), and a soft shadow all round so windows stand off the wallpaper and each other.
    Left/right pieces are drawn once and mirrored."""
    a, P = SHADOW_A[prefix], SHADOW
    o, defs = [], []
    gid = lambda n: f"{prefix}-g-{n}"

    def lin(name, x1, y1, x2, y2):          # fades from transparent (x1,y1) to shadow (x2,y2)
        defs.append(f'<linearGradient id="{gid(name)}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
                    f'<stop offset="0" stop-color="#000" stop-opacity="0"/>'
                    f'<stop offset="1" stop-color="#000" stop-opacity="{a}"/></linearGradient>')

    def rad(name, cx, cy, inner):           # corner: shadow at the centre, fading out
        defs.append(f'<radialGradient id="{gid(name)}" cx="{cx}" cy="{cy}" r="1" fx="{cx}" fy="{cy}">'
                    f'<stop offset="{inner:.3f}" stop-color="#000" stop-opacity="{a}"/>'
                    f'<stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>')

    lin("h", 0, 0, 1, 0)        # left edge
    lin("v", 0, 0, 0, 1)        # top edge
    lin("vb", 0, 1, 0, 0)       # bottom edge
    rad("tl", 1, 1, R / CW)     # top-left corner (around the rounded title corner)
    rad("bl", 1, 0, 0)          # bottom-left corner
    f = lambda n: f'url(#{gid(n)})'

    def add(name, x, y, body, w=None):
        if w is not None:   # mirrored copy for the right side
            body = f'<g transform="translate({w} 0) scale(-1 1)">{body}</g>'
        o.append(f'<g id="{prefix}-{name}" transform="translate({x} {y})">{body}</g>')

    topleft = (f'<rect width="{CW}" height="{CW}" fill="{f("tl")}"/>'
               f'<rect y="{CW}" width="{P}" height="{TH - CW}" fill="{f("h")}"/>'
               f'<path d="M{P} {TH}V{P + R}A{R} {R} 0 0 1 {P + R} {P}H{CW}V{TH}z" fill="{fill}"/>')
    left = f'<rect width="{P}" height="10" fill="{f("h")}"/><rect x="{P}" width="{R}" height="10" fill="none"/>'
    bottomleft = (f'<rect width="{P}" height="{P}" fill="{f("bl")}"/>'
                  f'<rect x="{P}" width="{R}" height="{P}" fill="{f("vb")}"/>')
    add("topleft", 0, 0, topleft)
    add("top", 40, 0, f'<rect width="10" height="{P}" fill="{f("v")}"/>'
                      f'<rect y="{P}" width="10" height="{TITLE_H}" fill="{fill}"/>')
    add("topright", 60, 0, topleft, CW)
    add("left", 0, 70, left)
    add("center", 40, 70, '<rect width="10" height="10" fill="none"/>')
    add("right", 60, 70, left, CW)
    add("bottomleft", 0, 90, bottomleft)
    add("bottom", 40, 90, f'<rect width="10" height="{P}" fill="{f("vb")}"/>')
    add("bottomright", 60, 90, bottomleft, CW)
    return "<defs>" + "".join(defs) + "</defs>\n" + "\n".join(o)


def maximized(prefix, fill, y):
    """Maximized windows: a plain solid title bar, square corners, no shadow. Without these pieces
    Aurorae draws the normal frame with no borders, which leaves the title bar see-through."""
    names = ["topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright"]
    return "\n".join(f'<rect id="{prefix}-{n}" x="{(i % 3) * 12}" y="{y + (i // 3) * 6}" '
                      f'width="10" height="4" fill="{fill}"/>' for i, n in enumerate(names))


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
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="280" viewBox="0 0 100 280">\n'
        + frame("decoration", ACTIVE) + "\n"
        + f'<g transform="translate(0 120)">{frame("decoration-inactive", INACTIVE)}</g>' + "\n"
        + maximized("decoration-maximized", ACTIVE, 240) + "\n"
        + maximized("decoration-maximized-inactive", INACTIVE, 260) + "\n</svg>\n")
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
BorderLeft=0
BorderRight=0
BorderBottom=0
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
TitleEdgeTopMaximized=0
TitleEdgeBottomMaximized=0
TitleEdgeLeftMaximized=12
TitleEdgeRightMaximized=12
ButtonMarginTopMaximized={(TITLE_H - 14) // 2}
PaddingTop={SHADOW}
PaddingBottom={SHADOW}
PaddingLeft={SHADOW}
PaddingRight={SHADOW}
""")


# ---- Plasma theme (desktoptheme T3) ---------------------------------------------------------------
# Only what T3 draws differently from Breeze Dark; every other piece falls back to the default theme.
#   panel-background: dock and menu bar with round corners (floating dock = a rounded island)
#   tasks:            no box behind open apps; a short bar under the icon (green = the app in front),
#                     a soft rounded highlight on hover
DOCK_R, DOCK_FILL, DOCK_EDGE = 18, "#1e1f22", "#ffffff"


def rounded(prefix, ox, oy, R, fill, op, edge_op=0.0, E=10):
    """FrameSvg pieces of a rounded rectangle, each drawn on its own (no clipping: Qt sizes an
    element by what is drawn in it). Corners R x R, edges E long, placed in a grid at (ox, oy)."""
    pid = (prefix + "-") if prefix else ""
    f = f'fill="{fill}" fill-opacity="{op}"'
    st = f'fill="none" stroke="#ffffff" stroke-opacity="{edge_op}" stroke-width="1"' if edge_op else ""
    corner = (f'<path d="M{R} {R}H0A{R} {R} 0 0 1 {R} 0z" {f}/>'
              + (f'<path d="M0.5 {R}A{R - .5} {R - .5} 0 0 1 {R} 0.5" {st}/>' if st else ""))
    top = (f'<rect width="{E}" height="{R}" {f}/>'
           + (f'<path d="M0 0.5H{E}" {st}/>' if st else ""))
    G = R + E + 4                                    # grid pitch
    def put(name, col, row, body, rot=0, w=R, h=R):
        x, y = ox + col * G, oy + row * G
        if rot:   # rotate the drawing about its own box so it stays at (x, y)
            body = f'<g transform="rotate({rot} {w / 2} {h / 2})">{body}</g>'
        return f'<g id="{pid}{name}" transform="translate({x} {y})">{body}</g>'
    side = (f'<rect width="{R}" height="{E}" {f}/>' + (f'<path d="M0.5 0V{E}" {st}/>' if st else ""))
    parts = [
        put("topleft", 0, 0, corner),
        put("top", 1, 0, top, w=E, h=R),
        put("topright", 2, 0, corner, 90),
        put("left", 0, 1, side, w=R, h=E),
        put("center", 1, 1, f'<rect width="{E}" height="{E}" {f}/>'),
        put("right", 2, 1, f'<g transform="translate({R} {E}) rotate(180)">{side}</g>'),
        put("bottomleft", 0, 2, corner, 270),
        put("bottom", 1, 2, f'<g transform="translate({E} {R}) rotate(180)">{top}</g>'),
        put("bottomright", 2, 2, corner, 180),
    ]
    return "\n".join(parts)


def bar_frame(prefix, ox, oy, SIDE, BAR, color, op, E=10):
    """Open-app indicator: transparent frame whose stretched bottom edge is the bar. The bottom
    corners are SIDE wide and see-through, so the bar is the item width minus 2 x SIDE, centred."""
    clear = 'fill="#000" fill-opacity="0"'
    def g(name, x, y, w, h, body=None):
        return (f'<g id="{prefix}-{name}" transform="translate({ox + x} {oy + y})">'
                f'{body or f"<rect width=\"{w}\" height=\"{h}\" {clear}/>"}</g>')
    bar = f'<rect width="{E}" height="{BAR}" fill="{color}" fill-opacity="{op}"/>'
    return "\n".join([
        g("topleft", 0, 0, SIDE, 1), g("top", 30, 0, E, 1), g("topright", 45, 0, SIDE, 1),
        g("left", 0, 5, SIDE, E), g("center", 30, 5, E, E), g("right", 45, 5, SIDE, E),
        g("bottomleft", 0, 20, SIDE, BAR), g("bottom", 30, 20, E, BAR, bar), g("bottomright", 45, 20, SIDE, BAR),
    ])


def desktoptheme():
    out = K / "desktoptheme" / "T3"
    (out / "widgets").mkdir(parents=True, exist_ok=True)
    (out / "metadata.json").write_text(json.dumps({
        "KPlugin": {"Id": "T3", "Name": "T3", "Description": "T3: Breeze Dark with a rounded dock",
                    "Authors": [{"Name": "T3"}], "License": "GPL-2.0+", "Version": "1.0",
                    "Website": "https://github.com/tawinkanthasa/T3OS"},
        "X-Plasma-API": "5.0"}, indent=2) + "\n")
    (out / "plasmarc").write_text("[ContrastEffect]\nenabled=true\ncontrast=0.2\nintensity=0.6\nsaturation=1.6\n\n"
                                  "[AdaptiveTransparency]\nenabled=true\n")

    # panel background: rounded, faint light edge
    R = DOCK_R
    hints = "".join(f'<rect id="{n}" x="{300 + i * 12}" y="0" width="{w}" height="{h}" fill="#000" fill-opacity="0"/>'
                    for i, (n, w, h) in enumerate([("hint-top-margin", 1, 2), ("hint-bottom-margin", 1, 2),     # thin menu bar
                                                   ("hint-left-margin", 4, 1), ("hint-right-margin", 4, 1),
                                                   ("thick-hint-top-margin", 1, 10), ("thick-hint-bottom-margin", 1, 10),   # dock
                                                   ("thick-hint-left-margin", 4, 1), ("thick-hint-right-margin", 4, 1),
                                                   ("hint-stretch-borders", 1, 1)]))
    (out / "widgets" / "panel-background.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="420" height="120" viewBox="0 0 420 120">\n'
        + rounded("", 0, 0, R, DOCK_FILL, 0.86, 0.08) + "\n"
        + hints + "\n</svg>\n")      # no mask-*: Plasma then takes the blur shape from the drawing itself

    # tasks: a short bar under each open app (green = the one in front); a soft rounded box on hover
    SIDE, BAR = 22, 3
    states = [("normal", "#9aa0a6", 0.9), ("focus", "#3fb950", 1), ("minimized", "#9aa0a6", 0.45),
              ("attention", "#d29922", 1)]
    parts = [bar_frame(n, i * 80, 0, SIDE, BAR, c, o) for i, (n, c, o) in enumerate(states)]
    parts.append(rounded("hover", 0, 40, 12, "#ffffff", 0.10))
    margins = "".join(f'<rect id="{st}-hint-{side}-margin" x="{340 + i * 6}" y="{40 + j * 6}" width="5" height="5" '
                      f'fill="#000" fill-opacity="0"/>'
                      for j, st in enumerate(["normal", "focus", "minimized", "attention", "hover"])
                      for i, side in enumerate(["top", "bottom", "left", "right"]))
    margins += '<rect id="hint-stretch-borders" x="390" y="110" width="1" height="1" fill="#000" fill-opacity="0"/>'
    (out / "widgets" / "tasks.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="120" viewBox="0 0 400 120">\n'
        + "\n".join(parts) + "\n" + margins + "\n</svg>\n")


if __name__ == "__main__":
    icon_theme()
    aurorae()
    desktoptheme()
    print("ok:", K / "icons-theme" / "T3", K / "aurorae" / "T3")
