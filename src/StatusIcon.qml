import QtQuick

// The state of a build, job, or step as one character. A running one turns
// through the braille spinner, so a glance says whether anything still moves.
Mono {
    id: icon
    property string state: "queued"
    property int frame: 0

    readonly property var frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    width: Math.ceil(theme.cellWidth)
    horizontalAlignment: Text.AlignHCenter
    font.bold: state === "success" || state === "failure"
    color: ({
        "success": theme.ok,
        "failure": theme.bad,
        "running": theme.accent,
        "queued": theme.dim,
        "pending": theme.faint,
        "cancelled": theme.dim,
        "skipped": theme.faint,
        "neutral": theme.dim
    })[state] || theme.dim
    text: state === "running" ? frames[frame % frames.length]
        : ({ "success": "✓", "failure": "✗", "queued": "○", "pending": "◌",
             "cancelled": "–", "skipped": "⊘", "neutral": "–" })[state] || "○"

    Timer {
        interval: 90
        repeat: true
        running: icon.state === "running" && icon.visible
        onTriggered: icon.frame = (icon.frame + 1) % icon.frames.length
    }
}
