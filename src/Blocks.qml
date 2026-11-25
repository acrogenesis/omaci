import QtQuick

// A run of block characters, drawn the way terminals draw them: not from the
// font, whose blocks are a hair narrower than a cell and leave seams, but as
// the cells themselves. `shade` is 1 for █, about a half for ▒ and a quarter
// for ░; `eighth` draws only the bottom eighth, which is ▁.
Rectangle {
    property real from: 0     // In cells.
    property real cells: 0    // May end part of the way into a cell.
    property real shade: 1
    property bool eighth: false

    x: Math.round(from * theme.cellWidth)
    y: eighth ? theme.cellHeight - height : 1
    width: Math.max(0, Math.round(cells * theme.cellWidth))
    height: eighth ? Math.max(2, Math.round(theme.cellHeight / 8)) : theme.cellHeight - 2
    opacity: shade
    visible: width > 0
}
