import QtQuick

// A panel the way a terminal draws one: a thin line around it with its title
// set into the top edge. The line is the accent while the panel is the one
// the keys last acted on. Corners follow the desktop's window rounding.
Item {
    id: frame
    property string title: ""
    property string note: ""       // After the title, quieter.
    property string corner: ""     // Set into the top edge on the right.
    property bool focused: false
    property color tint: focused ? theme.accent : theme.line
    property color cornerColor: theme.dim
    // The height of what is inside, for a frame that sizes itself.
    property real contentHeight: 0
    default property alias content: inner.data

    readonly property real cw: theme.cellWidth
    readonly property real ch: theme.cellHeight
    readonly property real innerWidth: inner.width
    implicitHeight: contentHeight + ch * 1.9

    Rectangle {
        x: Math.round(frame.cw / 2)
        y: Math.round(frame.ch / 2)
        width: parent.width - 2 * x
        height: parent.height - y - Math.round(frame.ch / 4)
        color: "transparent"
        border.width: 1
        border.color: frame.tint
        radius: theme.radius
    }
    Rectangle {
        visible: frame.title !== ""
        x: Math.round(frame.cw * 2) + theme.radius
        width: titleRow.width + frame.cw
        height: frame.ch
        color: theme.background
        Row {
            id: titleRow
            x: frame.cw / 2
            Mono { text: frame.title; color: frame.focused ? theme.accent : theme.text; font.bold: true }
            Mono {
                visible: frame.note !== ""
                width: Math.min(implicitWidth, Math.max(0, frame.width - frame.cw * 10 - x - cornerText.width))
                text: " ─ " + frame.note
                color: theme.dim
                elide: Text.ElideRight
            }
        }
    }
    Rectangle {
        visible: frame.corner !== ""
        anchors.right: parent.right
        anchors.rightMargin: Math.round(frame.cw * 2) + theme.radius
        width: cornerText.width + frame.cw
        height: frame.ch
        color: theme.background
        Mono { id: cornerText; x: frame.cw / 2; text: frame.corner; color: frame.cornerColor }
    }
    Item {
        id: inner
        x: Math.round(frame.cw * 1.5)
        y: Math.round(frame.ch * 1.2)
        width: parent.width - 2 * x
        height: parent.height - y - Math.round(frame.ch * 0.6)
        clip: true
    }
}
