import QtQuick
import QtQuick.Controls

// A scroll bar as a terminal would have one: a plain bar, half a character
// wide, that is only there when there is something to scroll.
ScrollBar {
    id: bar
    // The log is always wider than its panel, so its sideways bar only
    // shows while it is being used.
    property bool quiet: false
    padding: 0
    minimumSize: 0.06
    contentItem: Rectangle {
        implicitWidth: Math.max(4, Math.round(theme.cellWidth / 2))
        implicitHeight: Math.max(4, Math.round(theme.cellWidth / 2))
        radius: Math.min(4, theme.radius)
        color: bar.pressed ? theme.accent : theme.faint
        opacity: bar.size >= 1 || (bar.quiet && !bar.active) ? 0 : (bar.pressed || bar.hovered ? 1 : 0.6)
    }
    background: Item {}
}
