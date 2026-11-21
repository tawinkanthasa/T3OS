// T3 panel window: one page of T3 Bench (http://127.0.0.1:7300/?view=...) in Qt WebEngine.
// Replaces cog, which doubled its window size on fractional display scales (e.g. 115%)
// and had no title bar under KWin. Started by t3-open:  <copy of qml named after the view> t3-view.qml -- <url>
// Wayland app id = reversed organization domain + executable name, so domain "t3" and an
// executable called "settings" give "t3.settings" (what the .desktop StartupWMClass expects).
// The domain must be set before the window exists, hence the window is created afterwards.
import QtQuick
import QtQuick.Window
import QtWebEngine

QtObject {
    id: root
    property var win: null   // keeps the window alive (not garbage-collected)

    Component.onCompleted: {
        Qt.application.domain = "t3"
        root.win = panel.createObject(null)
    }

    property WebEngineProfile prof: WebEngineProfile {
        storageName: "t3"                 // keeps localStorage between runs
        offTheRecord: false
        httpCacheType: WebEngineProfile.MemoryHttpCache
    }

    property Component panel: Window {
        width: Math.min(1100, Screen.desktopAvailableWidth - 40)
        height: Math.min(760, Screen.desktopAvailableHeight - 40)
        visible: true
        color: "#0a0d0b"
        title: view.title || "T3"

        WebEngineView {
            id: view
            anchors.fill: parent
            profile: root.prof
            backgroundColor: "#0a0d0b"
            url: Qt.application.arguments[Qt.application.arguments.length - 1]
            // links that leave T3 open in the normal browser, not inside the panel
            onNavigationRequested: function (req) {
                if (!req.url.toString().startsWith("http://127.0.0.1:7300")) {
                    req.action = WebEngineNavigationRequest.IgnoreRequest
                    Qt.openUrlExternally(req.url)
                }
            }
            onNewWindowRequested: function (req) { Qt.openUrlExternally(req.requestedUrl) }
        }
    }
}
