#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

// The Omarchy palette, followed live: the accent, and also the background,
// the text colour and the reds and greens, so the window is light on a light
// theme and its "passed" is the theme's own green.
class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QColor accent READ accentColor NOTIFY changed)
    Q_PROPERTY(QString accentForeground READ accentForeground NOTIFY changed)
    Q_PROPERTY(QColor background READ backgroundColor NOTIFY changed)
    Q_PROPERTY(QColor foreground READ foregroundColor NOTIFY changed)
    Q_PROPERTY(bool light READ light NOTIFY changed)
    Q_PROPERTY(QVariantMap colors READ colors NOTIFY changed)
    // The few colours the window is drawn in, mixed from the palette so they
    // sit right on any theme: surfaces a step away from the background, text
    // in three strengths, and what passed, failed and needs a look.
    Q_PROPERTY(QColor panel READ panel NOTIFY changed)
    Q_PROPERTY(QColor raised READ raised NOTIFY changed)
    Q_PROPERTY(QColor hover READ hover NOTIFY changed)
    Q_PROPERTY(QColor line READ line NOTIFY changed)
    Q_PROPERTY(QColor text READ text NOTIFY changed)
    Q_PROPERTY(QColor dim READ dim NOTIFY changed)
    Q_PROPERTY(QColor faint READ faint NOTIFY changed)
    Q_PROPERTY(QColor logBackground READ logBackground NOTIFY changed)
    Q_PROPERTY(QColor ok READ ok NOTIFY changed)
    Q_PROPERTY(QColor bad READ bad NOTIFY changed)
    Q_PROPERTY(QColor warn READ warn NOTIFY changed)
    Q_PROPERTY(QColor info READ info NOTIFY changed)
    Q_PROPERTY(QColor badSoft READ badSoft NOTIFY changed)
    Q_PROPERTY(QColor accentSoft READ accentSoft NOTIFY changed)

public:
    explicit Theme(const QString &currentDirectory = {}, QObject *parent = nullptr);

    QString accent() const { return m_colors.value("accent").toString(); }
    QString accentForeground() const;
    QString background() const { return m_colors.value("background").toString(); }
    QString foreground() const { return m_colors.value("foreground").toString(); }
    bool light() const;
    QVariantMap colors() const { return m_colors; }

    QColor color(const QString &name) const { return QColor(m_colors.value(name).toString()); }
    QColor accentColor() const { return color("accent"); }
    QColor backgroundColor() const { return color("background"); }
    QColor foregroundColor() const { return color("foreground"); }
    // `amount` of the way from one colour to the other.
    Q_INVOKABLE static QColor mix(const QColor &from, const QColor &to, double amount);
    QColor toward(double amount) const { return mix(color("background"), color("foreground"), amount); }
    QColor panel() const { return toward(.035); }
    QColor raised() const { return toward(.085); }
    QColor hover() const { return toward(.06); }
    QColor line() const { return toward(.13); }
    QColor text() const { return light() ? color("foreground") : mix(color("foreground"), Qt::white, .25); }
    QColor dim() const { return toward(.62); }
    QColor faint() const { return toward(.36); }
    QColor logBackground() const { return light() ? toward(.03) : mix(color("background"), Qt::black, .3); }
    QColor ok() const { return color("green"); }
    QColor bad() const { return color("red"); }
    QColor warn() const { return color("yellow"); }
    QColor info() const { return color("blue"); }
    QColor badSoft() const { return mix(color("background"), color("red"), .16); }
    QColor accentSoft() const { return mix(color("background"), color("accent"), .16); }

    // Every `name = "#rrggbb"` in a theme's colors.toml, quoted or bare.
    static QVariantMap readColors(const QString &path);
    static QString readAccent(const QString &path);

signals:
    void changed();

private:
    void reload();

    QString m_directory;
    QVariantMap m_colors;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};
