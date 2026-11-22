// T3 Assistant: the button at the left end of the dock (or Meta+Space). A sheet slides in at the left
// edge of the screen and stays there next to your work until you close it (Esc, ✕, the button again).
//
// It talks to whatever AI server the user set (Ollama, LM Studio, llama.cpp ... anything with the
// OpenAI chat API) and gives the AI "tools": fixed, read-only checks of this PC (temperatures, disk,
// errors, boot time ...) that run by themselves, and run_command, which shows the exact command and
// waits for the user to press Run. Nothing changes on the machine without that click.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root
    Plasmoid.icon: "t3-assistant"
    toolTipMainText: "T3 Assistant"
    toolTipSubText: "Ask about this PC (Meta+Space)"
    preferredRepresentation: compactRepresentation
    // Plasma only shows the dock button when the applet also has a popup; ours is the sheet below, so
    // this one stays empty and never opens
    fullRepresentation: Item { Layout.preferredWidth: 1; Layout.preferredHeight: 1 }
    activationTogglesExpanded: false
    onExpandedChanged: if (expanded) Qt.callLater(() => { root.expanded = false; })

    // ------------------------------------------------------------------ open / close
    property bool open: false
    function toggle() { open = !open; }
    Plasmoid.onActivated: toggle()

    // ------------------------------------------------------------------ settings
    readonly property string base: (Plasmoid.configuration.serverUrl || "").trim().replace(/\/+$/, "")
    readonly property string modelName: (Plasmoid.configuration.model || "").trim()
    readonly property string apiKey: (Plasmoid.configuration.apiKey || "").trim()

    // ------------------------------------------------------------------ running commands
    property int seq: 0
    property var waiting: ({})
    P5Support.DataSource {
        id: sh
        engine: "executable"
        onNewData: (source, data) => {
            const cb = root.waiting[source];
            delete root.waiting[source];
            disconnectSource(source);
            if (cb) cb((data["stdout"] || "") + (data["stderr"] ? "\n" + data["stderr"] : ""), data["exit code"]);
        }
    }
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    // run through sh; the "# n" tail keeps two runs of the same command apart
    function run(cmd, cb) {
        const src = "export LC_ALL=C.UTF-8 PATH=\"$PATH:/usr/share/t3/bin:/usr/sbin:/sbin:$HOME/.local/bin\"; " + cmd + " #" + (++seq);
        waiting[src] = cb;
        sh.connectSource(src);
    }
    function cut(s, n) { s = String(s).trim(); return s.length > n ? s.slice(0, n) + "\n…(cut)" : s; }

    // ------------------------------------------------------------------ the checks the AI may run by itself
    readonly property var checks: ({
        system_overview: { label: "system", desc: "This PC: Debian/T3 version, kernel, uptime, CPU, RAM, graphics card and driver, disks (ROTA=1 means a spinning hard disk), Secure Boot, desktop session.",
            cmd: ". /etc/os-release; echo \"$PRETTY_NAME\"; uname -r; uptime -p; lscpu | grep -E 'Model name|^CPU\\(s\\)'; free -h; nvidia-smi --query-gpu=name,driver_version,memory.used,memory.total --format=csv,noheader 2>/dev/null || lspci | grep -iE 'vga|3d'; lsblk -e7 -o NAME,SIZE,ROTA,FSTYPE,MOUNTPOINTS; mokutil --sb-state 2>/dev/null; echo \"session: $XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP\"" },
        temperatures: { label: "temperatures", desc: "CPU and GPU temperatures, GPU load, power and fan.",
            cmd: "sensors 2>/dev/null | grep -E '°C|RPM' | head -30; nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,fan.speed --format=csv 2>/dev/null" },
        top_processes: { label: "processes", desc: "Programs using the most CPU and the most memory right now.",
            cmd: "ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -12; echo; ps -eo pid,comm,rss --sort=-rss | head -10 | awk 'NR==1{print;next}{printf \"%s %s %.0f MB\\n\",$1,$2,$3/1024}'; echo; free -h" },
        disk_usage: { label: "disk space", desc: "Free space on every disk and the biggest folders in the user's home.",
            cmd: "df -h -x tmpfs -x devtmpfs -x efivarfs -x overlay; echo; du -xh --max-depth=1 \"$HOME\" 2>/dev/null | sort -h | tail -12; echo; du -sh \"$HOME/.cache\" /var/cache/apt 2>/dev/null" },
        recent_errors: { label: "errors", desc: "Errors logged since this boot, and services that failed.",
            cmd: "journalctl -b -p 3 --no-pager -q | tail -40; echo '--- failed services'; systemctl --failed --no-legend; systemctl --user --failed --no-legend" },
        boot_time: { label: "boot time", desc: "How long the last start-up took and what was slowest.",
            cmd: "systemd-analyze; systemd-analyze blame --no-pager | head -15; echo '--- after login'; systemd-analyze --user blame --no-pager 2>/dev/null | head -8" },
        network: { label: "network", desc: "Wi-Fi/Ethernet state, IP addresses, whether the internet and DNS answer.",
            cmd: "nmcli -t -f STATE,CONNECTIVITY general; nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device; ip -br addr; ping -c2 -W2 1.1.1.1 2>&1 | tail -2; getent hosts debian.org | head -1 || echo 'DNS: no answer'" },
        t3_doctor: { label: "T3 Doctor", desc: "T3's own health check of the usual problems (drivers, sound, Wi-Fi, updates, boot menu, clock ...), with fixes.",
            cmd: "t3-doctor 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'" },
        search_logs: { label: "logs", desc: "Search this boot's system log for a word (an app name, a device, an error message).",
            params: { text: { type: "string", description: "word or phrase to look for" } },
            make: a => "journalctl -b --no-pager -q | grep -i -F -- " + root.q(a.text || "") + " | tail -40" },
        package_info: { label: "package", desc: "Whether a program/package is installed and which version (apt, Flatpak).",
            params: { name: { type: "string", description: "package or program name" } },
            make: a => "dpkg -l " + root.q(a.name || "") + " 2>&1 | tail -3; apt-cache policy " + root.q(a.name || "") + " 2>&1 | head -4; flatpak list --columns=application,version 2>/dev/null | grep -i -F -- " + root.q(a.name || "") }
    })
    function toolSpecs() {
        const list = Object.keys(checks).map(k => ({ type: "function", function: {
            name: k, description: checks[k].desc,
            parameters: { type: "object", properties: checks[k].params || {}, required: Object.keys(checks[k].params || {}) } } }));
        list.push({ type: "function", function: {
            name: "run_command",
            description: "Run a shell command that changes something or that no other tool covers. The user sees the command and your reason and must press Run first. For admin rights put pkexec in front (never sudo: there is no terminal).",
            parameters: { type: "object", required: ["command", "reason"], properties: {
                command: { type: "string", description: "bash command line" },
                reason: { type: "string", description: "one short sentence, in the user's language, saying what it does and why" } } } } });
        return list;
    }
    readonly property string systemPrompt:
        "You are T3 Assistant, built into T3: Debian 13 with KDE Plasma 6 (Wayland), on the user's own PC. " +
        "Today is " + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".\n" +
        "- Reply in the user's language (usually Thai), short and plain, like a friend who knows computers. Markdown is fine.\n" +
        "- For anything about this PC, call the tools first and answer from what they return. Never guess numbers or invent results.\n" +
        "- To change something use run_command; the user must press Run. Use pkexec, not sudo. Say clearly when something touches booting, drivers, disks or deletes files, and how to undo it.\n" +
        "- T3 helpers you can suggest or run: t3-doctor (health check), t3-get <chrome|vscode|nvidia|claude|arduino|platformio|esp-idf|t3> (installs extras / updates T3), " +
        "t3-boot-set (which system starts by default), Timeshift restore points (snapshots).\n" +
        "- If a tool result shows nothing wrong, say so; don't pad the answer."

    // ------------------------------------------------------------------ the conversation
    ListModel { id: view }            // what's on screen: kind = me | ai | check | ask | note
    property var history: []          // what the AI sees (OpenAI messages)
    property bool thinking: false
    property bool noTools: false      // the model can't use tools: give it a snapshot instead
    property string snapshot: ""
    property int gen: 0               // bumped by "new chat" / stop, so late answers are dropped
    property int rounds: 0
    property var xhr: null
    property var calls: ({})          // tool-call id -> view row, while waiting for the user

    function say(kind, text, extra) {
        const row = Object.assign({ kind: kind, text: text || "", cmd: "", st: "", out: "", callId: "" }, extra || {});
        view.append(row);
        return view.count - 1;
    }
    function send(text) {
        text = text.trim();
        if (!text || thinking) return;
        if (!base) { stack.currentIndex = 1; return; }
        say("me", text);
        history.push({ role: "user", content: text });
        rounds = 0;
        ask();
    }
    function stop() {
        gen++;
        if (xhr) xhr.abort();
        thinking = false;
        say("note", "หยุดแล้ว");
    }
    function newChat() {
        gen++;
        if (xhr) xhr.abort();
        thinking = false; history = []; calls = ({}); view.clear();
    }
    function ask() {
        const my = gen;
        thinking = true;
        if (++rounds > 10) { thinking = false; say("note", "เช็คไปหลายรอบแล้วยังไม่จบ ลองถามให้แคบลงหน่อย"); return; }
        const body = { messages: [{ role: "system", content: systemPrompt + (noTools ? "\n\nThis PC right now:\n" + snapshot : "") }].concat(history),
                       temperature: 0.3, stream: false };
        if (modelName) body.model = modelName;
        if (!noTools) body.tools = toolSpecs();
        const r = new XMLHttpRequest();
        xhr = r;
        r.open("POST", base + "/chat/completions");
        r.setRequestHeader("Content-Type", "application/json");
        if (apiKey) r.setRequestHeader("Authorization", "Bearer " + apiKey);
        r.onreadystatechange = function () {
            if (r.readyState !== XMLHttpRequest.DONE || my !== gen) return;
            xhr = null;
            if (r.status === 0) { thinking = false; say("note", "ต่อ AI ไม่ได้ (" + base + ") ดูว่าเปิดเซิร์ฟเวอร์ AI อยู่ไหม หรือแก้ลิงก์ในตั้งค่า ⚙"); return; }
            if (r.status >= 400) {
                // some local models can't use tools: carry on without them, with a snapshot of the PC instead
                if (!noTools && /tool/i.test(r.responseText)) {
                    noTools = true;
                    run(checks.system_overview.cmd + "; " + checks.temperatures.cmd + "; " + checks.disk_usage.cmd, out => { snapshot = cut(out, 5000); rounds--; ask(); });
                    return;
                }
                thinking = false;
                say("note", "เซิร์ฟเวอร์ AI ตอบว่า error " + r.status + ": " + cut(r.responseText, 300));
                return;
            }
            let msg;
            try { msg = JSON.parse(r.responseText).choices[0].message; }
            catch (e) { thinking = false; say("note", "อ่านคำตอบจาก AI ไม่ออก: " + cut(r.responseText, 200)); return; }
            const content = String(msg.content || "").replace(/<think>[\s\S]*?<\/think>/g, "").trim();
            if (msg.tool_calls && msg.tool_calls.length && !noTools) {
                history.push({ role: "assistant", content: msg.content || "", tool_calls: msg.tool_calls });
                if (content) say("ai", content);
                handle(msg.tool_calls, my);
            } else {
                history.push({ role: "assistant", content: content });
                thinking = false;
                say("ai", content || "(ไม่มีคำตอบ)");
            }
        };
        r.send(JSON.stringify(body));
    }
    function handle(list, my) {
        let left = list.length;
        const done = (id, result) => {
            if (my !== gen) return;
            history.push({ role: "tool", tool_call_id: id, content: cut(result, 6000) });
            if (--left === 0) ask();
        };
        list.forEach((c, i) => {
            const id = c.id || ("call" + i);
            const name = c.function ? c.function.name : "";
            let a = {};
            try { a = typeof c.function.arguments === "string" ? JSON.parse(c.function.arguments || "{}") : (c.function.arguments || {}); } catch (e) {}
            if (name === "run_command") {
                const row = say("ask", a.reason || "", { cmd: a.command || "", st: "wait", callId: id });
                const cs = calls; cs[id] = { row: row, done: done }; calls = cs;
                thinking = false;           // waiting for the user, not for the AI
            } else if (checks[name]) {
                const ck = checks[name];
                const row = say("check", ck.label + (a.text || a.name ? ": " + (a.text || a.name) : ""), { st: "run" });
                run(ck.make ? ck.make(a) : ck.cmd, out => {
                    if (my !== gen) return;
                    view.setProperty(row, "st", "ok");
                    done(id, out || "(no output)");
                });
            } else {
                done(id, "There is no tool called " + name + ".");
            }
        });
    }
    function answer(row, yes) {
        const it = view.get(row);
        const c = calls[it.callId];
        if (!c || it.st !== "wait") return;
        thinking = true;
        if (!yes) {
            view.setProperty(row, "st", "no");
            c.done(it.callId, "The user chose not to run this command.");
            return;
        }
        view.setProperty(row, "st", "running");
        run("timeout 600 bash -c " + q(it.cmd) + " 2>&1; echo \"[exit $?]\"", out => {
            view.setProperty(row, "st", /\[exit 0\]\s*$/.test(out) ? "ok" : "fail");
            view.setProperty(row, "out", cut(out, 1500));
            c.done(it.callId, out);
        });
    }

    // ------------------------------------------------------------------ live numbers at the top
    property real cpu: 0
    property var lastCpu: null
    property string mem: "–"
    property real memFrac: 0
    property string gpuTemp: "–"
    property int disk: 0
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.open
        onTriggered: root.run("awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat; awk '/MemTotal|MemAvailable/{print $2}' /proc/meminfo; " +
                              "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo -; df --output=pcent / | tail -1", out => {
            const l = out.trim().split("\n");
            const [tot, idle] = l[0].split(" ").map(Number);
            if (root.lastCpu) root.cpu = Math.max(0, Math.min(1, 1 - (idle - root.lastCpu[1]) / Math.max(1, tot - root.lastCpu[0])));
            root.lastCpu = [tot, idle];
            const total = Number(l[1]), avail = Number(l[2]);
            root.memFrac = 1 - avail / total;
            root.mem = ((total - avail) / 1048576).toFixed(1) + "/" + Math.round(total / 1048576) + "G";
            root.gpuTemp = /^\d+$/.test((l[3] || "").trim()) ? l[3].trim() + "°C" : "–";
            root.disk = parseInt(l[4]) || 0;
        })
    }

    // ------------------------------------------------------------------ in the dock
    compactRepresentation: RowLayout {
        id: dockPart
        spacing: 0
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        MouseArea {
            id: btn
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            Layout.fillHeight: true
            Layout.preferredWidth: Math.max(Kirigami.Units.gridUnit * 2, dockPart.height)
            Layout.leftMargin: Kirigami.Units.smallSpacing
            onClicked: root.toggle()
            Rectangle {
                anchors.centerIn: parent
                width: Math.round(Math.min(parent.width, parent.height) * 0.85); height: width
                radius: Math.round(width * 0.3)
                color: root.open ? Qt.rgba(0.43, 0.36, 0.96, 0.32)
                     : btn.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                Behavior on color { ColorAnimation { duration: 150 } }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Math.round(parent.width * 0.62); height: width
                    source: "t3-assistant"
                }
            }
        }
    }

    // ------------------------------------------------------------------ the sheet at the left edge
    PlasmaCore.Dialog {
        id: sheet
        readonly property rect scr: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 1920, 1080)
        readonly property int gap: Kirigami.Units.largeSpacing
        readonly property int top: Math.round(Kirigami.Units.gridUnit * 1.6) + gap      // under the top bar
        visible: root.open
        location: PlasmaCore.Types.LeftEdge          // KWin slides it in from the left
        flags: Qt.WindowStaysOnTopHint
        hideOnWindowDeactivate: false                // stays open next to your work
        x: scr.x + gap
        y: scr.y + top
        onVisibleChanged: if (visible) { requestActivate(); input.forceActiveFocus(); } else root.open = false

        mainItem: Item {
            id: pane
            width: Kirigami.Units.gridUnit * 24
            height: sheet.scr.height - sheet.top - sheet.gap * 2
            Keys.onEscapePressed: root.open = false

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // title row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.smallSpacing * 2
                    Kirigami.Icon { source: "t3-assistant"; Layout.preferredWidth: Kirigami.Units.iconSizes.small; Layout.preferredHeight: Layout.preferredWidth }
                    PC3.Label { text: stack.currentIndex === 1 ? "T3 Assistant · Settings" : "T3 Assistant"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    PC3.ToolButton { icon.name: "list-add"; visible: stack.currentIndex === 0; onClicked: root.newChat()
                                     QQC2.ToolTip.text: "New chat"; QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: 500 }
                    PC3.ToolButton { icon.name: "configure"; checkable: true; checked: stack.currentIndex === 1
                                     onClicked: stack.currentIndex = stack.currentIndex === 1 ? 0 : 1
                                     QQC2.ToolTip.text: "AI server"; QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: 500 }
                    PC3.ToolButton { icon.name: "window-close"; onClicked: root.open = false
                                     QQC2.ToolTip.text: "Close (Esc)"; QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: 500 }
                }

                // live numbers
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing; Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.bottomMargin: Kirigami.Units.smallSpacing * 2
                    spacing: Kirigami.Units.largeSpacing
                    Gauge { name: "CPU"; value: Math.round(root.cpu * 100) + "%"; frac: root.cpu }
                    Gauge { name: "GPU"; value: root.gpuTemp; frac: (parseInt(root.gpuTemp) || 0) / 100 }
                    Gauge { name: "RAM"; value: root.mem; frac: root.memFrac }
                    Gauge { name: "Disk"; value: root.disk + "%"; frac: root.disk / 100 }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                StackLayout {
                    id: stack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.base ? 0 : 1

                    // ---------------- chat
                    ColumnLayout {
                        spacing: 0
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ListView {
                                id: chat
                                anchors.fill: parent
                                clip: true
                                spacing: Kirigami.Units.smallSpacing * 2
                                topMargin: Kirigami.Units.largeSpacing; bottomMargin: Kirigami.Units.largeSpacing
                                leftMargin: Kirigami.Units.largeSpacing; rightMargin: Kirigami.Units.largeSpacing
                                model: view
                                QQC2.ScrollBar.vertical: PC3.ScrollBar {}
                                delegate: Row_ {}
                                footer: Item {
                                    width: chat.width - chat.leftMargin - chat.rightMargin
                                    height: root.thinking ? Kirigami.Units.gridUnit * 1.6 : 0
                                    visible: root.thinking
                                    PC3.Label {
                                        id: dots
                                        property int n: 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "กำลังคิด" + ".".repeat(n + 1)
                                        opacity: 0.6
                                        Timer { running: root.thinking; interval: 400; repeat: true; onTriggered: dots.n = (dots.n + 1) % 3 }
                                    }
                                }
                                onCountChanged: Qt.callLater(() => chat.positionViewAtEnd())
                            }
                            // first look: things people ask
                            ColumnLayout {
                                visible: view.count === 0
                                anchors.centerIn: parent
                                width: parent.width - Kirigami.Units.gridUnit * 3
                                spacing: Kirigami.Units.smallSpacing * 2
                                PC3.Label { text: "ถามอะไรก็ได้เกี่ยวกับเครื่องนี้"; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
                                PC3.Label { text: "มันเช็คเครื่องให้จริงๆ และถามก่อนทุกครั้งที่จะแก้อะไร"; opacity: 0.6; wrapMode: Text.Wrap
                                            horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Kirigami.Units.smallSpacing * 2
                                    spacing: Kirigami.Units.smallSpacing
                                    Repeater {
                                        model: ["ทำไมเครื่องช้า", "การ์ดจอร้อนไหม", "ดิสก์เหลือเท่าไหร่", "วันนี้มี error อะไรบ้าง", "บูตช้าเพราะอะไร", "เน็ตมีปัญหาไหม"]
                                        delegate: PC3.Button { required property string modelData; text: modelData; onClicked: root.send(modelData) }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: Kirigami.Units.largeSpacing
                            PC3.TextField {
                                id: input
                                Layout.fillWidth: true
                                placeholderText: "ถามอะไรก็ได้เกี่ยวกับเครื่องนี้…"
                                onAccepted: { root.send(text); text = ""; }
                                Keys.onEscapePressed: root.open = false
                            }
                            PC3.Button {
                                icon.name: root.thinking ? "media-playback-stop" : "document-send"
                                onClicked: root.thinking ? root.stop() : (root.send(input.text), input.text = "")
                                QQC2.ToolTip.text: root.thinking ? "Stop" : "Send"; QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: 500
                            }
                        }
                    }

                    // ---------------- settings: the AI server
                    ColumnLayout {
                        id: settings
                        property var found: []
                        property string status: ""
                        spacing: Kirigami.Units.smallSpacing * 2
                        function test() {
                            status = "กำลังลอง…";
                            const r = new XMLHttpRequest();
                            r.open("GET", url.text.trim().replace(/\/+$/, "") + "/models");
                            if (key.text.trim()) r.setRequestHeader("Authorization", "Bearer " + key.text.trim());
                            r.onreadystatechange = function () {
                                if (r.readyState !== XMLHttpRequest.DONE) return;
                                if (r.status !== 200) { status = r.status === 0 ? "✗ ต่อไม่ได้: เปิดเซิร์ฟเวอร์ AI อยู่ไหม / ลิงก์ถูกไหม" : "✗ error " + r.status; found = []; return; }
                                try { found = JSON.parse(r.responseText).data.map(m => m.id); } catch (e) { found = []; }
                                status = "✓ ต่อได้ เจอ " + found.length + " โมเดล" + (found.length ? " กดเลือกด้านล่าง" : "");
                                if (!modelField.text && found.length) modelField.text = found[0];
                                save();
                            };
                            r.send();
                        }
                        function save() {
                            Plasmoid.configuration.serverUrl = url.text.trim();
                            Plasmoid.configuration.model = modelField.text.trim();
                            Plasmoid.configuration.apiKey = key.text.trim();
                        }
                        Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
                        PC3.Label { text: "วางลิงก์เซิร์ฟเวอร์ AI ของคุณเอง ตัวไหนก็ได้ที่ใช้ OpenAI API"; wrapMode: Text.Wrap; Layout.fillWidth: true
                                    Layout.leftMargin: Kirigami.Units.largeSpacing; Layout.rightMargin: Kirigami.Units.largeSpacing }
                        Field { title: "ลิงก์"; hint: "Ollama: http://localhost:11434/v1 · LM Studio: http://localhost:1234/v1"
                            PC3.TextField { id: url; Layout.fillWidth: true; text: Plasmoid.configuration.serverUrl; onEditingFinished: settings.save(); font.family: "monospace" } }
                        Field { title: "โมเดล"; hint: "เว้นว่างได้ถ้าเซิร์ฟเวอร์มีโมเดลเดียว"
                            PC3.TextField { id: modelField; Layout.fillWidth: true; text: Plasmoid.configuration.model; onEditingFinished: settings.save(); font.family: "monospace" } }
                        Flow {
                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.largeSpacing; Layout.rightMargin: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing
                            Repeater {
                                model: settings.found
                                delegate: PC3.Button { required property string modelData; text: modelData; checkable: true
                                    checked: modelField.text === modelData; onClicked: { modelField.text = modelData; settings.save(); } }
                            }
                        }
                        Field { title: "คีย์ (ถ้าเซิร์ฟเวอร์ต้องใช้)"; hint: "Ollama / LM Studio ไม่ต้องใส่"
                            PC3.TextField { id: key; Layout.fillWidth: true; text: Plasmoid.configuration.apiKey; echoMode: TextInput.Password; onEditingFinished: settings.save() } }
                        RowLayout {
                            Layout.leftMargin: Kirigami.Units.largeSpacing; Layout.rightMargin: Kirigami.Units.largeSpacing
                            PC3.Button { text: "ทดสอบและบันทึก"; icon.name: "network-connect"; onClicked: { settings.save(); settings.test(); } }
                            PC3.Label { text: settings.status; wrapMode: Text.Wrap; Layout.fillWidth: true
                                        color: settings.status.startsWith("✓") ? "#3fb950" : settings.status.startsWith("✗") ? "#f85149" : Kirigami.Theme.textColor }
                        }
                        PC3.Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.largeSpacing; Layout.rightMargin: Kirigami.Units.largeSpacing
                            Layout.topMargin: Kirigami.Units.largeSpacing
                            wrapMode: Text.Wrap; opacity: 0.6
                            text: "• การเช็คที่แค่อ่านข้อมูล (อุณหภูมิ ดิสก์ log) ทำเองได้เลย\n• อะไรที่แก้เครื่อง จะโชว์คำสั่งให้ดูแล้วรอคุณกด รัน ก่อน\n• ข้อมูลไม่ออกจากเครื่อง ถ้าลิงก์ชี้มาที่เครื่องตัวเอง (localhost)\n• เปิด/ปิด: Meta+Space หรือปุ่มซ้ายสุดของ dock"
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ pieces
    component Gauge: ColumnLayout {
        property string name
        property string value
        property real frac: 0
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 2
        PC3.Label { text: parent.name; opacity: 0.6; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        PC3.Label { text: parent.value; font.weight: Font.DemiBold; font.features: { "tnum": 1 }; elide: Text.ElideRight; Layout.fillWidth: true }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.1)
            Rectangle { width: parent.width * Math.max(0, Math.min(1, frac)); height: parent.height; radius: 2
                        color: frac > 0.85 ? "#f85149" : frac > 0.65 ? "#d29922" : "#3fb950"
                        Behavior on width { NumberAnimation { duration: 300 } } }
        }
    }

    component Field: ColumnLayout {
        property string title
        property string hint
        default property alias content: box.data
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing; Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: 2
        PC3.Label { text: parent.title; opacity: 0.7 }
        RowLayout { id: box; Layout.fillWidth: true }
        PC3.Label { text: parent.hint; opacity: 0.5; font.pointSize: Kirigami.Theme.smallFont.pointSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }

    // one line of the chat
    component Row_: Item {
        id: line
        required property int index
        required property string kind
        required property string text
        required property string cmd
        required property string st
        required property string out
        width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
        height: box.height

        Item {
            id: box
            width: parent.width
            height: line.kind === "me" ? me.height : line.kind === "ai" || line.kind === "note" ? ai.height
                  : line.kind === "check" ? check.height : card.height

            // you
            Rectangle {
                id: me
                visible: line.kind === "me"
                anchors.right: parent.right
                width: Math.min(parent.width * 0.85, meText.implicitWidth + Kirigami.Units.largeSpacing * 2)
                height: meText.implicitHeight + Kirigami.Units.smallSpacing * 3
                radius: Kirigami.Units.cornerRadius * 3
                color: "#1f3a5f"
                TextEdit {
                    id: meText
                    anchors.fill: parent; anchors.margins: Kirigami.Units.smallSpacing * 1.5
                    anchors.leftMargin: Kirigami.Units.largeSpacing; anchors.rightMargin: Kirigami.Units.largeSpacing
                    text: line.kind === "me" ? line.text : ""
                    textFormat: TextEdit.PlainText; wrapMode: Text.Wrap
                    readOnly: true; selectByMouse: true
                    color: Kirigami.Theme.textColor; font: Kirigami.Theme.defaultFont
                }
            }
            // the AI (Markdown), or a note from T3 itself
            TextEdit {
                id: ai
                visible: line.kind === "ai" || line.kind === "note"
                width: parent.width
                text: visible ? line.text : ""
                textFormat: line.kind === "ai" ? TextEdit.MarkdownText : TextEdit.PlainText
                wrapMode: Text.Wrap
                readOnly: true; selectByMouse: true
                color: Kirigami.Theme.textColor
                opacity: line.kind === "note" ? 0.65 : 1
                font: Kirigami.Theme.defaultFont
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            // a check it ran by itself
            Rectangle {
                id: check
                visible: line.kind === "check"
                width: checkRow.implicitWidth + Kirigami.Units.largeSpacing * 2
                height: Kirigami.Units.gridUnit * 1.3
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.05)
                border.color: Qt.rgba(1, 1, 1, 0.1)
                RowLayout {
                    id: checkRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle { width: 6; height: 6; radius: 3; color: line.st === "ok" ? "#3fb950" : "#d29922"
                                SequentialAnimation on opacity { running: line.st === "run"; loops: Animation.Infinite
                                    NumberAnimation { to: 0.2; duration: 400 } NumberAnimation { to: 1; duration: 400 } } }
                    PC3.Label { text: "เช็ค " + line.text; opacity: 0.75; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                }
            }
            // it wants to run a command: show it, wait for the user
            Rectangle {
                id: card
                visible: line.kind === "ask"
                width: parent.width
                height: cardCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.cornerRadius * 3
                color: line.st === "ok" ? Qt.rgba(0.25, 0.73, 0.31, 0.1) : line.st === "fail" ? Qt.rgba(0.97, 0.32, 0.29, 0.1) : Qt.rgba(0.82, 0.6, 0.13, 0.12)
                border.color: line.st === "ok" ? Qt.rgba(0.25, 0.73, 0.31, 0.4) : line.st === "fail" ? Qt.rgba(0.97, 0.32, 0.29, 0.4) : Qt.rgba(0.82, 0.6, 0.13, 0.45)
                ColumnLayout {
                    id: cardCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Kirigami.Units.largeSpacing }
                    spacing: Kirigami.Units.smallSpacing * 2
                    PC3.Label { text: line.text || "ขอรันคำสั่งนี้"; wrapMode: Text.Wrap; Layout.fillWidth: true; textFormat: Text.PlainText }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: cmdText.implicitHeight + Kirigami.Units.smallSpacing * 3
                        radius: Kirigami.Units.cornerRadius * 2
                        color: Qt.rgba(0, 0, 0, 0.3)
                        TextEdit {
                            id: cmdText
                            anchors.fill: parent; anchors.margins: Kirigami.Units.smallSpacing * 1.5
                            text: line.cmd; textFormat: TextEdit.PlainText; wrapMode: Text.WrapAnywhere
                            readOnly: true; selectByMouse: true
                            color: Kirigami.Theme.textColor; font.family: "monospace"; font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                    RowLayout {
                        visible: line.st === "wait"
                        PC3.Button { text: "รัน"; icon.name: "media-playback-start"; onClicked: root.answer(line.index, true) }
                        PC3.Button { text: "ไม่เอา"; flat: true; onClicked: root.answer(line.index, false) }
                    }
                    PC3.Label {
                        visible: line.st !== "wait"
                        opacity: 0.7
                        text: line.st === "running" ? "กำลังรัน… (ถ้ามีหน้าต่างขอรหัสผ่าน ใส่รหัสเครื่อง)"
                            : line.st === "no" ? "ไม่ได้รัน" : line.st === "ok" ? "✓ รันเสร็จ" : "✗ รันแล้วมีปัญหา"
                    }
                    PC3.Label {
                        visible: line.out !== "" && line.st !== "running"
                        Layout.fillWidth: true
                        text: line.out.split("\n").slice(-8).join("\n")
                        textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; maximumLineCount: 8; elide: Text.ElideRight
                        font.family: "monospace"; font.pointSize: Kirigami.Theme.smallFont.pointSize; opacity: 0.6
                    }
                }
            }
        }
    }
}
