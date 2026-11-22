// T3 window frame (KWin decoration, drawn by Aurorae's QML engine).
// Dark title bar with round top corners and a soft shadow; the window buttons sit on the left like
// macOS: three dots (close, minimise, maximise). Point at the group and every dot shows its mark;
// the dot under the mouse stretches into a capsule that says what it does (Close, Minimize, Maximize).
// Windows in the background get grey dots, coloured again as soon as the mouse is over them.
import QtQuick
import org.kde.kwin.decoration

Decoration {
    id: root

    readonly property int titleHeight: 34
    readonly property int radius: 10
    readonly property int shadow: 20
    readonly property bool active: decoration.client.active
    readonly property bool maximized: decoration.client.maximized
    readonly property color barColor: active ? "#26272a" : "#1e1f22"

    // true while the mouse is anywhere on the buttons; a short delay so moving from one dot to the
    // next does not make the marks blink
    property int buttonsHovered: 0
    property bool showMarks: false
    onButtonsHoveredChanged: buttonsHovered > 0 ? (marksOff.stop(), showMarks = true) : marksOff.restart()
    Timer { id: marksOff; interval: 120; onTriggered: root.showMarks = false }

    alpha: true

    DecorationOptions { id: options; deco: decoration }

    // ---- window shape + shadow (the shadow lives in the "padding" around the window) ----
    Item {
        id: frame
        anchors.fill: parent
        anchors.leftMargin: root.maximized ? 0 : root.padding.left
        anchors.rightMargin: root.maximized ? 0 : root.padding.right
        anchors.topMargin: root.maximized ? 0 : root.padding.top
        anchors.bottomMargin: root.maximized ? 0 : root.padding.bottom

        // soft shadow round the window (a 9-slice picture, see os/kde/gen-theme.py)
        BorderImage {
            anchors.fill: parent
            anchors.margins: -root.shadow
            border { left: root.shadow + root.radius; right: root.shadow + root.radius
                     top: root.shadow + root.radius; bottom: root.shadow + root.radius }
            source: "shadow.png"
            visible: !root.maximized
            opacity: root.active ? 1 : 0.6
        }
        Rectangle {
            anchors.fill: parent
            color: root.barColor
            topLeftRadius: root.maximized ? 0 : root.radius
            topRightRadius: root.maximized ? 0 : root.radius
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    // ---- title bar ----
    Item {
        id: titleBar
        x: frame.x
        y: frame.y
        width: frame.width
        height: root.titleHeight

        // faint line between title bar and window content
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: "#000000"
            opacity: 0.25
        }

        ButtonGroup {
            id: leftGroup
            anchors { left: parent.left; leftMargin: 12 }
            y: (root.titleHeight - 18) / 2      // 18 = a button at full (capsule) height
            spacing: 8
            explicitSpacer: 10
            buttons: options.titleButtonsLeft
            closeButton: closeC; minimizeButton: minC; maximizeButton: maxC   // other kinds are left out
        }
        ButtonGroup {
            id: rightGroup
            anchors { right: parent.right; rightMargin: 12 }
            y: (root.titleHeight - 18) / 2
            spacing: 8
            explicitSpacer: 10
            buttons: options.titleButtonsRight
            closeButton: closeC; minimizeButton: minC; maximizeButton: maxC   // other kinds are left out
        }

        Text {
            id: caption
            readonly property int side: Math.max(leftGroup.width, rightGroup.width) + 24
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: side
            anchors.rightMargin: side
            horizontalAlignment: Text.AlignHCenter
            text: decoration.client.caption
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            font: options.titleFont
            color: root.active ? "#c9cdd1" : "#787d82"
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Component.onCompleted: decoration.installTitleItem(titleBar)
    }

    Component { id: closeC; T3Button { buttonType: DecorationOptions.DecorationButtonClose } }
    Component { id: minC; T3Button { buttonType: DecorationOptions.DecorationButtonMinimize } }
    Component { id: maxC; T3Button { buttonType: DecorationOptions.DecorationButtonMaximizeRestore } }

    Component.onCompleted: {
        borders.setBorders(0);
        borders.setTitle(titleHeight);
        maximizedBorders.setBorders(0);
        maximizedBorders.setTitle(titleHeight);
        extendedBorders.setAllBorders(6);      // invisible edge you can grab to resize
        padding.setAllBorders(shadow);
    }
}
