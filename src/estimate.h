#pragma once

#include <QHash>
#include <QList>
#include <QString>
#include <QVariantList>

// How long a build will still take, worked out from how long earlier builds
// took. Nothing here knows about GitHub, processes or the clock: it is given
// the jobs as they are now, the earlier builds, and the time, and the tests
// check what comes out.
namespace Estimate {

double quantile(QList<double> values, double q);

// The earlier builds this one is compared with, newest first: finished,
// older, and like it. On the same branch when there are at least three,
// otherwise started by the same kind of event, otherwise all of them.
QVariantList likeBuilds(const QVariantList &builds, const QVariantMap &build, int most = 16);

struct Spread {
    int samples = 0;
    double low = 0, typical = 0, high = 0; // Lower quartile, median, upper quartile.
    bool known() const { return samples >= 3; }
};
// The spread of how long the builds that passed took.
Spread spread(const QVariantList &like);

// One job, with times in seconds since its build started. -1 is unknown.
struct Job {
    QString key;
    QString state; // running, queued, success, failure, cancelled, skipped, pending.
    double start = -1;
    double end = -1;
};

// One earlier build: the jobs that ran in it.
using Earlier = QHash<QString, Job>;

struct JobForecast {
    QString key;
    bool expected = false; // Not created by GitHub yet; known from earlier builds.
    double start = -1;     // Known or forecast.
    double end = -1;
    double low = -1, high = -1; // The end with every job quick, and with every job slow.
    double typical = -1;        // How long this job usually takes.
    bool late = false;          // Running for longer than it usually does.
};

struct Forecast {
    bool known = false;
    QString basis;   // "jobs" when played forward job by job, "builds" from whole builds.
    int samples = 0; // How many earlier builds it rests on.
    double elapsed = 0;
    double total = 0, low = 0, high = 0; // The build's whole length.
    // Past the slow end of what earlier builds did, and by how much past the
    // usual: said out loud instead of promising "0s left" for minutes.
    bool late = false;
    double over = 0;
    QList<JobForecast> jobs;
};

Forecast forecast(const QList<Job> &jobs, double elapsed, const Spread &builds, const QList<Earlier> &earlier);

// "about 3m 50s": rounded to what a forecast can be trusted to.
int rounded(double seconds);

}
