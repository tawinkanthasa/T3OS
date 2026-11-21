// T3 login screen (SDDM, Qt 6): big clock, the last user, a round password field, power buttons.
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    width: 1440; height: 900
    color: "#0c0e10"
    readonly property color fg: "#e6e8ea"
    readonly property color mute: "#c9cdd1"
    readonly property color acc: "#3fb950"
    readonly property string font: "Noto Sans Thai"
    property string user: userModel.lastUser || ""
    property int session: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0

    Image {
        anchors.fill: parent
        source: config.background ? "file://" + config.background : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width; sourceSize.height: root.height
    }
    Rectangle { anchors.fill: parent; color: "#080a09"; opacity: 0.45 }

    // ---- clock
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.13
        spacing: 4
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.fg; font.family: root.font; font.pixelSize: 112; font.weight: Font.Light
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.mute; font.family: root.font; font.pixelSize: 22; font.weight: Font.Medium
            text: new Date().toLocaleDateString(Qt.locale("th_TH"), "dddd'ที่' d MMMM")
        }
        Timer {
            interval: 5000; running: true; repeat: true
            onTriggered: {
                clock.text = Qt.formatTime(new Date(), "HH:mm")
                date.text = new Date().toLocaleDateString(Qt.locale("th_TH"), "dddd'ที่' d MMMM")
            }
        }
    }

    // ---- user + password
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.48
        spacing: 16

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96; radius: 48
            color: "#1f6f35"; border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 3
            Text {
                anchors.centerIn: parent
                color: "#e6ffe9"; font.family: root.font; font.pixelSize: 40; font.weight: Font.DemiBold
                text: (root.user || "T").charAt(0).toUpperCase()
            }
        }

        // no remembered user yet (first boot): ask for the name too
        TextField {
            id: nameField
            visible: !userModel.lastUser
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260; height: 44
            placeholderText: "ชื่อผู้ใช้"; placeholderTextColor: "#8b949e"
            color: root.fg; font.family: root.font; font.pixelSize: 15
            leftPadding: 16; rightPadding: 16
            background: Rectangle { radius: 22; color: Qt.rgba(0.08, 0.08, 0.09, 0.7); border.color: Qt.rgba(1, 1, 1, 0.16) }
            onTextChanged: root.user = text
            KeyNavigation.tab: password
        }
        Text {
            visible: !!userModel.lastUser
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.fg; font.family: root.font; font.pixelSize: 22; font.weight: Font.DemiBold
            text: root.user
        }

        Row {
            id: pwRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            TextField {
                id: password
                width: 260; height: 44
                echoMode: TextInput.Password
                placeholderText: "รหัสผ่าน"; placeholderTextColor: "#8b949e"
                color: root.fg; font.family: root.font; font.pixelSize: 15
                leftPadding: 16; rightPadding: 16
                focus: true
                background: Rectangle { radius: 22; color: Qt.rgba(0.08, 0.08, 0.09, 0.7); border.color: Qt.rgba(1, 1, 1, 0.16) }
                Keys.onReturnPressed: root.login()
                Keys.onEnterPressed: root.login()
                Accessible.name: "รหัสผ่าน"
            }
            Button {
                width: 44; height: 44
                Accessible.name: "เข้าสู่ระบบ"
                onClicked: root.login()
                background: Rectangle { radius: 22; color: parent.down ? "#2ea043" : root.acc }
                contentItem: Text {
                    text: "→"; color: "#06210d"; font.pixelSize: 22; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: pwRow; property: "anchors.horizontalCenterOffset"; to: -12; duration: 50 }
                NumberAnimation { target: pwRow; property: "anchors.horizontalCenterOffset"; to: 12; duration: 70 }
                NumberAnimation { target: pwRow; property: "anchors.horizontalCenterOffset"; to: -6; duration: 60 }
                NumberAnimation { target: pwRow; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
            }
        }

        Text {
            id: hint
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#8fa89a"; font.family: root.font; font.pixelSize: 13
            text: "Alt+Shift สลับ EN / TH"
        }
    }

    // ---- bottom bar: logo, keyboard layout, power
    Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 30 }
        height: 44
        Image {
            anchors.verticalCenter: parent.verticalCenter
            source: "logo-mono.svg"; width: 22; height: 22; sourceSize: Qt.size(44, 44)
        }
        Row {
            anchors.right: parent.right
            spacing: 12
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: keyboard && keyboard.layouts && keyboard.layouts.length > 1
                width: kb.width + 20; height: 26; radius: 6
                color: Qt.rgba(1, 1, 1, 0.08)
                Text {
                    id: kb; anchors.centerIn: parent
                    color: root.mute; font.family: "JetBrains Mono"; font.pixelSize: 13; font.weight: Font.DemiBold
                    text: keyboard && keyboard.layouts && keyboard.layouts.length > keyboard.currentLayout
                          ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
                }
            }
            Repeater {
                model: [
                    { name: "พักเครื่อง", icon: "suspend.svg", ok: sddm.canSuspend, act: function() { sddm.suspend() } },
                    { name: "รีสตาร์ท", icon: "reboot.svg", ok: sddm.canReboot, act: function() { sddm.reboot() } },
                    { name: "ปิดเครื่อง", icon: "shutdown.svg", ok: sddm.canPowerOff, act: function() { sddm.powerOff() } }
                ]
                delegate: Button {
                    visible: modelData.ok
                    width: 44; height: 44
                    Accessible.name: modelData.name
                    ToolTip.visible: hovered; ToolTip.text: modelData.name
                    onClicked: modelData.act()
                    background: Rectangle { radius: 22; color: parent.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08) }
                    contentItem: Image { source: modelData.icon; sourceSize: Qt.size(20, 20); fillMode: Image.Pad }
                }
            }
        }
    }

    function login() {
        if (!root.user) { nameField.forceActiveFocus(); return }
        hint.text = "กำลังเข้าสู่ระบบ…"
        sddm.login(root.user, password.text, root.session)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            password.text = ""
            hint.text = "รหัสผ่านไม่ถูก ลองอีกครั้ง"
            hint.color = "#f85149"
            shake.start()
            password.forceActiveFocus()
        }
    }

    Component.onCompleted: (userModel.lastUser ? password : nameField).forceActiveFocus()
}
