// Dock widget: the song playing (any MPRIS player: Spotify, Chrome, YouTube, VLC...).
// Takes no room while nothing plays; when music starts the dock grows open to show
// cover · title / artist · previous play next. After a pause it stays for a minute, then folds away.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    Mpris.Mpris2Model { id: mpris }
    readonly property var player: mpris.currentPlayer
    readonly property int status: player ? player.playbackStatus : 0
    readonly property bool playing: status === Mpris.PlaybackStatus.Playing
    readonly property bool paused: status === Mpris.PlaybackStatus.Paused
    property bool lingering: false          // paused a moment ago: keep it showing for a while
    readonly property bool shown: playing || (paused && lingering)

    onPlayingChanged: if (playing) lingering = true; else if (paused) linger.restart()
    onPausedChanged: if (paused) linger.restart()
    Timer { id: linger; interval: 60000; onTriggered: root.lingering = false }

    toolTipMainText: player ? (player.track || player.identity) : ""
    toolTipSubText: player ? [player.artist, player.identity].filter(s => s).join(" · ") : ""

    fullRepresentation: Item {
        id: box
        readonly property real full: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.fillHeight: true
        Layout.preferredWidth: root.shown ? full : 0
        Layout.minimumWidth: Layout.preferredWidth
        Layout.maximumWidth: Layout.preferredWidth
        clip: true
        opacity: root.shown ? 1 : 0
        Behavior on Layout.preferredWidth { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 260 } }

        RowLayout {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            x: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing * 2

            // cover: click to bring the player's window up
            Item {
                id: cover
                readonly property int size: Math.round(box.height * 0.66)
                Layout.preferredWidth: size
                Layout.preferredHeight: size
                Rectangle {
                    anchors.fill: parent
                    radius: Math.round(cover.size * 0.22)
                    color: Qt.rgba(1, 1, 1, 0.08)
                    clip: true
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: cover.size * 0.55; height: width
                        source: root.player && root.player.iconName ? root.player.iconName : "view-media-track"
                        visible: art.status !== Image.Ready
                    }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: root.player ? root.player.artUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: cover.size * 2
                        sourceSize.height: cover.size * 2
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.player && root.player.canRaise) root.player.Raise()
                }
            }

            ColumnLayout {
                spacing: 0
                Layout.maximumWidth: Kirigami.Units.gridUnit * 8
                PC3.Label {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.track || root.player.identity) : ""
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                PC3.Label {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.artist || root.player.identity) : ""
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            RowLayout {
                spacing: 0
                PC3.ToolButton {
                    icon.name: "media-skip-backward"
                    enabled: root.player && root.player.canGoPrevious
                    onClicked: root.player.Previous()
                    PC3.ToolTip.text: "Previous"
                    PC3.ToolTip.visible: hovered
                }
                // play / pause: a light round button, the one thing in the dock you press most
                Rectangle {
                    readonly property int size: Math.round(box.height * 0.5)
                    Layout.preferredWidth: size
                    Layout.preferredHeight: size
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    radius: size / 2
                    color: playArea.pressed ? "#c9cdd1" : playArea.containsMouse ? "#ffffff" : "#e6e8ea"
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: parent.size * 0.5; height: width
                        source: root.playing ? "media-playback-pause" : "media-playback-start"
                        isMask: true
                        color: "#141518"
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.PlayPause()
                    }
                }
                PC3.ToolButton {
                    icon.name: "media-skip-forward"
                    enabled: root.player && root.player.canGoNext
                    onClicked: root.player.Next()
                    PC3.ToolTip.text: "Next"
                    PC3.ToolTip.visible: hovered
                }
            }

            // thin line between the music and the apps
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: Math.round(box.height * 0.5)
                Layout.leftMargin: Kirigami.Units.smallSpacing
                color: Qt.rgba(1, 1, 1, 0.12)
            }
        }
    }
}
