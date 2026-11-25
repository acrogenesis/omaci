import QtQuick
import "format.js" as Format

// The jobs of a build on one time axis, in characters. Full blocks are what
// happened, shade is what earlier builds say is still to come, the dashes
// after it are how much longer a slow run takes, the low line under a bar is
// where the same job ran in the build main had before, and the line down
// through the rows is now.
Item {
    id: timeline
    property var jobs: []
    property var estimate: ({})
    // The build main had before this one: where its jobs ran, and how long.
    property var previous: ({})
    property real selectedJobId: 0
    signal picked(real id)

    readonly property real cw: theme.cellWidth
    readonly property real ch: theme.cellHeight
    readonly property bool compared: previous.ready === true
    // Skipped jobs did nothing and have no log, so they share one line at
    // the bottom instead of taking a row each; unless they are all there is.
    readonly property var skipped: jobs.filter(job => job.state === "skipped")
    readonly property var shown: skipped.length === jobs.length ? jobs : jobs.filter(job => job.state !== "skipped")
    readonly property bool skippedLine: skipped.length > 0 && skipped.length < jobs.length

    readonly property int rowHeight: Math.round(ch * 1.45)
    readonly property int labelCells: Math.max(16, Math.min(30, Math.floor(width / cw * 0.2)))
    readonly property int figureCells: 17
    readonly property int wasCells: compared ? 16 : 0
    readonly property int cells: Math.max(8, Math.floor(width / cw) - labelCells - figureCells - wasCells - 2)
    readonly property real labelWidth: labelCells * cw
    readonly property real axis: Math.max(1, estimate.axis || 1) * 1.04
    readonly property bool active: estimate.active === true
    readonly property real elapsed: estimate.elapsed || 0
    readonly property int tickStep: Format.tickStep(axis, Math.max(3, Math.floor(cells / 9)))

    implicitHeight: ch + 4 + rows.implicitHeight + (skippedLine ? rowHeight : 0)

    function cell(seconds) { return Math.max(0, Math.min(cells, Math.round(seconds / axis * cells))) }
    function run(from, to, glyph, least) {
        const a = cell(from), b = Math.max(a + least, cell(to))
        return " ".repeat(a) + glyph.repeat(Math.max(0, Math.min(cells, b) - a))
    }

    // The axis, and its marks down through the rows.
    Repeater {
        model: Math.floor(timeline.axis / timeline.tickStep) + 1
        delegate: Item {
            required property int index
            x: timeline.labelWidth + timeline.cell(index * timeline.tickStep) * timeline.cw
            Rectangle { y: timeline.ch + 2; width: 1; height: rows.implicitHeight + 2; color: theme.line }
            Mono {
                x: index === 0 ? 0 : -width / 2
                text: Format.tick(index * timeline.tickStep)
                color: theme.faint
            }
        }
    }
    Mono {
        visible: timeline.compared
        anchors.right: parent.right
        text: "before, " + (timeline.previous.branch || "main")
        color: theme.faint
    }

    Column {
        id: rows
        y: timeline.ch + 4
        width: parent.width

        Repeater {
            model: timeline.shown
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool current: modelData.id === timeline.selectedJobId
                readonly property var forecast: (timeline.estimate.jobs || {})[modelData.key] || ({})
                readonly property var was: (timeline.previous.jobs || {})[modelData.key] || ({})
                readonly property string jobState: modelData.state
                readonly property bool started: modelData.start >= 0 && jobState !== "skipped"
                readonly property bool running: jobState === "running"
                readonly property bool waiting: jobState === "queued" || jobState === "pending"
                readonly property real from: started ? modelData.start : (forecast.start >= 0 ? forecast.start : -1)
                readonly property real until: running ? timeline.elapsed : modelData.end
                readonly property bool forecastShown: timeline.active && forecast.end > 0 && forecast.typical >= 0
                                                      && (running || waiting)
                readonly property real barY: Math.round((height - timeline.ch) / 2) - 1

                width: rows.width
                height: timeline.rowHeight
                radius: Math.min(4, theme.radius)
                color: current ? theme.raised : area.containsMouse && modelData.id > 0 ? theme.hover : "transparent"

                Rectangle { width: Math.max(2, Math.round(timeline.cw / 3)); height: parent.height; color: theme.accent; visible: row.current }

                StatusIcon { x: timeline.cw; y: row.barY; state: row.jobState }
                Row {
                    x: timeline.cw * 3
                    y: row.barY
                    width: timeline.labelWidth - timeline.cw * 4
                    clip: true
                    Mono {
                        id: nameText
                        width: Math.min(implicitWidth, parent.width)
                        text: modelData.name
                        color: row.jobState === "skipped" || row.jobState === "pending" ? theme.dim : theme.text
                        font.bold: row.current
                        elide: Text.ElideRight
                    }
                    // Which workflow, when the build has more than one.
                    Mono {
                        visible: modelData.workflow !== "" && width > timeline.cw * 3
                        width: Math.max(0, parent.width - nameText.width)
                        text: " " + (modelData.workflow || "")
                        color: theme.faint
                        elide: Text.ElideRight
                    }
                }

                Item {
                    x: timeline.labelWidth
                    y: row.barY
                    width: timeline.cells * timeline.cw
                    height: timeline.ch

                    // Where the same job ran in the build before: a low
                    // line that shows under and beside the bar.
                    Blocks {
                        visible: timeline.compared && row.was.thenEnd > 0
                        eighth: true
                        y: timeline.ch + 2
                        from: timeline.cell(row.was.thenStart)
                        cells: Math.max(1, timeline.cell(row.was.thenEnd) - from)
                        color: row.was.thenState === "failure" ? theme.bad : theme.dim
                    }
                    // What is still expected: from now, or from where the job
                    // usually starts, to where it usually ends.
                    Blocks {
                        visible: row.forecastShown
                        from: timeline.cell(row.running ? timeline.elapsed : Math.max(row.from, 0))
                        cells: Math.max(0, timeline.cell(row.forecast.end) - from)
                        color: theme.accent
                        shade: row.waiting ? 0.25 : 0.4
                    }
                    // How much later it ends when the job is slow.
                    Mono {
                        visible: row.forecastShown && row.forecast.high > row.forecast.end
                        text: visible ? timeline.run(row.forecast.end, row.forecast.high, "╌", 0) : ""
                        color: theme.accent
                        opacity: 0.7
                    }
                    // What happened.
                    Blocks {
                        visible: row.started
                        from: timeline.cell(modelData.start)
                        cells: Math.max(1, timeline.cell(row.until) - from)
                        color: row.running ? theme.accent
                             : row.jobState === "success" ? theme.ok
                             : row.jobState === "failure" ? theme.bad : theme.faint
                    }
                }

                // How long the job took in the build before, and whether
                // that is a difference worth a colour.
                Mono {
                    visible: timeline.compared
                    anchors.right: parent.right
                    anchors.rightMargin: timeline.cw
                    y: row.barY
                    color: row.was.verdict === "broke" ? theme.bad
                         : row.was.verdict === "slower" ? theme.warn
                         : row.was.verdict === "faster" || row.was.verdict === "fixed" ? theme.ok : theme.faint
                    text: {
                        const verdict = row.was.verdict || ""
                        if (verdict === "new") return "new"
                        if (verdict === "broke") return row.was.then >= 0 ? "passed, " + Format.duration(row.was.then) : "broke"
                        if (verdict === "fixed") return "failed then"
                        if (!(row.was.then >= 0)) return row.was.thenState === "skipped" ? "skipped" : ""
                        const arrow = verdict === "slower" ? "▲ " : verdict === "faster" ? "▼ " : ""
                        return arrow + Format.duration(row.was.then)
                    }
                }
                Mono {
                    anchors.right: parent.right
                    anchors.rightMargin: timeline.cw * (1 + timeline.wasCells)
                    y: row.barY
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

    Mono {
        visible: timeline.skippedLine
        x: timeline.cw
        y: rows.y + rows.implicitHeight + Math.round((timeline.rowHeight - timeline.ch) / 2)
        width: parent.width - timeline.cw * 2
        text: "⊘ skipped: " + timeline.skipped.map(job => job.name).join(", ")
        color: theme.faint
        elide: Text.ElideRight
    }

    // Now.
    Rectangle {
        visible: timeline.active
        x: timeline.labelWidth + Math.min(1, timeline.elapsed / timeline.axis) * timeline.cells * timeline.cw
        y: timeline.ch
        width: 1
        height: rows.implicitHeight + 6
        color: theme.text
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -timeline.ch
            width: nowText.implicitWidth + timeline.cw
            height: timeline.ch
            color: theme.text
            Mono { id: nowText; anchors.centerIn: parent; text: "now"; color: theme.background; font.bold: true }
        }
    }
}
