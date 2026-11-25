#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantList>

#include "estimate.h"

// This build next to the one main had before it: which job broke, which got
// slower, and by how much. Like the estimate, it is given plain numbers and
// knows nothing about GitHub or the clock.
namespace Compare {

// The build to compare with: the newest finished build on `branch` that
// started before this one. Whatever its result; a red main is worth knowing.
QVariantMap previous(const QVariantList &builds, const QVariantMap &build, const QString &branch);

struct Row {
    QString key;
    QString nowState, thenState;
    double now = -1;  // How long the job has taken, or took. -1 when it didn't run.
    double then = -1; // The same job in the earlier build.
    double thenStart = -1, thenEnd = -1;
    double delta = 0; // now - then, when both ran.
    // broke: failed now, didn't then. fixed: the other way round. slower,
    // faster, same: both finished. new: no such job then. Empty: nothing to
    // say yet (still running and not past the earlier time, or skipped).
    QString verdict;
};

// One row per job of this build, in the same order. A job's `end` is where it
// is now when it is still running.
QList<Row> jobs(const QList<Estimate::Job> &now, const QList<Estimate::Job> &then);

// "test broke", "build 58s slower": what is worth saying in one line, the
// worst first. Empty when nothing stands out.
QStringList notes(const QList<Row> &rows);

// Whether a difference is worth mentioning: more than five seconds and more
// than fifteen percent.
bool notable(double now, double then);

}
