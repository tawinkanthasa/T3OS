// T3 Assistant button at the left end of the dock, with Meta+Space (only if it isn't there yet)
panels().forEach(function (p) {
    if (p.location !== "bottom") return;
    var widgets = p.widgets();
    if (widgets.some(function (w) { return w.type === "org.t3.assistant"; })) return;
    p.currentConfigGroup = ["General"];
    var order = String(p.readConfig("AppletOrder", "") || "");
    var others = order ? order.split(";") : widgets.map(function (w) { return w.id; });
    var w = p.addWidget("org.t3.assistant");
    w.globalShortcut = "Meta+Space";
    p.writeConfig("AppletOrder", [w.id].concat(others).join(";"));
});
