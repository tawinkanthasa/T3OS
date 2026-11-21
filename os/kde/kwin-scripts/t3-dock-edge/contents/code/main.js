// T3 dock: touching the bottom screen edge ANYWHERE brings the dock up, floating OVER the windows.
// Plasma only reveals a hidden panel when the cursor hits the edge right under the panel, and the
// T3 dock is only as wide as its apps. So: on the bottom edge, switch the dock to "windows go below"
// for a moment (shown on top, reserves no space, so windows don't shrink; Plasma slides it in),
// and put its own hiding mode back once the cursor moves up away from the bottom.
var saved = "";          // the dock's hiding mode while we hold it up ("" = not holding)
var AWAY = 220;          // px above the bottom edge that counts as "left the dock"

function plasma(js, cb) {
    callDBus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", js, cb || function () {});
}

function bottomPanels(body) {
    return "panels().forEach(function(p){if(p.location=='bottom'){" + body + "}});";
}

registerScreenEdge(KWin.ElectricBottom, function () {
    if (saved) return;
    plasma(bottomPanels("print(p.hiding);"), function (mode) {
        mode = String(mode || "").trim();
        // only Plasma's own modes (the value is put back into a script later); "none" = always visible already
        if (["autohide", "dodgewindows"].indexOf(mode) < 0 || saved) return;
        saved = mode;
        plasma(bottomPanels("p.hiding='windowsgobelow';"));
    });
    return true;
});

workspace.cursorPosChanged.connect(function () {
    if (!saved) return;
    var pos = workspace.cursorPos;
    var area = workspace.clientArea(KWin.FullScreenArea, workspace.screenAt(pos), workspace.currentDesktop);
    if (pos.y < area.y + area.height - AWAY) {
        var mode = saved;
        saved = "";
        plasma(bottomPanels("p.hiding='" + mode + "';"));
    }
});
