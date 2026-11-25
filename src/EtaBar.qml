import QtQuick

// "How far is it" in characters. Full blocks are the time gone, the light
// shade is what is left up to the slow end of what earlier builds did, the
// medium shade is the band they ended in, and the bar is where one usually
// ends: ████████████░░░░░░░░▒▒▒┃▒▒
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
    readonly property int cells: Math.max(4, Math.floor(width / theme.cellWidth))
    implicitHeight: theme.cellHeight

    function cell(seconds) { return Math.max(0, Math.min(cells, seconds / span * cells)) }

    readonly property bool banded: known && high > low
    readonly property int bandFrom: Math.floor(cell(low))
    readonly property int bandTo: Math.max(bandFrom + 1, Math.ceil(cell(high)))

    // What is left, and in it the band the earlier builds ended in.
    Blocks { cells: bar.cells; color: theme.dim; shade: 0.28 }
    Blocks { visible: bar.banded; from: bar.bandFrom; cells: bar.bandTo - bar.bandFrom; color: theme.dim; shade: 0.45 }
    // What is gone, to an eighth of a character.
    Blocks {
        visible: bar.known || !bar.active
        cells: Math.floor(bar.cell(bar.elapsed) * 8) / 8
        color: bar.fill
    }
    // No estimate: a few blocks that travel, which says "working" without
    // claiming to know how far.
    Mono {
        id: traveller
        property real at: 0
        visible: bar.active && !bar.known
        x: Math.floor(at) * theme.cellWidth
        color: bar.fill
        text: "▓▓▓▓▓▓"
        opacity: 0
        Blocks { cells: 6; color: bar.fill; shade: 0.8; parent: traveller.parent; x: traveller.x }
        NumberAnimation on at {
            running: traveller.visible
            loops: Animation.Infinite
            from: 0
            to: Math.max(1, bar.cells - 6)
            duration: 2400
        }
    }
    // Where a build like this usually ends.
    Mono {
        visible: bar.known
        x: Math.min(bar.cells - 1, Math.floor(bar.cell(bar.typical))) * theme.cellWidth
        color: theme.text
        font.bold: true
        text: "┃"
    }
}
