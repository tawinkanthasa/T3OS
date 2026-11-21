// Menu-bar widget: "ESP32 ●  Pico ●   claude ●" from benchd (127.0.0.1:7300/api/status).
// Green dot = connected, red = a recent alert (brownout, panic...). Click opens T3 Bench.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root
    property var boards: ({ text: "…", tooltip: "", class: "none" })
    property var ai: ({ text: "", tooltip: "", class: "ok" })
    property bool up: false

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipMainText: up ? "T3 Bench" : "T3 Bench: benchd ไม่ทำงาน"
    toolTipSubText: (boards.tooltip || "ไม่มีบอร์ดเสียบอยู่") + (ai.tooltip ? "\nLocal AI: " + ai.tooltip : "")
                    + "\nคลิกเพื่อเปิด Bench"

    function poll() {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            if (x.status === 200) {
                try {
                    var j = JSON.parse(x.responseText);
                    root.boards = j.boards; root.ai = j.ai; root.up = true;
                    return;
                } catch (e) {}
            }
            root.up = false;
        };
        x.open("GET", "http://127.0.0.1:7300/api/status");
        x.send();
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.poll() }

    P5Support.DataSource {
        id: run
        engine: "executable"
        onNewData: (source) => disconnectSource(source)
    }

    fullRepresentation: MouseArea {
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: run.connectSource("/usr/share/t3/bin/t3-open bench")

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            PC3.Label {
                text: root.up ? root.boards.text : "bench ✕"
                color: !root.up || root.boards.class === "alert" ? Kirigami.Theme.negativeTextColor
                     : root.boards.class === "ok" ? Kirigami.Theme.positiveTextColor
                     : Kirigami.Theme.disabledTextColor
            }
            PC3.Label {
                visible: root.up && root.ai.text !== ""
                text: root.ai.text
                color: root.ai.class === "down" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                opacity: 0.85
            }
        }
    }
}
