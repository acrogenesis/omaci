import QtQuick

// Something to click that also has a key: the label, and the key next to it,
// so the mouse teaches the keyboard.
Rectangle {
    id: button
    property string label: ""
    property string key: ""
    property bool strong: false
    signal clicked()

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 26
    radius: 5
    opacity: enabled ? 1 : 0.4
    color: strong ? theme.accent : area.containsMouse && enabled ? theme.raised : "transparent"
    border.width: strong ? 0 : 1
    border.color: theme.line

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            text: button.label
            textFormat: Text.PlainText
            color: button.strong ? theme.accentForeground : theme.text
            font.pixelSize: 12
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: button.key !== ""
            text: button.key
            textFormat: Text.PlainText
            color: button.strong ? theme.accentForeground : theme.dim
            opacity: button.strong ? 0.7 : 1
            font.pixelSize: 11
            font.family: "monospace"
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (button.enabled) button.clicked()
    }
}
