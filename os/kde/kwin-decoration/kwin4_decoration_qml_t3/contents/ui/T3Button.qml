// One T3 window button: a 14 px dot that, under the mouse, stretches into a capsule with its name.
import QtQuick
import org.kde.kwin.decoration

DecorationButton {
    id: button

    readonly property int dot: 14
    readonly property int pill: 18
    readonly property bool isClose: buttonType === DecorationOptions.DecorationButtonClose
    readonly property bool isMin: buttonType === DecorationOptions.DecorationButtonMinimize
    readonly property bool isMax: buttonType === DecorationOptions.DecorationButtonMaximizeRestore
    readonly property bool maxed: decoration.client.maximized

    readonly property color tint: isClose ? "#f85149" : isMin ? "#d29922" : "#3fb950"
    readonly property string word: isClose ? "Close" : isMin ? "Minimize" : maxed ? "Restore" : "Maximize"
    // marks drawn in a 10x10 box, dark on the coloured dot (same shapes as macOS)
    readonly property string mark: isClose ? '<path d="M2.6 2.6l4.8 4.8M7.4 2.6l-4.8 4.8" stroke="#000" stroke-width="1.6" stroke-linecap="round"/>'
        : isMin ? '<path d="M2 5h6" stroke="#000" stroke-width="1.6" stroke-linecap="round"/>'
        : maxed ? '<path d="M5.4 0.9v3.7h3.7zM4.6 9.1V5.4H0.9z" fill="#000"/>'
        : '<path d="M1.8 1.8h4.6L1.8 6.4zM8.2 8.2H3.6L8.2 3.6z" fill="#000"/>'

    readonly property bool open: hovered && enabled

    width: open ? body.openWidth : dot
    height: pill
    Behavior on width { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

    onHoveredChanged: root.buttonsHovered += hovered ? 1 : -1

    Rectangle {
        id: body
        readonly property int openWidth: 5 + 10 + 4 + label.implicitWidth + 9
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: button.open ? button.pill : button.dot
        radius: height / 2
        Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        color: !button.enabled ? "#3a3d42"
             : (decoration.client.active || root.showMarks) ? button.tint : "#4a4d52"
        Behavior on color { ColorAnimation { duration: 120 } }
        opacity: button.pressed ? 0.75 : 1
        clip: true

        Image {
            id: glyph
            x: button.open ? 5 : (button.dot - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 10; height: 10
            sourceSize: Qt.size(40, 40)
            source: "data:image/svg+xml;utf8," + encodeURIComponent(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" fill="none" opacity="0.62">'
                + button.mark + '</svg>')
            opacity: root.showMarks && button.enabled ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 110 } }
        }
        Text {
            id: label
            x: 5 + 10 + 4
            anchors.verticalCenter: parent.verticalCenter
            text: button.word
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: "#000000"
            opacity: button.open ? 0.72 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
    }
}
