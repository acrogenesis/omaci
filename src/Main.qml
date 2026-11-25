import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "format.js" as Format

ApplicationWindow {
    id: win
    width: 1440
    height: 900
    minimumWidth: 980
    minimumHeight: 600
    visible: true
    // The answer in the title too, where the compositor and the window
    // switcher show it without the window being in front.
    title: "CI Watch · " + backend.repo + (win.buildActive && win.headline ? " · " + win.headline : "")
    color: theme.background

    Material.theme: theme.light ? Material.Light : Material.Dark
    Material.accent: theme.accent
    Material.background: theme.background
    Material.foreground: theme.text

    readonly property string mono: "monospace"
    readonly property var build: backend.selectedBuild
    readonly property var job: backend.selectedJob
    readonly property var estimate: backend.estimate
    readonly property bool buildActive: build.state === "running" || build.state === "queued"

    property bool helpVisible: false
    // The log alone, for reading: the build and its timeline step aside.
    property bool tall: false
    property real now: Date.now()

    Timer { interval: 1000; running: true; repeat: true; onTriggered: win.now = Date.now() }

    function seconds(from, to) {
        if (!from) return 0
        const end = to ? new Date(to).getTime() : win.now
        return Math.max(0, Math.round((end - new Date(from).getTime()) / 1000))
    }
    function ago(iso) {
        const s = seconds(iso)
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m ago"
        if (s < 86400) return Math.floor(s / 3600) + "h ago"
        return Math.floor(s / 86400) + "d ago"
    }
    function stateColor(state) {
        return state === "success" ? theme.ok : state === "failure" ? theme.bad
             : state === "running" || state === "queued" ? theme.accent : theme.dim
    }

    // The answer to "how is it going", in a few words.
    readonly property string headline: {
        const e = win.estimate
        if (!win.build.key) return ""
        if (!win.buildActive) {
            const took = Format.duration(win.build.seconds)
            return ({ "success": "Passed in " + took, "failure": "Failed after " + took,
                      "cancelled": "Cancelled after " + took, "skipped": "Skipped" })[win.build.state] || "Finished in " + took
        }
        if (!e.known) return "Running for " + Format.duration(e.elapsed)
        if (e.late) return "Taking longer than usual"
        if (e.remaining < 3) return "Any moment now"
        return "About " + Format.duration(e.remainingRounded) + " left"
    }
    // What that answer rests on.
    readonly property string basis: {
        const e = win.estimate
        if (!win.build.key) return ""
        const usually = e.usualKnown
            ? "Usually " + Format.duration(e.usual) + (e.usualHigh - e.usualLow >= 2
                ? ", between " + Format.duration(e.usualLow) + " and " + Format.duration(e.usualHigh) : "")
            : ""
        if (!win.buildActive) {
            if (!e.usualKnown) return ""
            const delta = win.build.seconds - e.usual
            const compared = win.build.state !== "success" ? ""
                : Math.abs(delta) < Math.max(5, e.usual * 0.05) ? "  ·  about as long as usual"
                : delta > 0 ? "  ·  " + Format.duration(delta) + " slower than usual"
                            : "  ·  " + Format.duration(-delta) + " faster than usual"
            return usually + compared
        }
        if (!e.known)
            return "No estimate yet: fewer than three earlier builds like this one have passed"
        if (e.late)
            return Format.duration(e.elapsed) + " so far, " + Format.duration(e.over) + " over the usual"
        if (e.basis === "jobs")
            return (e.usualKnown ? "Usually " + Format.duration(e.usual) + "  ·  this one " : "This one ")
                 + "between " + Format.duration(e.low) + " and " + Format.duration(e.high)
                 + ", going by the jobs of the last " + e.samples + " builds like it"
        return usually + ", going by " + e.samples + " earlier builds"
    }

    // Where the log is, and what moved it there.
    function scrollLogBy(pages) {
        logView.scripted = true
        logView.contentY = Math.max(logView.originY, Math.min(logView.contentY + pages * logView.height * 0.9,
                                    logView.originY + logView.contentHeight - logView.height))
        logView.scripted = false
        logView.follow = logView.nearEnd
        backend.selectStep(-1)
    }
    // Puts a line near the top of the view, with a little of what came
    // before it, so what follows from it is what you see.
    function jumpToLine(index, context) {
        if (index < 0) return
        logView.follow = false
        logView.highlighted = index
        logView.scripted = true
        followAnimation.stop()
        logView.positionViewAtIndex(Math.max(0, index - context), ListView.Beginning)
        logView.scripted = false
    }
    function jumpToStep(index) {
        const step = backend.steps[index]
        if (!step || step.line < 0) return
        backend.selectStep(index)
        win.jumpToLine(step.line, 0)
    }
    function moveStep(delta) {
        const from = backend.selectedStep >= 0 ? backend.selectedStep : logView.readingStep
        const index = backend.moveStep(delta > 0 ? from : (from < 0 ? backend.steps.length : from), delta)
        if (index >= 0) win.jumpToLine(backend.steps[index].line, 0)
    }
    property int failureIndex: -1
    function jumpToFailure(index) {
        const failures = backend.failures
        if (failures.length === 0) return
        win.failureIndex = (index + failures.length) % failures.length
        const failure = failures[win.failureIndex]
        backend.selectStep(-1)
        // The first failure of a block shows the block from its heading.
        win.jumpToLine(failure.line, Math.min(2, failure.line - failure.first))
    }
    function copyLink() {
        const url = backend.copyLink()
        toast.show(url ? "Copied " + url : "Nothing to link to yet")
    }
    function copyFailure() {
        toast.show(backend.copyFailure() ? "Copied the failure and its link" : "This job has no failure to copy")
    }
    function openOnGitHub() {
        const url = backend.openUrl()
        if (url) Qt.openUrlExternally(url)
    }
    // For screenshots: main.cpp walks the window through a scene.
    function scene(step) {
        if (step === "help") win.helpVisible = true
        else if (step === "tall") win.tall = true
        else if (step === "failure+") win.jumpToFailure(win.failureIndex + 1)
        else if (step === "step+") win.moveStep(1)
        else if (step === "end") { logView.follow = true; logView.toEnd(false) }
        else if (step === "previous") backend.selectPrevious()
    }

    Shortcut { sequence: "?"; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut {
        sequence: "Esc"
        onActivated: win.helpVisible ? win.helpVisible = false : win.tall = false
    }
    Shortcut { sequence: "Q"; onActivated: Qt.quit() }
    Shortcut { sequences: ["Space", "R", "Ctrl+R"]; onActivated: backend.refresh() }
    Shortcut { sequences: ["J", "Down"]; onActivated: backend.moveBuild(1) }
    Shortcut { sequences: ["K", "Up"]; onActivated: backend.moveBuild(-1) }
    Shortcut { sequences: ["L", "Right", "Tab"]; onActivated: backend.moveJob(1) }
    Shortcut { sequences: ["H", "Left", "Shift+Tab"]; onActivated: backend.moveJob(-1) }
    Shortcut { sequence: "N"; onActivated: win.moveStep(1) }
    Shortcut { sequence: "P"; onActivated: win.moveStep(-1) }
    Shortcut { sequence: "E"; onActivated: win.jumpToFailure(win.failureIndex + 1) }
    Shortcut { sequence: "Shift+E"; onActivated: win.jumpToFailure(win.failureIndex - 1) }
    Shortcut { sequence: "C"; onActivated: win.copyLink() }
    Shortcut { sequence: "Y"; onActivated: win.copyFailure() }
    Shortcut { sequence: "Shift+C"; onActivated: { backend.copyLog(); toast.show("Copied the whole log") } }
    Shortcut { sequences: ["O", "Return"]; onActivated: win.openOnGitHub() }
    Shortcut { sequence: "Z"; onActivated: win.tall = !win.tall }
    Shortcut { sequence: "B"; onActivated: backend.selectPrevious() }
    Shortcut { sequence: "F"; onActivated: backend.toggleBranch() }
    Shortcut { sequence: "S"; onActivated: backend.toggleSkipped() }
    Shortcut { sequence: "PgDown"; onActivated: win.scrollLogBy(1) }
    Shortcut { sequence: "PgUp"; onActivated: win.scrollLogBy(-1) }
    Shortcut { sequence: "Home"; onActivated: { logView.follow = false; backend.selectStep(-1); logView.positionViewAtBeginning() } }
    Shortcut { sequence: "End"; onActivated: { logView.follow = true; backend.selectStep(-1); logView.toEnd(true) } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Which repository, what is filtered, how fresh the data is.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            color: theme.panel

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 10

                Text { text: backend.repo; textFormat: Text.PlainText; color: theme.text; font.pixelSize: 15; font.bold: true }
                ActionButton {
                    label: backend.branchFilter ? "Only " + backend.branchFilter : "All branches"
                    key: "F"
                    enabled: backend.branchFilter !== "" || win.build.branch !== undefined
                    onClicked: backend.toggleBranch()
                }
                ActionButton {
                    label: backend.showSkipped ? "With skipped" : "Skipped hidden"
                    key: "S"
                    onClicked: backend.toggleSkipped()
                }
                Row {
                    spacing: 7
                    visible: backend.activeCount > 0
                    StatusIcon { state: "running"; size: 12; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: backend.activeCount + " running"; color: theme.accent; font.pixelSize: 13 }
                }
                Item { Layout.fillWidth: true }
                BusyIndicator { running: backend.busy; implicitWidth: 22; implicitHeight: 22; opacity: running ? 1 : 0 }
                ActionButton {
                    key: "R"
                    label: {
                        win.now
                        if (isNaN(backend.lastUpdated.getTime())) return "Loading…"
                        const s = Math.round((win.now - backend.lastUpdated.getTime()) / 1000)
                        return "Updated " + (s < 2 ? "just now" : s + "s ago")
                    }
                    onClicked: backend.refresh()
                }
                ActionButton { label: "Shortcuts"; key: "?"; onClicked: win.helpVisible = true }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.line }
        }

        // What went wrong, said plainly, instead of an empty window.
        Rectangle {
            Layout.fillWidth: true
            visible: backend.error !== ""
            implicitHeight: errorText.implicitHeight + 20
            color: theme.badSoft
            Text {
                id: errorText
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 16
                text: backend.error
                textFormat: Text.PlainText
                color: theme.text
                wrapMode: Text.Wrap
                font.pixelSize: 13
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Builds, newest first.
            ListView {
                id: buildList
                Layout.preferredWidth: Math.max(270, Math.min(330, win.width * 0.23))
                Layout.fillHeight: true
                clip: true
                model: backend.builds
                currentIndex: backend.selectedIndex
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    id: buildRow
                    required property var modelData
                    required property int index
                    readonly property bool current: modelData.key === backend.selectedKey
                    readonly property bool active: modelData.state === "running" || modelData.state === "queued"
                    readonly property real elapsed: { win.now; return win.seconds(modelData.startedAt) }
                    // The picked build has the better forecast; the others
                    // go by how long builds like them usually take.
                    readonly property real total: current && win.estimate.known ? win.estimate.total : (modelData.usual || 0)
                    width: ListView.view.width
                    height: 62
                    color: current ? theme.raised : (mouse.containsMouse ? theme.hover : "transparent")

                    Rectangle { width: 3; height: parent.height; color: theme.accent; visible: buildRow.current }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 14
                        spacing: 12

                        StatusIcon { state: modelData.failing ? "failure" : modelData.state; size: 16 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                textFormat: Text.PlainText
                                color: theme.text
                                font.pixelSize: 14
                                font.bold: buildRow.current
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.isBuild ? modelData.branch + " · " + modelData.sha
                                                        : modelData.workflows.join(", ") + " · " + modelData.event
                                textFormat: Text.PlainText
                                color: theme.dim
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                            }
                        }
                        ColumnLayout {
                            spacing: 3
                            Text { Layout.alignment: Qt.AlignRight; text: win.ago(modelData.startedAt); color: theme.dim; font.pixelSize: 12 }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: !buildRow.active ? Format.duration(modelData.seconds)
                                    : buildRow.total > buildRow.elapsed + 3 ? "~" + Format.duration(Math.round((buildRow.total - buildRow.elapsed) / 10) * 10) + " left"
                                    : Format.duration(buildRow.elapsed)
                                color: buildRow.active ? theme.accent : theme.dim
                                font.pixelSize: 12
                                font.family: win.mono
                            }
                        }
                    }
                    // How far a running build is, on the row itself.
                    Rectangle {
                        visible: buildRow.active
                        anchors.bottom: parent.bottom
                        x: 16
                        width: parent.width - 30
                        height: 2
                        radius: 1
                        color: theme.line
                        Rectangle {
                            height: parent.height
                            radius: 1
                            color: modelData.failing ? theme.bad : theme.accent
                            width: buildRow.total > 0 ? parent.width * Math.min(1, buildRow.elapsed / buildRow.total) : 0
                        }
                    }
                    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: backend.selectBuild(modelData.key) }
                }

                Text {
                    anchors.centerIn: parent
                    visible: buildList.count === 0 && !isNaN(backend.lastUpdated.getTime())
                    text: "No builds match this filter."
                    color: theme.dim
                }
            }

            Rectangle { Layout.fillHeight: true; width: 1; color: theme.line }

            // The picked build: how it is going, its jobs in time, and the
            // steps and log of one job.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                visible: backend.selectedKey !== ""

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 18
                    Layout.topMargin: 14
                    Layout.bottomMargin: 12
                    spacing: 10
                    visible: !win.tall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                spacing: 10
                                Layout.fillWidth: true
                                StatusIcon { state: win.build.failing ? "failure" : (win.build.state || "queued"); size: 20 }
                                Text {
                                    Layout.fillWidth: true
                                    text: win.build.title || ""
                                    textFormat: Text.PlainText
                                    color: theme.text
                                    font.pixelSize: 19
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                color: theme.dim
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: {
                                    const b = win.build
                                    if (!b.key) return ""
                                    win.now
                                    return [b.branch, b.sha, b.event, b.actor, (b.workflows || []).join(" + "),
                                            "started " + win.ago(b.startedAt)].filter(part => part).join("  ·  ")
                                }
                            }
                        }
                        ColumnLayout {
                            spacing: 4
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: win.headline
                                textFormat: Text.PlainText
                                color: win.buildActive ? (win.estimate.late ? theme.warn : win.build.failing ? theme.bad : theme.accent)
                                                       : win.stateColor(win.build.state)
                                font.pixelSize: 22
                                font.bold: true
                            }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: win.build.failing ? "A job has already failed; the rest is finishing" : ""
                                visible: text !== ""
                                color: theme.bad
                                font.pixelSize: 12
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 22

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            EtaBar {
                                Layout.fillWidth: true
                                active: win.buildActive
                                elapsed: win.estimate.elapsed || 0
                                typical: win.buildActive ? (win.estimate.known ? win.estimate.total : 0)
                                                         : (win.estimate.usualKnown ? win.estimate.usual : 0)
                                low: win.buildActive ? (win.estimate.low || 0) : (win.estimate.usualLow || 0)
                                high: win.buildActive ? (win.estimate.high || 0) : (win.estimate.usualHigh || 0)
                                fill: win.build.failing ? theme.bad : win.stateColor(win.build.state)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: win.buildActive ? Format.duration(win.estimate.elapsed || 0) + " so far" : ""
                                    color: theme.text
                                    font.pixelSize: 12
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: win.buildActive ? Text.AlignRight : Text.AlignLeft
                                    text: historyStrip.hovered !== "" ? historyStrip.hovered : win.basis
                                    textFormat: Text.PlainText
                                    color: theme.dim
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        ColumnLayout {
                            spacing: 5
                            visible: backend.history.length > 1
                            HistoryStrip {
                                id: historyStrip
                                Layout.preferredWidth: Math.min(280, Math.max(60, backend.history.length * 16))
                                Layout.preferredHeight: 30
                                Layout.alignment: Qt.AlignRight
                                builds: backend.history
                                currentSeconds: win.estimate.elapsed || 0
                                typical: win.estimate.usualKnown ? win.estimate.usual : 0
                                onPicked: key => backend.selectBuild(key)
                            }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: "Earlier builds like it"
                                color: theme.faint
                                font.pixelSize: 11
                            }
                        }
                    }

                    // The build main had before this one, to compare with,
                    // and the way to it.
                    Rectangle {
                        id: previousRow
                        readonly property var was: backend.previous
                        visible: was.key !== undefined
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 5
                        color: previousMouse.containsMouse ? theme.raised : theme.panel
                        border.width: 1
                        border.color: theme.line

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8
                            Text { text: "Before, on " + (previousRow.was.branch || ""); textFormat: Text.PlainText; color: theme.dim; font.pixelSize: 12 }
                            StatusIcon { state: previousRow.was.state || "queued"; size: 13 }
                            Text {
                                Layout.maximumWidth: previousRow.width * 0.3
                                text: previousRow.was.title || ""
                                textFormat: Text.PlainText
                                color: theme.text
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                textFormat: Text.PlainText
                                color: theme.dim
                                font.pixelSize: 12
                                text: {
                                    const was = previousRow.was
                                    if (!was.key) return ""
                                    win.now
                                    const verb = ({ "success": "passed in ", "failure": "failed after ", "cancelled": "cancelled after " })[was.state] || "took "
                                    return verb + Format.duration(was.seconds) + "  ·  " + win.ago(was.startedAt)
                                }
                            }
                            // What changed since: the job that broke, the
                            // ones that got slower, the whole build.
                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                readonly property var notes: previousRow.was.notes || []
                                readonly property bool alarming: notes.some(note => note.endsWith(" broke"))
                                color: alarming ? theme.bad : notes.some(note => note.endsWith(" slower")) ? theme.warn : theme.dim
                                text: {
                                    const was = previousRow.was
                                    if (!was.key) return ""
                                    if (!was.ready) return "·  fetching its jobs…"
                                    const parts = notes.slice(0, 3)
                                    if (was.notable && win.build.state === "success" && was.state === "success")
                                        parts.unshift("this build " + Format.duration(Math.abs(was.delta)) + (was.delta > 0 ? " slower" : " faster"))
                                    if (parts.length === 0 && backend.jobs.length > 0) return "·  no job stands out"
                                    return parts.length ? "·  " + parts.join(", ") : ""
                                }
                            }
                            Text { text: "Go to it"; color: theme.text; font.pixelSize: 12 }
                            Text { text: "B"; color: theme.dim; font.pixelSize: 11; font.family: win.mono }
                        }
                        MouseArea {
                            id: previousMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: backend.selectPrevious()
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: theme.line; visible: !win.tall }

                // The jobs, in time.
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(jobsTimeline.implicitHeight + 14, 22 + 8 * 26 + 14)
                    visible: !win.tall && backend.jobs.length > 0
                    contentHeight: jobsTimeline.implicitHeight + 14
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    JobsTimeline {
                        id: jobsTimeline
                        y: 6
                        width: parent.width
                        jobs: backend.jobs
                        estimate: win.estimate
                        previous: backend.previous
                        selectedJobId: backend.selectedJobId
                        onPicked: id => backend.selectJob(id)
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: theme.line; visible: !win.tall && backend.jobs.length > 0 }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // The steps of the picked job. Each one that wrote
                    // something is a way into the log.
                    Flickable {
                        Layout.preferredWidth: Math.max(220, Math.min(280, win.width * 0.19))
                        Layout.fillHeight: true
                        contentHeight: stepColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}

                        Column {
                            id: stepColumn
                            width: parent.width
                            topPadding: 6
                            bottomPadding: 8

                            Item {
                                width: parent.width
                                height: 30
                                Text {
                                    x: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 28
                                    text: win.job.name ? win.job.name + (backend.steps.length ? "  ·  " + backend.steps.length + " steps" : "") : ""
                                    textFormat: Text.PlainText
                                    color: theme.dim
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }

                            Repeater {
                                model: backend.steps
                                delegate: Rectangle {
                                    id: stepRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool reachable: modelData.line >= 0
                                    readonly property bool current: backend.selectedStep >= 0 ? backend.selectedStep === index
                                                                                              : logView.readingStep === index
                                    width: stepColumn.width
                                    height: 26
                                    color: current ? theme.raised : stepMouse.containsMouse && reachable ? theme.hover : "transparent"

                                    Rectangle { width: 3; height: parent.height; color: theme.accent; visible: stepRow.current }
                                    StatusIcon { x: 18; anchors.verticalCenter: parent.verticalCenter; state: modelData.state; size: 11 }
                                    Text {
                                        x: 38
                                        width: parent.width - 50 - stepTime.implicitWidth
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.name
                                        textFormat: Text.PlainText
                                        color: modelData.state === "failure" ? theme.bad
                                             : modelData.state === "running" ? theme.accent
                                             : modelData.state === "skipped" || modelData.state === "queued" ? theme.faint : theme.text
                                        font.pixelSize: 12
                                        font.bold: modelData.state === "failure"
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        id: stepTime
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: modelData.state === "running" ? theme.accent : theme.dim
                                        font.pixelSize: 11
                                        font.family: win.mono
                                        text: {
                                            if (modelData.state === "running") {
                                                win.now
                                                return Format.duration(win.seconds(modelData.startedAt))
                                                     + (modelData.usual >= 2 ? " / ~" + Format.duration(modelData.usual) : "")
                                            }
                                            return modelData.seconds >= 1 ? Format.duration(modelData.seconds) : ""
                                        }
                                    }
                                    MouseArea {
                                        id: stepMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: stepRow.reachable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: win.jumpToStep(stepRow.index)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillHeight: true; width: 1; color: theme.line }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        // What can be done with this job, each with its key.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            color: theme.panel
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 10
                                spacing: 8
                                Text {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    color: theme.dim
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    text: {
                                        if (!win.job.name) return ""
                                        const step = backend.steps[backend.selectedStep >= 0 ? backend.selectedStep : logView.readingStep]
                                        return win.job.name + (step ? "  ›  " + step.name : "") + (logView.count ? "  ·  " + logView.count + " lines" : "")
                                    }
                                }
                                ActionButton {
                                    visible: backend.failures.length > 0
                                    label: backend.failures.length > 1 ? "Next failure" : "Go to failure"
                                    key: "E"
                                    onClicked: win.jumpToFailure(win.failureIndex + 1)
                                }
                                ActionButton {
                                    visible: backend.failures.length > 0
                                    label: "Copy failure"
                                    key: "Y"
                                    onClicked: win.copyFailure()
                                }
                                ActionButton { label: "Copy link"; key: "C"; strong: true; onClicked: win.copyLink() }
                                ActionButton { label: "Open on GitHub"; key: "O"; onClicked: win.openOnGitHub() }
                                ActionButton { label: win.tall ? "Show build" : "Tall log"; key: "Z"; onClicked: win.tall = !win.tall }
                            }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.line }
                        }

                        // What failed, by name, before any scrolling.
                        Rectangle {
                            Layout.fillWidth: true
                            visible: backend.failures.length > 0
                            implicitHeight: failureColumn.implicitHeight + 16
                            color: theme.badSoft
                            Rectangle { width: 3; height: parent.height; color: theme.bad }
                            Column {
                                id: failureColumn
                                x: 16
                                y: 8
                                width: parent.width - 28
                                spacing: 2
                                Text {
                                    text: {
                                        const count = backend.failures.length
                                        let step = ""
                                        for (const s of backend.steps) if (s.state === "failure" && !step) step = s.name
                                        return (count === 1 ? "1 failure" : count + " failures") + (step ? " in " + step : "")
                                    }
                                    textFormat: Text.PlainText
                                    color: theme.bad
                                    font.pixelSize: 12
                                    font.bold: true
                                    bottomPadding: 2
                                }
                                Repeater {
                                    model: backend.failures.slice(0, 4)
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        width: failureColumn.width
                                        height: 22
                                        radius: 3
                                        color: failureMouse.containsMouse || win.failureIndex === index
                                               ? Qt.rgba(theme.bad.r, theme.bad.g, theme.bad.b, 0.16) : "transparent"
                                        Row {
                                            x: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 12
                                            Text {
                                                visible: modelData.location !== ""
                                                text: modelData.location
                                                textFormat: Text.PlainText
                                                color: theme.bad
                                                font.family: win.mono
                                                font.pixelSize: 12
                                            }
                                            Text {
                                                width: Math.max(80, failureColumn.width - 24 - (modelData.location !== "" ? x : 0))
                                                text: modelData.title + (modelData.detail ? "  ·  " + modelData.detail : "")
                                                textFormat: Text.PlainText
                                                color: theme.text
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MouseArea {
                                            id: failureMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.jumpToFailure(index)
                                        }
                                    }
                                }
                                Text {
                                    visible: backend.failures.length > 4
                                    x: 6
                                    text: "and " + (backend.failures.length - 4) + " more: E walks through all of them"
                                    color: theme.dim
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // The log, which follows the end while the job runs.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: theme.logBackground

                            ListView {
                                id: logView
                                // Following means staying at the bottom as lines arrive.
                                // Only a scroll the user makes decides it, by wheel, drag
                                // or scrollbar: scrolled to the end follows, scrolled up
                                // stops. The view also moves by itself while it lays out
                                // new lines, and that must not count as scrolling away.
                                property bool follow: true
                                property bool scripted: false
                                property int highlighted: -1

                                // The step whose lines are at the top of the view: the
                                // one being read, which the step list marks.
                                readonly property int readingStep: {
                                    backend.steps
                                    if (count === 0) return -1
                                    const top = indexAt(20, contentY + 30)
                                    return backend.log.stepAt(top < 0 ? 0 : top)
                                }

                                // Glides to the end rather than jumping, so new output
                                // scrolls into view the way it would in a terminal. A
                                // long way (a reload, a different job) goes at once.
                                function toEnd(animated) {
                                    scripted = true
                                    const from = contentY
                                    positionViewAtEnd()
                                    const to = contentY
                                    scripted = false
                                    if (!animated || to <= from || to - from > height * 2) {
                                        followAnimation.stop()
                                        return
                                    }
                                    scripted = true
                                    contentY = from
                                    followAnimation.from = from
                                    followAnimation.to = to
                                    followAnimation.restart()
                                }

                                NumberAnimation {
                                    id: followAnimation
                                    target: logView
                                    property: "contentY"
                                    duration: 450
                                    easing.type: Easing.OutCubic
                                    onRunningChanged: logView.scripted = running
                                }
                                onMovementStarted: { followAnimation.stop(); backend.selectStep(-1) }

                                // New lines slide in from the right and fade up, and
                                // the lines above them make room smoothly. A reload
                                // or a different job appears at once.
                                add: Transition {
                                    ParallelAnimation {
                                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 380; easing.type: Easing.OutQuad }
                                        NumberAnimation { property: "x"; from: 28; to: 0; duration: 420; easing.type: Easing.OutCubic }
                                    }
                                }
                                addDisplaced: Transition {
                                    NumberAnimation { property: "y"; duration: 300; easing.type: Easing.OutCubic }
                                }
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                model: backend.log
                                boundsBehavior: Flickable.StopAtBounds
                                reuseItems: true
                                ScrollBar.vertical: ScrollBar { id: logBar }
                                ScrollBar.horizontal: ScrollBar {}
                                flickableDirection: Flickable.AutoFlickIfNeeded
                                contentWidth: Math.max(width, 2400)

                                readonly property bool nearEnd: contentY + height >= originY + contentHeight - 24
                                onContentYChanged: if (!scripted && (moving || logBar.pressed)) follow = nearEnd
                                onCountChanged: if (follow) Qt.callLater(toEnd, true)

                                delegate: Item {
                                    id: logLine
                                    required property int index
                                    required property string time
                                    required property string text
                                    required property int kind
                                    required property string step
                                    required property int mark
                                    width: logView.contentWidth
                                    height: 19 + (step !== "" ? 30 : 0)

                                    // Where a step begins: a heading, so the log
                                    // reads as chapters.
                                    Item {
                                        visible: logLine.step !== ""
                                        width: logView.width
                                        height: 30
                                        Rectangle { y: 9; x: 6; width: parent.width - 20; height: 1; color: theme.line }
                                        Rectangle {
                                            x: 76
                                            y: 4
                                            width: headingText.implicitWidth + 16
                                            height: 20
                                            radius: 4
                                            color: theme.raised
                                            Text {
                                                id: headingText
                                                anchors.centerIn: parent
                                                text: logLine.step
                                                textFormat: Text.PlainText
                                                color: theme.text
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                        }
                                    }
                                    Rectangle {
                                        y: parent.height - 19
                                        width: parent.width
                                        height: 19
                                        color: logLine.index === logView.highlighted ? theme.accentSoft
                                             : logLine.mark === 2 ? Qt.rgba(theme.bad.r, theme.bad.g, theme.bad.b, 0.22)
                                             : logLine.mark === 1 ? Qt.rgba(theme.bad.r, theme.bad.g, theme.bad.b, 0.09)
                                             : logLine.kind === 2 ? Qt.rgba(theme.bad.r, theme.bad.g, theme.bad.b, 0.12) : "transparent"
                                        Rectangle { width: 3; height: parent.height; color: theme.bad; visible: logLine.mark > 0 }
                                        Text {
                                            x: 10
                                            width: 64
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: logLine.time
                                            color: theme.faint
                                            font.family: win.mono
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            x: 82
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (logLine.kind === 1 ? "▸ " : logLine.kind === 2 ? "Error: " : logLine.kind === 3 ? "Warning: " : "") + logLine.text
                                            textFormat: Text.PlainText
                                            color: logLine.mark === 2 ? theme.bad
                                                 : [theme.text, theme.accent, theme.bad, theme.warn, theme.info, theme.info][logLine.kind]
                                            font.family: win.mono
                                            font.pixelSize: 12
                                            font.bold: logLine.kind === 1 || logLine.kind === 2 || logLine.mark === 2
                                        }
                                    }
                                }
                            }

                            Connections {
                                target: backend.log
                                function onModelAboutToBeReset() { logView.scripted = true }
                                function onModelReset() {
                                    logView.scripted = false
                                    if (logView.follow) Qt.callLater(logView.toEnd)
                                }
                            }

                            Connections {
                                target: backend
                                function onLogReset() {
                                    logView.highlighted = -1
                                    win.failureIndex = -1
                                    // A failed job opens on what failed; anything
                                    // else on its end, which is where a running
                                    // job is writing.
                                    if (backend.failures.length > 0 && win.job.state === "failure") {
                                        Qt.callLater(win.jumpToFailure, 0)
                                    } else {
                                        logView.follow = true
                                        Qt.callLater(logView.toEnd)
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                width: parent.width * 0.7
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                visible: backend.logStatus !== "" && logView.count === 0
                                text: backend.logStatus
                                textFormat: Text.PlainText
                                color: theme.dim
                                font.pixelSize: 14
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 16
                                readonly property bool shown: !logView.follow && win.job.state === "running"
                                opacity: shown ? 1 : 0
                                visible: opacity > 0
                                anchors.bottomMargin: shown ? 16 : -8
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                                Behavior on anchors.bottomMargin { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                                radius: 6
                                color: theme.accent
                                implicitWidth: followText.implicitWidth + 20
                                implicitHeight: 28
                                Text { id: followText; anchors.centerIn: parent; text: "End  follow the log"; color: theme.accentForeground; font.pixelSize: 12 }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { logView.follow = true; backend.selectStep(-1); logView.toEnd(true) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A short confirmation for actions with no visible result, like copying.
    Rectangle {
        id: toast
        function show(message) { toastText.text = message; opacity = 1; toastTimer.restart() }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        radius: 8
        color: theme.accent
        opacity: 0
        visible: opacity > 0
        implicitWidth: Math.min(parent.width - 60, toastText.implicitWidth + 28)
        implicitHeight: 34
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Text {
            id: toastText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 28)
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            color: theme.accentForeground
            font.pixelSize: 13
            font.bold: true
        }
        Timer { id: toastTimer; interval: 2200; onTriggered: toast.opacity = 0 }
    }

    // Every shortcut, on ?.
    Rectangle {
        anchors.fill: parent
        color: "#cc000000"
        visible: win.helpVisible
        MouseArea { anchors.fill: parent; onClicked: win.helpVisible = false }

        Rectangle {
            anchors.centerIn: parent
            width: 780
            height: helpGrid.implicitHeight + 76
            radius: 10
            color: theme.panel
            border.color: theme.line

            Text { x: 28; y: 22; text: "Shortcuts"; color: theme.text; font.pixelSize: 17; font.bold: true }
            Grid {
                id: helpGrid
                x: 28
                y: 58
                columns: 2
                columnSpacing: 36
                rowSpacing: 7
                flow: Grid.TopToBottom
                rows: 10
                Repeater {
                    model: [
                        ["J / ↓", "Next build"], ["K / ↑", "Previous build"],
                        ["L / → / Tab", "Next job"], ["H / ← / Shift+Tab", "Previous job"],
                        ["N / P", "Next, previous step in the log"],
                        ["E / Shift+E", "Next, previous failure"],
                        ["C", "Copy the link of the job"],
                        ["Y", "Copy the failure and its link"],
                        ["Shift+C", "Copy the whole log"],
                        ["O / Enter", "Open the job on GitHub"],
                        ["B", "The previous build on main"],
                        ["Z", "Tall log, and back"],
                        ["F", "Only this branch, and back"],
                        ["S", "Show or hide skipped builds"],
                        ["PgUp / PgDn", "Scroll the log"],
                        ["Home / End", "Top of the log, follow the end"],
                        ["Space / R / Ctrl+R", "Refresh now"],
                        ["Esc", "Close this, or leave the tall log"],
                        ["?", "Show or hide this help"], ["Q", "Quit"]
                    ]
                    delegate: Row {
                        required property var modelData
                        Text { width: 160; text: modelData[0]; color: theme.accent; font.family: win.mono; font.pixelSize: 13 }
                        Text { width: 184; text: modelData[1]; color: theme.text; font.pixelSize: 13 }
                    }
                }
            }
        }
    }
}
