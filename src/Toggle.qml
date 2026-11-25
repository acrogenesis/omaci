import QtQuick

// A filter you can see the state of, written the way a terminal program
// writes a checkbox: the key that flips it, a box that is filled while it
// is on, and what it keeps. `[m] ■ main`, `[a] □ running`.
Item {
    id: toggle
    property string key: ""
    property string label: ""
    property bool checked: false
    property bool active: true
    property color labelColor: checked ? theme.text : theme.dim
    signal clicked()

    implicitWidth: row.implicitWidth + theme.cellWidth
    implicitHeight: theme.cellHeight + 4
    opacity: active ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: Math.min(4, theme.radius)
        color: area.containsMouse && toggle.active ? theme.accentSoft
             : toggle.checked ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14) : "transparent"
    }
    Row {
        id: row
        anchors.centerIn: parent
        Mono { text: "[" + toggle.key + "] "; color: theme.accent }
        Mono { text: toggle.checked ? "■" : "□"; color: toggle.checked ? theme.accent : theme.faint; font.bold: true }
        Mono {
            text: " " + toggle.label
            color: area.containsMouse && toggle.active ? theme.accent : toggle.labelColor
            font.bold: toggle.checked
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: toggle.active ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (toggle.active) toggle.clicked()
    }
}
