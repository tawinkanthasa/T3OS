/* T3 installer slideshow (Calamares slideshowAPI 2) */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    Timer { interval: 12000; running: presentation.activatedInCalamares; repeat: true; onTriggered: presentation.goToNextSlide() }

    function onActivate() { }
    function onLeave() { }

    Rectangle { anchors.fill: parent; color: "#101c13"; z: -1 }

    Slide {
        Column {
            anchors.centerIn: parent; spacing: 18; width: parent.width * 0.8
            Image { source: "t3-logo.svg"; width: 96; height: 96; sourceSize.width: 192; sourceSize.height: 192; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "กำลังติดตั้ง T3"; color: "#e6e8ea"; font.pixelSize: 26; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "ใช้เวลาประมาณ 10-20 นาที ปล่อยไว้ได้เลย"; color: "#a8b0b6"; font.pixelSize: 16; wrapMode: Text.WordWrap; width: parent.width; horizontalAlignment: Text.AlignHCenter }
        }
    }
    Slide {
        Column {
            anchors.centerIn: parent; spacing: 14; width: parent.width * 0.8
            Text { text: "เสียบบอร์ดแล้วใช้ได้เลย"; color: "#3fb950"; font.pixelSize: 24; font.bold: true }
            Text { text: "ESP32, Pico, Arduino, ST-Link ไม่ต้องตั้งสิทธิ์เอง\nT3 Bench (Meta+B) บอกว่าเสียบอะไรอยู่ ดู Serial และแฟลชได้ในที่เดียว"; color: "#e6e8ea"; font.pixelSize: 16; wrapMode: Text.WordWrap; width: parent.width; lineHeight: 1.3 }
        }
    }
    Slide {
        Column {
            anchors.centerIn: parent; spacing: 14; width: parent.width * 0.8
            Text { text: "อัปเดตพังก็ย้อนได้"; color: "#3fb950"; font.pixelSize: 24; font.bold: true }
            Text { text: "ก่อนอัปเดตทุกครั้ง T3 สร้างจุดกู้คืนให้อัตโนมัติ\nถ้าเปิดเครื่องไม่ขึ้น เลือก 'snapshots' ในเมนูตอนบูตเพื่อกลับไปจุดก่อนหน้า"; color: "#e6e8ea"; font.pixelSize: 16; wrapMode: Text.WordWrap; width: parent.width; lineHeight: 1.3 }
        }
    }
    Slide {
        Column {
            anchors.centerIn: parent; spacing: 14; width: parent.width * 0.8
            Text { text: "มีปัญหา ถามได้"; color: "#3fb950"; font.pixelSize: 24; font.bold: true }
            Text { text: "T3 Doctor ตรวจ Wi-Fi เสียง ดิสก์ บอร์ด แล้วบอกวิธีแก้\nกดให้ Claude ช่วยแก้ต่อได้ทันที"; color: "#e6e8ea"; font.pixelSize: 16; wrapMode: Text.WordWrap; width: parent.width; lineHeight: 1.3 }
        }
    }
}
