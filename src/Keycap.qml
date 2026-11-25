import QtQuick

// Something to click that also has a key, written the way a terminal
// program writes it: `[c] copy link`. The mouse teaches the keyboard.
Item {
    id: keycap
    property string key: ""
    property string label: ""
    property bool strong: false
    property bool active: true
    signal clicked()

    implicitWidth: row.implicitWidth + theme.cellWidth
    implicitHeight: theme.cellHeight + 4
    opacity: active ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: Math.min(4, theme.radius)
        color: area.containsMouse && keycap.active ? theme.accentSoft : "transparent"
    }
    Row {
        id: row
        anchors.centerIn: parent
        Mono { text: "[" + keycap.key + "]"; color: theme.accent; font.bold: keycap.strong }
        Mono {
            text: " " + keycap.label
            color: area.containsMouse && keycap.active ? theme.accent : keycap.strong ? theme.text : theme.dim
            font.bold: keycap.strong
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: keycap.active ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (keycap.active) keycap.clicked()
    }
}
