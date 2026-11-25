import QtQuick

// The state of a build, job, or step as one mark, drawn rather than typed so
// it looks the same whatever fonts are installed. A running one turns, so a
// glance at the window says whether anything is still moving.
Item {
    id: icon
    property string state: "queued"
    property int size: 16

    implicitWidth: size
    implicitHeight: size

    readonly property color tint: ({
        "success": theme.ok,
        "failure": theme.bad,
        "running": theme.accent,
        "queued": theme.dim,
        "pending": theme.faint,
        "cancelled": theme.dim,
        "skipped": theme.faint,
        "neutral": theme.dim
    })[state] || theme.dim

    onTintChanged: canvas.requestPaint()
    onStateChanged: canvas.requestPaint()
    onSizeChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        RotationAnimator on rotation {
            running: icon.state === "running" && icon.visible
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 1100
            onRunningChanged: if (!running) canvas.rotation = 0
        }

        onPaint: {
            const c = getContext("2d")
            const s = icon.size, m = s / 2
            const stroke = Math.max(1.5, s / 8)
            c.reset()
            c.lineCap = "round"
            c.lineJoin = "round"

            if (icon.state === "running") {
                // A faint ring with a bright arc going round it.
                c.lineWidth = stroke
                c.strokeStyle = Qt.rgba(icon.tint.r, icon.tint.g, icon.tint.b, 0.25)
                c.beginPath(); c.arc(m, m, m - stroke / 2, 0, Math.PI * 2); c.stroke()
                c.strokeStyle = icon.tint
                c.beginPath(); c.arc(m, m, m - stroke / 2, -Math.PI / 2, Math.PI * 0.35); c.stroke()
                return
            }
            if (icon.state === "queued" || icon.state === "skipped" || icon.state === "pending") {
                c.lineWidth = stroke
                c.strokeStyle = icon.tint
                if (icon.state === "pending")
                    c.setLineDash([1.6, 1.6])
                c.beginPath(); c.arc(m, m, m - stroke / 2, 0, Math.PI * 2); c.stroke()
                if (icon.state === "skipped") {
                    c.setLineDash([])
                    c.beginPath(); c.moveTo(s * 0.3, s * 0.7); c.lineTo(s * 0.7, s * 0.3); c.stroke()
                }
                return
            }

            c.fillStyle = icon.tint
            c.beginPath(); c.arc(m, m, m, 0, Math.PI * 2); c.fill()
            c.strokeStyle = theme.background
            c.lineWidth = Math.max(1.5, s / 7)
            c.beginPath()
            if (icon.state === "success") {
                c.moveTo(s * 0.28, s * 0.53); c.lineTo(s * 0.44, s * 0.68); c.lineTo(s * 0.73, s * 0.34)
            } else if (icon.state === "failure") {
                c.moveTo(s * 0.33, s * 0.33); c.lineTo(s * 0.67, s * 0.67)
                c.moveTo(s * 0.67, s * 0.33); c.lineTo(s * 0.33, s * 0.67)
            } else {
                c.moveTo(s * 0.3, m); c.lineTo(s * 0.7, m)
            }
            c.stroke()
        }
    }
}
