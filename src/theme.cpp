// Theme watching follows Omacut (MIT, David Heinemeier Hansson).
#include "theme.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <cmath>

// What the window looks like without Omarchy, and what a theme that leaves a
// colour out falls back to.
static QVariantMap defaults() {
    return {{"accent", "#FFD60A"}, {"background", "#0e0e10"}, {"foreground", "#e6e6e6"}, {"red", "#f87171"},
            {"green", "#4ade80"},  {"yellow", "#fbbf24"},     {"blue", "#7dd3fc"},       {"magenta", "#a5b4fc"}};
}

static double luminance(const QColor &c) {
    auto linear = [](double v) { return v <= .04045 ? v / 12.92 : std::pow((v + .055) / 1.055, 2.4); };
    return .2126 * linear(c.redF()) + .7152 * linear(c.greenF()) + .0722 * linear(c.blueF());
}

Theme::Theme(const QString &directory, QObject *parent)
    : QObject(parent),
      m_directory(directory.isEmpty() ? QDir::homePath() + "/.local/state/omarchy/current" : directory),
      m_colors(defaults()) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(80);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
    connect(&m_debounce, &QTimer::timeout, this, &Theme::reload);
    reload();
}

QVariantMap Theme::readColors(const QString &path) {
    QVariantMap colors;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return colors;
    static const QRegularExpression expression("^\\s*([A-Za-z_]+)\\s*=\\s*[\"']?(#[0-9a-fA-F]{6})[\"']?",
                                               QRegularExpression::MultilineOption);
    auto matches = expression.globalMatch(QString::fromUtf8(file.readAll()));
    while (matches.hasNext()) {
        const auto match = matches.next();
        colors.insert(match.captured(1), match.captured(2));
    }
    return colors;
}

QString Theme::readAccent(const QString &path) {
    return readColors(path).value("accent", "#FFD60A").toString();
}

QColor Theme::mix(const QColor &from, const QColor &to, double amount) {
    return QColor::fromRgbF(from.redF() + (to.redF() - from.redF()) * amount,
                            from.greenF() + (to.greenF() - from.greenF()) * amount,
                            from.blueF() + (to.blueF() - from.blueF()) * amount);
}

// Black or white, whichever reads on the accent (WCAG relative luminance).
QString Theme::accentForeground() const {
    return luminance(QColor(accent())) > .179 ? "black" : "white";
}

bool Theme::light() const {
    return luminance(QColor(background())) > .4;
}

void Theme::reload() {
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);

    // A theme switch replaces symlinks and files, so watch the parents too and
    // re-arm after every change. Watching the nearest existing ancestor means
    // installing Omarchy later works without restarting the app.
    QString ancestor = m_directory;
    while (!QFileInfo::exists(ancestor) && ancestor != "/")
        ancestor = QFileInfo(ancestor).absolutePath();
    QStringList candidates{ancestor, QFileInfo(ancestor).absolutePath(), m_directory,
                           m_directory + "/theme", m_directory + "/theme/colors.toml"};
    candidates.removeDuplicates();
    for (const auto &path : candidates)
        if (QFileInfo::exists(path))
            m_watcher.addPath(path);

    auto colors = defaults();
    const auto read = readColors(m_directory + "/theme/colors.toml");
    // A theme that sets its own background but not its own text gets text
    // that reads on it, not the fallback's.
    if (read.contains("background") && !read.contains("foreground"))
        colors["foreground"] = luminance(QColor(read["background"].toString())) > .4 ? "#1a1a1a" : "#e6e6e6";
    for (auto it = read.cbegin(); it != read.cend(); ++it)
        colors.insert(it.key(), it.value());
    if (colors != m_colors) {
        m_colors = colors;
        emit changed();
    }
}
