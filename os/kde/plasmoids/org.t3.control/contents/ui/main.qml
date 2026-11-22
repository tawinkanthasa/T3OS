// Control Center: the button at the right end of the dock. One popup with the switches people reach
// for every day: Wi-Fi, Bluetooth, Night Light, Do Not Disturb, screenshot, display settings,
// brightness of every screen, volume, where the sound goes, and the song playing.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.bluezqt as BluezQt
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.private.brightnesscontrolplugin
import org.kde.plasma.private.volume
import org.kde.plasma.private.mpris as Mpris

PlasmoidItem {
    id: root
    Plasmoid.icon: "adjustlevels"
    toolTipMainText: "Control Center"
    toolTipSubText: "Wi-Fi, Bluetooth, brightness, sound"
    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 10

    // ---- the system pieces ----
    PlasmaNM.Handler { id: nm }
    PlasmaNM.EnabledConnections { id: nmOn }
    NightLightControl { id: night }
    ScreenBrightnessControl { id: screens; isSilent: root.expanded }
    NotificationManager.Settings { id: notif }
    Mpris.Mpris2Model { id: mpris }
    SinkModel { id: sinkModel }
    PulseObjectFilterModel {
        id: outputs
        sourceModel: sinkModel
        filters: [ { role: "VirtualDevice", value: false } ]
    }
    P5Support.DataSource {
        id: run
        engine: "executable"
        onNewData: (source, data) => disconnectSource(source)
        function exec(cmd) { connectSource(cmd) }
    }

    readonly property var sink: PreferredDevice.sink
    readonly property var player: mpris.currentPlayer
    readonly property bool dnd: {
        const until = notif.notificationsInhibitedUntil;
        return !isNaN(until) && until > new Date();
    }
    // "HyperX Cloud III Analog Stereo" -> "HyperX Cloud III"; "... Digital Stereo (HDMI)" -> "HDMI"
    function shortName(n) {
        if (/\(HDMI|HDMI|DisplayPort/i.test(n)) return "HDMI / screen";
        return n.replace(/\s+(Analog|Digital|Multichannel)\b.*$/i, "").replace(/\s+(Stereo|Mono)$/i, "");
    }
    function setDnd(on) {
        // "until" a far date = on until switched off (what the stock Notifications widget does)
        notif.notificationsInhibitedUntil = on ? new Date(new Date().getFullYear() + 10, 0, 1) : new Date(NaN);
        if (!on) notif.revokeApplicationInhibitions();
        notif.save();
    }

    // ---- in the dock:  | 12:40  Sun 22 Nov  [Control Center] ----
    compactRepresentation: RowLayout {
        id: dockPart
        spacing: Kirigami.Units.smallSpacing * 2
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth

        Rectangle {        // divider between the apps and the clock
            Layout.preferredWidth: 1
            Layout.preferredHeight: Math.round(dockPart.height * 0.55)
            Layout.leftMargin: Kirigami.Units.smallSpacing
            color: Qt.rgba(1, 1, 1, 0.18)
        }
        ColumnLayout {     // clock, like the design: time over date
            spacing: 0
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Timer { id: tick; property date now: new Date(); interval: 1000; running: true; repeat: true; onTriggered: now = new Date() }
            PC3.Label {
                Layout.alignment: Qt.AlignRight
                text: Qt.formatTime(tick.now, "HH:mm")
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            PC3.Label {
                Layout.alignment: Qt.AlignRight
                text: Qt.formatDate(tick.now, "ddd d MMM")
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
        MouseArea {
            id: btn
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            Layout.fillHeight: true
            Layout.preferredWidth: Math.max(Kirigami.Units.gridUnit * 2, dockPart.height)
            Layout.rightMargin: Kirigami.Units.smallSpacing
            onClicked: root.expanded = !root.expanded
            Rectangle {
                anchors.centerIn: parent
                width: Math.round(Math.min(parent.width, parent.height) * 0.85); height: width
                radius: Math.round(width * 0.3)
                color: root.expanded ? Qt.rgba(0.247, 0.725, 0.314, 0.28)
                     : btn.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                Behavior on color { ColorAnimation { duration: 150 } }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Math.round(parent.width * 0.55); height: width
                    source: "adjustlevels"
                }
            }
        }
    }

    // ---- popup ----
    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 21
        Layout.minimumWidth: Kirigami.Units.gridUnit * 21
        Layout.preferredHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
        Layout.minimumHeight: Layout.preferredHeight
        collapseMarginsHint: true

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                PC3.Label { text: "Control Center"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                PC3.Label {
                    opacity: 0.6
                    text: Qt.formatDate(clock.now, "ddd d MMM")
                    Timer { id: clock; property date now: new Date(); interval: 60000; running: true; repeat: true; onTriggered: now = new Date() }
                }
            }

            // switches
            GridLayout {
                columns: 3
                columnSpacing: Kirigami.Units.smallSpacing * 2
                rowSpacing: Kirigami.Units.smallSpacing * 2
                Layout.fillWidth: true

                Tile {
                    icon: "network-wireless"; title: "Wi-Fi"
                    visible: nmOn.wirelessHwEnabled
                    on: nmOn.wirelessEnabled
                    sub: on ? "On" : "Off"
                    onToggled: nm.enableWireless(!nmOn.wirelessEnabled)
                }
                Tile {
                    icon: "network-bluetooth"; title: "Bluetooth"
                    visible: BluezQt.Manager.adapters.length > 0
                    on: BluezQt.Manager.bluetoothOperational
                    sub: !on ? "Off" : BluezQt.Manager.connectedDevices.length > 0
                         ? BluezQt.Manager.connectedDevices[0].name : "On"
                    onToggled: {
                        const enable = !BluezQt.Manager.bluetoothOperational;
                        BluezQt.Manager.bluetoothBlocked = !enable;
                        BluezQt.Manager.adapters.forEach(a => a.powered = enable);
                    }
                }
                Tile {
                    icon: "redshift-status-on"; title: "Night Light"
                    visible: night.available && night.enabled
                    on: night.running && !night.inhibited
                    sub: on ? "On" : "Paused"
                    onToggled: night.toggleInhibition()
                }
                Tile {
                    icon: "notifications-disabled-symbolic"; title: "Do Not Disturb"
                    on: root.dnd
                    sub: on ? "On" : "Off"
                    onToggled: root.setDnd(!root.dnd)
                }
                Tile {
                    icon: "spectacle"; title: "Screenshot"; sub: "Pick an area"
                    onToggled: { root.expanded = false; run.exec("spectacle --region --launchonly"); }
                }
                Tile {
                    icon: "video-display"; title: "Displays"; sub: "Settings"
                    onToggled: { root.expanded = false; run.exec("systemsettings kcm_kscreen"); }
                }
            }

            // brightness, one slider per screen that allows it (external monitors via DDC)
            Repeater {
                model: screens.displays
                delegate: SliderRow {
                    required property string displayName
                    required property string label
                    required property int brightness
                    required property int maxBrightness
                    icon: "video-display-brightness"
                    hint: label
                    from: 0; to: maxBrightness
                    value: brightness
                    onMoved: v => screens.setBrightness(displayName, v)
                }
            }

            // volume
            SliderRow {
                visible: !!root.sink
                icon: root.sink && root.sink.muted ? "audio-volume-muted"
                    : !root.sink ? "audio-volume-high"
                    : root.sink.volume / PulseAudio.NormalVolume < 0.34 ? "audio-volume-low"
                    : root.sink.volume / PulseAudio.NormalVolume < 0.67 ? "audio-volume-medium" : "audio-volume-high"
                from: 0; to: PulseAudio.NormalVolume
                value: root.sink ? root.sink.volume : 0
                iconClick: true
                onIconClicked: if (root.sink) root.sink.muted = !root.sink.muted
                onMoved: v => { if (root.sink) { root.sink.muted = false; root.sink.volume = v; } }
            }

            // where the sound goes
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: outputs.count > 1
                Repeater {
                    model: outputs
                    delegate: PC3.Button {
                        required property var model
                        text: root.shortName(model.PulseObject.description || model.PulseObject.name)
                        checkable: true
                        checked: model.PulseObject.default
                        flat: !checked
                        onClicked: model.PulseObject.default = true
                    }
                }
            }

            // the song playing
            Rectangle {
                visible: !!root.player
                Layout.fillWidth: true
                Layout.preferredHeight: np.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.cornerRadius * 2
                color: Qt.rgba(1, 1, 1, 0.06)
                RowLayout {
                    id: np
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing
                    Rectangle {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                        radius: Kirigami.Units.cornerRadius * 2
                        color: Qt.rgba(1, 1, 1, 0.08)
                        clip: true
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: parent.width * 0.5; height: width
                            source: root.player && root.player.iconName ? root.player.iconName : "view-media-track"
                            visible: npArt.status !== Image.Ready
                        }
                        Image {
                            id: npArt
                            anchors.fill: parent
                            source: root.player ? root.player.artUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        PC3.Label {
                            Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.DemiBold
                            textFormat: Text.PlainText
                            text: root.player ? (root.player.track || root.player.identity) : ""
                        }
                        PC3.Label {
                            Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.6
                            textFormat: Text.PlainText
                            text: root.player ? [root.player.artist, root.player.identity].filter(s => s).join(" · ") : ""
                        }
                    }
                    PC3.ToolButton { icon.name: "media-skip-backward"; onClicked: root.player.Previous(); enabled: root.player && root.player.canGoPrevious }
                    PC3.ToolButton {
                        icon.name: root.player && root.player.playbackStatus === Mpris.PlaybackStatus.Playing ? "media-playback-pause" : "media-playback-start"
                        onClicked: root.player.PlayPause()
                    }
                    PC3.ToolButton { icon.name: "media-skip-forward"; onClicked: root.player.Next(); enabled: root.player && root.player.canGoNext }
                }
            }
        }
    }

    // ---- building blocks ----
    component Tile: Rectangle {
        id: t
        property string icon
        property string title
        property string sub
        property bool on: false
        signal toggled()
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 4.4
        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
        radius: Kirigami.Units.cornerRadius * 2.5
        color: on ? (ma.containsMouse ? "#4cc85d" : "#3fb950")
                  : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
        Behavior on color { ColorAnimation { duration: 150 } }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing * 2.5
            spacing: 2
            Kirigami.Icon {
                source: t.icon
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                isMask: t.on
                color: "#0b1a0e"
            }
            Item { Layout.fillHeight: true }
            PC3.Label {
                text: t.title; Layout.fillWidth: true; elide: Text.ElideRight
                font.weight: Font.DemiBold
                color: t.on ? "#0b1a0e" : Kirigami.Theme.textColor
            }
            PC3.Label {
                text: t.sub; Layout.fillWidth: true; elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: t.on ? "#0b1a0e" : Kirigami.Theme.textColor
                opacity: t.on ? 0.75 : 0.6
                textFormat: Text.PlainText
            }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: t.toggled() }
    }

    component SliderRow: Rectangle {
        id: s
        property string icon
        property string hint
        property real from: 0
        property real to: 100
        property real value: 0
        property bool iconClick: false
        signal moved(real v)
        signal iconClicked()
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * (s.hint !== "" ? 3.3 : 2.4)
        radius: Kirigami.Units.cornerRadius * 2.5
        color: Qt.rgba(1, 1, 1, 0.06)
        PC3.Label {
            visible: s.hint !== ""
            text: s.hint
            textFormat: Text.PlainText
            elide: Text.ElideRight
            opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: Kirigami.Units.largeSpacing; topMargin: Kirigami.Units.smallSpacing * 1.5 }
        }
        RowLayout {
            anchors.fill: parent
            anchors.topMargin: s.hint !== "" ? Kirigami.Units.gridUnit * 1.1 : 0
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            Kirigami.Icon {
                source: s.icon
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                MouseArea { anchors.fill: parent; enabled: s.iconClick; cursorShape: Qt.PointingHandCursor; onClicked: s.iconClicked() }
            }
            PC3.Slider {
                id: sl
                Layout.fillWidth: true
                from: s.from; to: s.to
                value: s.value
                onMoved: s.moved(value)
            }
            PC3.Label {
                text: Math.round((sl.value - s.from) / Math.max(1, s.to - s.from) * 100) + "%"
                opacity: 0.6
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                horizontalAlignment: Text.AlignRight
                font.features: { "tnum": 1 }
            }
        }
    }
}
