.pragma library

// "7m 12s": how long something took or will take.
function duration(seconds) {
    const s = Math.max(0, Math.round(seconds))
    if (s < 60) return s + "s"
    if (s < 3600) return Math.floor(s / 60) + "m " + (s % 60 ? (s % 60) + "s" : "").trim()
    return Math.floor(s / 3600) + "h " + Math.floor(s % 3600 / 60) + "m"
}

// "2m": a point on a time axis.
function tick(seconds) {
    if (seconds === 0) return "0"
    if (seconds < 60) return seconds + "s"
    if (seconds % 60 === 0) return (seconds / 60) + "m"
    return Math.floor(seconds / 60) + "m" + (seconds % 60) + "s"
}

// A step between the marks of a time axis that gives at most `most` of them.
function tickStep(span, most) {
    for (const step of [5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200])
        if (span / step <= most) return step
    return 14400
}
