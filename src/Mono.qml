import QtQuick

// Text on the grid: the desktop's monospace font at the one size the whole
// window is drawn in, and always plain, so nothing in a log or a commit
// title is ever read as markup.
Text {
    font.family: theme.font
    font.pixelSize: theme.textSize
    // Hinted to whole pixels, as a terminal does it: every character is
    // exactly one cell wide, so block characters join without a seam.
    font.hintingPreference: Font.PreferFullHinting
    renderType: Text.NativeRendering
    color: theme.text
    textFormat: Text.PlainText
}
