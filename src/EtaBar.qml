import QtQuick

// One bar for "how far is it". The filled part is the time gone and the whole
// width is the slow end of what earlier builds did. A tick marks the usual
// finish, and the band around it how far the earlier builds spread, so the
// bar shows what the estimate is worth as well as what it is.
Item {
    id: bar
    property real elapsed: 0
    property real typical: 0   // The usual finish, 0 when unknown.
    property real low: 0
    property real high: 0
    property bool active: false
    property color fill: theme.accent

    readonly property bool known: typical > 0
    readonly property real span: Math.max(elapsed, high, typical, 1)
    implicitHeight: 14

    function at(seconds) { return Math.max(0, Math.min(1, seconds / span)) * track.width }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 8
        radius: 4
        color: theme.raised
        clip: true

        Rectangle {
            height: parent.height
            radius: parent.radius
            color: bar.fill
            width: bar.known || !bar.active ? Math.max(height, bar.at(bar.elapsed)) : 0
            Behavior on width { enabled: bar.active; NumberAnimation { duration: 1000 } }
        }

        // No estimate: a stripe that travels, which says "working" without
        // claiming to know how far.
        Rectangle {
            visible: bar.active && !bar.known
            width: parent.width * 0.22
            height: parent.height
            radius: parent.radius
            color: bar.fill
            opacity: 0.8
            SequentialAnimation on x {
                running: bar.active && !bar.known && bar.visible
                loops: Animation.Infinite
                NumberAnimation { from: -track.width * 0.22; to: track.width; duration: 1600; easing.type: Easing.InOutSine }
            }
        }
    }

    Rectangle {
        visible: bar.known && bar.high > bar.low
        x: bar.at(bar.low)
        width: Math.max(2, bar.at(bar.high) - bar.at(bar.low))
        anchors.verticalCenter: parent.verticalCenter
        height: 14
        radius: 3
        color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.13)
        border.width: 1
        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.22)
    }
    Rectangle {
        visible: bar.known
        x: Math.min(parent.width - width, bar.at(bar.typical) - 1)
        width: 2
        height: parent.height
        color: theme.text
    }
}
