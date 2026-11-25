import QtQuick
import "format.js" as Format

// The earlier builds like this one, oldest on the left, one bar each: as tall
// as the build was long, coloured by how it ended. The last bar is this
// build. "Usually seven minutes" then has something to look at behind it.
Item {
    id: strip
    property var builds: []       // { key, seconds, state, title, sha, current }
    property real currentSeconds: 0
    property real typical: 0
    property string hovered: ""
    signal picked(string key)

    readonly property real tallest: {
        let most = Math.max(currentSeconds, typical, 1)
        for (const build of builds) most = Math.max(most, build.seconds)
        // One build that took an hour mustn't flatten the others into a line.
        return typical > 0 ? Math.min(most, Math.max(typical * 2, currentSeconds)) : most
    }
    readonly property real slot: Math.max(5, Math.min(16, Math.floor((width + 3) / Math.max(1, builds.length))))

    Row {
        id: bars
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height
        spacing: 3
        Repeater {
            model: strip.builds
            delegate: Item {
                required property var modelData
                readonly property real seconds: modelData.current ? strip.currentSeconds : modelData.seconds
                width: strip.slot - 3
                height: bars.height
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(3, Math.min(parent.height, Math.round(parent.height * parent.seconds / strip.tallest)))
                    radius: Math.min(2, width / 2)
                    opacity: modelData.current || area.containsMouse ? 1 : 0.75
                    color: modelData.current && (modelData.state === "running" || modelData.state === "queued") ? theme.accent
                         : modelData.state === "success" ? theme.ok
                         : modelData.state === "failure" ? theme.bad : theme.faint
                    border.width: modelData.current ? 1 : 0
                    border.color: theme.text
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.margins: -1
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: strip.hovered = !containsMouse ? ""
                        : modelData.title + "  ·  " + (modelData.current && strip.currentSeconds > 0 && !modelData.seconds
                            ? "running" : Format.duration(modelData.seconds) + ", " + ({ "success": "passed", "failure": "failed", "cancelled": "cancelled" }[modelData.state] || modelData.state))
                    onClicked: strip.picked(modelData.key)
                }
            }
        }
    }

    // The usual length, as a line across the bars.
    Rectangle {
        visible: strip.typical > 0
        anchors.right: parent.right
        width: bars.width
        height: 1
        y: Math.round(parent.height - parent.height * strip.typical / strip.tallest)
        color: theme.dim
    }
}
