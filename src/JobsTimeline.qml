import QtQuick
import "format.js" as Format

// The jobs of a build on one time axis. Solid is what happened, hollow is
// what earlier builds say is still to come, and the line is now: one look
// says which job the build is waiting for.
Item {
    id: timeline
    property var jobs: []
    property var estimate: ({})
    property real selectedJobId: 0
    signal picked(real id)

    // Skipped jobs did nothing and have no log, so they share one line at
    // the bottom instead of taking a row each; unless they are all there is.
    readonly property var skipped: jobs.filter(job => job.state === "skipped")
    readonly property var shown: skipped.length === jobs.length ? jobs : jobs.filter(job => job.state !== "skipped")
    readonly property bool skippedLine: skipped.length > 0 && skipped.length < jobs.length

    readonly property int rowHeight: 26
    readonly property int labelWidth: Math.max(150, Math.min(250, width * 0.2))
    readonly property int figuresWidth: 150
    readonly property real trackWidth: Math.max(50, width - labelWidth - figuresWidth - 16)
    readonly property real axis: Math.max(1, estimate.axis || 1) * 1.04
    readonly property bool active: estimate.active === true
    readonly property real elapsed: estimate.elapsed || 0
    readonly property int tickStep: Format.tickStep(axis, Math.max(3, Math.floor(trackWidth / 70)))

    implicitHeight: 22 + rows.implicitHeight + (skippedLine ? 22 : 0)

    function px(seconds) { return Math.max(0, Math.min(1, seconds / axis)) * trackWidth }

    // The axis, and its marks down through the rows.
    Repeater {
        model: Math.floor(timeline.axis / timeline.tickStep) + 1
        delegate: Item {
            required property int index
            x: timeline.labelWidth + timeline.px(index * timeline.tickStep)
            height: timeline.height
            Rectangle { y: 20; width: 1; height: rows.implicitHeight + 2; color: theme.line; opacity: 0.6 }
            Text {
                x: index === 0 ? 0 : -width / 2
                y: 2
                text: Format.tick(index * timeline.tickStep)
                color: theme.faint
                font.pixelSize: 11
            }
        }
    }

    Column {
        id: rows
        y: 22
        width: parent.width

        Repeater {
            model: timeline.shown
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool current: modelData.id === timeline.selectedJobId
                readonly property var forecast: (timeline.estimate.jobs || {})[modelData.key] || ({})
                readonly property string jobState: modelData.state
                readonly property bool started: modelData.start >= 0 && jobState !== "skipped"
                readonly property bool running: jobState === "running"
                readonly property bool waiting: jobState === "queued" || jobState === "pending"
                readonly property real from: started ? modelData.start : (forecast.start >= 0 ? forecast.start : -1)
                readonly property real until: running ? timeline.elapsed : modelData.end
                readonly property bool forecastShown: timeline.active && forecast.end > 0 && forecast.typical >= 0
                                                      && (running || waiting)

                width: rows.width
                height: timeline.rowHeight
                color: current ? theme.raised : area.containsMouse && modelData.id > 0 ? theme.hover : "transparent"

                Rectangle { width: 3; height: parent.height; color: theme.accent; visible: row.current }

                StatusIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; state: row.jobState; size: 13 }
                Row {
                    x: 38
                    width: timeline.labelWidth - 46
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    clip: true
                    Text {
                        id: nameText
                        width: Math.min(implicitWidth, parent.width)
                        text: modelData.name
                        textFormat: Text.PlainText
                        color: row.jobState === "skipped" || row.jobState === "pending" ? theme.dim : theme.text
                        font.pixelSize: 13
                        font.bold: row.current
                        elide: Text.ElideRight
                    }
                    // Which workflow, when the build has more than one.
                    Text {
                        visible: modelData.workflow !== "" && width > 20
                        width: Math.max(0, parent.width - nameText.width - 8)
                        anchors.baseline: nameText.baseline
                        text: modelData.workflow || ""
                        textFormat: Text.PlainText
                        color: theme.faint
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Item {
                    x: timeline.labelWidth
                    width: timeline.trackWidth
                    height: parent.height

                    // What is still expected: from now, or from where the job
                    // usually starts, to where it usually ends.
                    Rectangle {
                        visible: row.forecastShown
                        readonly property real begin: row.running ? timeline.elapsed : Math.max(row.from, 0)
                        x: timeline.px(begin)
                        width: Math.max(0, timeline.px(row.forecast.end) - x)
                        anchors.verticalCenter: parent.verticalCenter
                        height: 10
                        radius: 3
                        color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, row.waiting ? 0.10 : 0.16)
                        border.width: 1
                        border.color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, row.waiting ? 0.45 : 0.7)
                    }
                    // How much later it ends when the job is slow.
                    Rectangle {
                        visible: row.forecastShown && row.forecast.high > row.forecast.end
                        x: timeline.px(row.forecast.end)
                        width: Math.max(0, timeline.px(row.forecast.high) - x)
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.6)
                        Rectangle { anchors.right: parent.right; y: -3; width: 1; height: 7; color: parent.color; visible: parent.width > 2 }
                    }
                    // What happened.
                    Rectangle {
                        visible: row.started
                        x: timeline.px(modelData.start)
                        width: Math.max(3, timeline.px(row.until) - x)
                        anchors.verticalCenter: parent.verticalCenter
                        height: 10
                        radius: 3
                        color: row.running ? theme.accent
                             : row.jobState === "success" ? theme.ok
                             : row.jobState === "failure" ? theme.bad : theme.faint
                        opacity: row.jobState === "success" ? 0.8 : 1
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    font.family: "monospace"
                    color: row.running ? (row.forecast.late ? theme.warn : theme.accent) : theme.dim
                    text: {
                        const usual = row.forecast.typical >= 0 && timeline.active ? " / ~" + Format.duration(row.forecast.typical) : ""
                        if (row.running) return Format.duration(timeline.elapsed - modelData.start) + usual
                        if (row.jobState === "pending") return row.forecast.typical >= 0 ? "~" + Format.duration(row.forecast.typical) : ""
                        if (row.jobState === "queued") return "queued" + (row.forecast.typical >= 0 ? usual : "")
                        if (row.jobState === "skipped") return "skipped"
                        return row.started ? Format.duration(modelData.end - modelData.start) : ""
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: modelData.id > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: timeline.picked(modelData.id)
                }
            }
        }
    }

    Text {
        visible: timeline.skippedLine
        x: 38
        y: 22 + rows.implicitHeight
        width: parent.width - 54
        height: 22
        verticalAlignment: Text.AlignVCenter
        text: "Skipped: " + timeline.skipped.map(job => job.name).join(", ")
        textFormat: Text.PlainText
        color: theme.faint
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    // Now.
    Rectangle {
        visible: timeline.active
        x: timeline.labelWidth + timeline.px(timeline.elapsed)
        y: 16
        width: 1
        height: 6 + rows.implicitHeight
        color: theme.text
        Behavior on x { NumberAnimation { duration: 1000 } }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -14
            width: nowText.implicitWidth + 10
            height: 16
            radius: 3
            color: theme.text
            Text { id: nowText; anchors.centerIn: parent; text: "now"; color: theme.background; font.pixelSize: 10; font.bold: true }
        }
    }
}
