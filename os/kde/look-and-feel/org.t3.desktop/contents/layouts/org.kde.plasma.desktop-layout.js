// T3 default desktop: menu bar on top, floating dock at the bottom (Mac-style layout).
// Runs once for a new user (LookAndFeelPackage=org.t3.desktop in /etc/xdg/kdeglobals),
// or again from System Settings > Global Theme > T3 with "Desktop and window layout" ticked.

var T3 = "/usr/share/t3";

// wallpaper on every screen
desktopsForActivity(currentActivity()).forEach(function (d) {
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file:///usr/share/wallpapers/T3/");
});

// ---- top: menu bar ----
var bar = new Panel;
bar.location = "top";
bar.height = Math.round(gridUnit * 1.6);
bar.floating = false;
bar.hiding = "dodgewindows";                                // tucks away under a maximised window; touch the top edge to bring it back

var menu = bar.addWidget("org.kde.plasma.kickoff");        // T3 menu: apps, places, sleep/restart/shut down
menu.currentConfigGroup = ["General"];
menu.writeConfig("icon", "t3-logo");
menu.writeConfig("favoritesDisplay", "1");                  // list, not grid
// first page of the T3 menu; "รีสตาร์ทเข้า Windows" restarts into Windows once (asks first)
menu.writeConfig("favorites", ["preferred://browser", "applications:org.kde.dolphin.desktop",
    "applications:org.kde.discover.desktop", "applications:t3.settings.desktop",
    "applications:t3.windows.desktop"].join(","));

bar.addWidget("org.kde.plasma.appmenu");                    // the focused app's menus (File, Edit, ...)
bar.addWidget("org.kde.plasma.panelspacer");
bar.addWidget("org.t3.boards");                             // ESP32 ● Pico ● claude ●
bar.addWidget("org.kde.plasma.systemtray");                 // Wi-Fi, sound, Bluetooth, battery, EN/TH
var clock = bar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", "true");
clock.writeConfig("dateDisplayFormat", "BesideTime");
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd d MMM");          // ส. 22 พ.ย.
clock.writeConfig("use24hFormat", "2");

// ---- bottom: floating dock: [music] apps | trash [Control Center] ----
var dock = new Panel;
dock.location = "bottom";
dock.height = Math.round(gridUnit * 3.1);                    // about 56 px: icons about half the dock height
dock.lengthMode = "fit";
dock.alignment = "center";
dock.hiding = "dodgewindows";                               // slides away when a window touches it
dock.floating = true;

dock.addWidget("org.t3.media");                             // takes no room until music plays, then the dock grows open
var grid = dock.addWidget("org.kde.plasma.kickerdash");     // full-screen app grid
grid.currentConfigGroup = ["General"];
grid.writeConfig("icon", "t3-apps");

var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:google-chrome.desktop",
    "applications:com.microsoft.VSCode.desktop",               // VS Code from Microsoft's apt repo (t3-get vscode)
    "applications:org.kde.konsole.desktop",
    "applications:t3.bench.desktop",
    "applications:t3.scope.desktop",
    "applications:cc.arduino.IDE2.desktop",
    "applications:org.kicad.kicad.desktop",
    "applications:org.kde.discover.desktop",
    "applications:t3.settings.desktop"                       // T3 Settings (KDE's full one is linked inside it)
].join(","));
tasks.writeConfig("groupingStrategy", "1");                 // one icon per app
tasks.writeConfig("indicateAudioStreams", "true");
tasks.writeConfig("iconSpacing", "0");                       // icons close together, like the design

dock.addWidget("org.kde.plasma.marginsseparator");
dock.addWidget("org.kde.plasma.trash");
dock.addWidget("org.t3.control");                           // Control Center: Wi-Fi, Bluetooth, brightness, sound...
