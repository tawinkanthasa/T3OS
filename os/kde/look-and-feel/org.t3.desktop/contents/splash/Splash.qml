// T3 desktop splash: chip logo, a thin progress line, "สวัสดี <name>"
import QtQuick
import org.kde.coreaddons as KCoreAddons

Rectangle {
    id: root
    color: "#0c0e10"
    property int stage

    KCoreAddons.KUser { id: kuser }

    Image {
        anchors.fill: parent
        source: "images/background.svg"
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width; sourceSize.height: root.height
    }
    Rectangle { anchors.fill: parent; color: "#080a09"; opacity: 0.55 }

    Column {
        id: content
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height * 0.05
        spacing: 40
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "images/logo.svg"
            width: 96; height: 96; sourceSize: Qt.size(192, 192)
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 200; height: 3; radius: 2
            color: Qt.rgba(1, 1, 1, 0.1)
            Rectangle {
                height: parent.height; radius: 2; color: "#3fb950"
                width: parent.width * Math.min(1, root.stage / 6)
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#c9cdd1"; font.family: "Noto Sans Thai"; font.pixelSize: 15
            text: "สวัสดี " + (kuser.fullName || kuser.loginName)
        }
    }

    onStageChanged: if (stage == 2) content.opacity = 1
    Component.onCompleted: content.opacity = 1
}
