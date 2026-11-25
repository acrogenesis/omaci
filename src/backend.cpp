#include "backend.h"

#include <QClipboard>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

#include "demo.h"
#include "github.h"

// Poll every few seconds while a build is moving, and back off when it's
// quiet. The list of runs and the jobs are asked for with the ETag of the
// last answer, and GitHub doesn't count "not modified" against the hourly
// limit, so most polls cost one request: the log.
static constexpr int ActiveInterval = 6000;
static constexpr int IdleInterval = 60000;
static constexpr int MaxProcesses = 4;
// How many earlier builds' jobs the forecast is made from. Each costs a
// request per run, once.
static constexpr int EarlierBuilds = 6;

static QString findGh() {
    auto path = QStandardPaths::findExecutable("gh");
    if (!path.isEmpty())
        return path;
    // The launcher may start the app without the shell's PATH, and mise keeps
    // gh outside the system directories.
    for (const auto &candidate : {QDir::homePath() + "/.local/share/mise/shims/gh",
                                  QDir::homePath() + "/.local/bin/gh"})
        if (QFileInfo(candidate).isExecutable())
            return candidate;
    return {};
}

static QString jobKey(const QVariantMap &job, const QVariantMap &run) {
    const auto workflow = job["workflow"].toString().isEmpty() ? run["workflow"].toString()
                                                                : job["workflow"].toString();
    return workflow + "/" + job["name"].toString();
}

static double offset(const QString &iso, qint64 origin) {
    const auto at = GitHub::ms(iso);
    return at && origin ? qMax(0.0, (at - origin) / 1000.0) : -1;
}

Backend::Backend(const QString &repo, bool demo, QObject *parent)
    : QObject(parent), m_repo(repo), m_gh(findGh()), m_demo(demo) {
    m_poll.setSingleShot(true);
    connect(&m_poll, &QTimer::timeout, this, &Backend::refresh);
    // The time left changes with the clock, not only with what GitHub says.
    m_tick.setInterval(1000);
    connect(&m_tick, &QTimer::timeout, this, &Backend::computeEstimate);
    connect(this, &Backend::buildFinished, this, &Backend::notify);
}

int Backend::selectedIndex() const {
    for (int i = 0; i < m_builds.size(); ++i)
        if (m_builds[i].toMap()["key"] == m_key)
            return i;
    return -1;
}

QVariantMap Backend::selectedBuild() const {
    const int index = selectedIndex();
    return index < 0 ? QVariantMap{} : m_builds[index].toMap();
}

QVariantMap Backend::buildByKey(const QString &key) const {
    for (const auto &build : m_allBuilds)
        if (build.toMap()["key"] == key)
            return build.toMap();
    return {};
}

QVariantMap Backend::selectedJob() const {
    for (const auto &job : m_jobs)
        if (job.toMap()["id"].toLongLong() == m_jobId)
            return job.toMap();
    return {};
}

int Backend::activeCount() const {
    int count = 0;
    for (const auto &build : m_allBuilds)
        count += GitHub::isActive(build.toMap()["state"].toString());
    return count;
}

void Backend::gh(const QStringList &args, Done done) {
    if (m_demo) {
        // Answered a moment later, the way a real call is, so the window goes
        // through the same states.
        const auto out = Demo::respond(args.last(), m_started);
        QTimer::singleShot(40, this, [done, out] { done(true, out, {}); });
        return;
    }
    if (m_offline)
        return;
    if (m_gh.isEmpty()) {
        done(false, {}, "The GitHub CLI (gh) isn't installed. Install it with `omarchy-pkg-add github-cli` "
                        "and log in with `gh auth login`.");
        return;
    }
    m_queue.append({args, done});
    pump();
}

// A handful of gh processes at a time: opening a build can ask for the jobs
// of a dozen earlier runs at once.
void Backend::pump() {
    while (m_running < MaxProcesses && !m_queue.isEmpty()) {
        const auto call = m_queue.takeFirst();
        auto *process = new QProcess(this);
        ++m_running;
        emit busyChanged();
        auto finish = [this, process, done = call.done](bool ok, const QString &err) {
            const auto out = process->readAllStandardOutput();
            process->deleteLater();
            --m_running;
            emit busyChanged();
            done(ok, out, err);
            pump();
        };
        connect(process, &QProcess::finished, this, [process, finish](int code, QProcess::ExitStatus status) {
            const auto err = QString::fromUtf8(process->readAllStandardError()).trimmed();
            finish(status == QProcess::NormalExit && code == 0, err);
        });
        connect(process, &QProcess::errorOccurred, this, [this, process, finish](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart)
                finish(false, QString("Couldn't start %1: %2").arg(m_gh, process->errorString()));
        });
        process->start(m_gh, call.args);
    }
}

// A JSON request that sends along the ETag of the answer it got last time.
// "Not modified" comes back as the answer already here.
void Backend::api(const QString &path, Done done) {
    if (m_demo) {
        gh({"api", path}, done);
        return;
    }
    QStringList args{"api", "--include"};
    if (m_kept.contains(path))
        args << "-H" << "If-None-Match: " + QString::fromLatin1(m_kept[path].etag);
    args << path;
    gh(args, [this, path, done](bool ok, const QByteArray &out, const QString &err) {
        int split = out.indexOf("\r\n\r\n"), skip = 4;
        if (split < 0) {
            split = out.indexOf("\n\n");
            skip = 2;
        }
        const auto head = split < 0 ? out : out.left(split);
        const auto body = split < 0 ? QByteArray() : out.mid(split + skip);
        const auto statusLine = head.left(qMax<qsizetype>(0, head.indexOf('\n')));
        if (statusLine.startsWith("HTTP/") && statusLine.contains(" 304") && m_kept.contains(path)) {
            done(true, m_kept[path].body, {});
            return;
        }
        if (!ok) {
            done(false, body, err);
            return;
        }
        static const QRegularExpression etag(R"(^etag:\s*(\S.*?)\s*$)", QRegularExpression::MultilineOption |
                                                                           QRegularExpression::CaseInsensitiveOption);
        const auto match = etag.match(QString::fromLatin1(head));
        if (match.hasMatch())
            m_kept[path] = {match.captured(1).toLatin1(), body};
        done(true, body, {});
    });
}

void Backend::refresh() {
    if (m_fetchingRuns)
        return;
    m_fetchingRuns = true;
    m_poll.stop();
    const auto repo = m_repo;
    // A hundred runs is about thirty-five builds: the list, and the history
    // the forecast is made from, in one request.
    api(QString("repos/%1/actions/runs?per_page=100").arg(m_repo),
        [this, repo](bool ok, const QByteArray &out, const QString &err) {
            m_fetchingRuns = false;
            // The user switched repository while this was in flight.
            if (repo != m_repo) {
                refresh();
                return;
            }
            if (!ok) {
                setError(err.isEmpty() ? "Fetching runs from GitHub failed." : err);
                schedule();
                return;
            }
            QString parseError;
            const auto runs = GitHub::parseRuns(out, &parseError);
            if (!parseError.isEmpty()) {
                setError(parseError);
                schedule();
                return;
            }
            setError({});
            applyRuns(runs);
            fetchCommit();
            fetchJobs();
            schedule();
        });
}

void Backend::applyRuns(const QVariantList &runs) {
    const auto before = m_allBuilds;
    m_listRuns = runs;
    m_lastUpdated = QDateTime::currentDateTime();
    rebuild();
    if (!before.isEmpty())
        for (const auto &build : GitHub::finishedBuilds(before, m_allBuilds))
            emit buildFinished(build.toMap());
}

// Builds from every run the app knows: the latest ones, and the runs of a
// commit it was asked for that is older than those.
void Backend::rebuild() {
    QVariantList runs = m_listRuns;
    QSet<qlonglong> ids;
    for (const auto &run : runs)
        ids << run.toMap()["id"].toLongLong();
    for (const auto &run : m_extraRuns)
        if (!ids.contains(run.toMap()["id"].toLongLong()))
            runs << run;

    m_allBuilds = GitHub::builds(runs);
    // A running build's row says how far along it is, which only needs how
    // long builds like it usually take.
    for (auto &value : m_allBuilds) {
        auto build = value.toMap();
        if (!GitHub::isActive(build["state"].toString()))
            continue;
        const auto usual = Estimate::spread(Estimate::likeBuilds(m_allBuilds, build));
        build["usual"] = usual.known() ? usual.typical : 0.0;
        value = build;
    }
    filterBuilds();
}

void Backend::filterBuilds() {
    m_builds.clear();
    for (const auto &value : m_allBuilds) {
        const auto build = value.toMap();
        if (!m_showSkipped && build["state"] == "skipped")
            continue;
        if (!m_branch.isEmpty() && build["branch"] != m_branch)
            continue;
        m_builds << build;
    }

    QString key = m_key;
    // Handed one commit: its build, as soon as it is here.
    if (!m_wantCommit.isEmpty()) {
        for (const auto &build : m_builds) {
            if (build.toMap()["fullSha"].toString().startsWith(m_wantCommit)) {
                key = build.toMap()["key"].toString();
                m_wantCommit.clear();
                break;
            }
        }
    }
    const bool gone = std::none_of(m_builds.cbegin(), m_builds.cend(),
                                   [&](const QVariant &build) { return build.toMap()["key"] == key; });
    if (gone)
        key = m_builds.isEmpty() ? QString() : m_builds.first().toMap()["key"].toString();

    emit buildsChanged();
    if (key != m_key) {
        m_key = key;
        clearJob();
    }
    rebuildJobs();
}

void Backend::clearJob() {
    m_jobId = 0;
    m_jobPinned = false;
    m_step = -1;
    m_logJobId = 0;
    m_log.clear();
    m_found.clear();
    m_failures.clear();
    setLogStatus({});
    emit failuresChanged();
    emit logReset();
}

void Backend::schedule() {
    m_poll.start(activeCount() > 0 ? ActiveInterval : IdleInterval);
}

// A commit older than the latest hundred runs is asked for by its sha.
void Backend::fetchCommit() {
    if (m_wantCommit.size() != 40 || m_commitFetched == m_wantCommit)
        return;
    m_commitFetched = m_wantCommit;
    const auto repo = m_repo;
    const auto commit = m_wantCommit;
    api(QString("repos/%1/actions/runs?per_page=100&head_sha=%2").arg(m_repo, commit),
        [this, repo, commit](bool ok, const QByteArray &out, const QString &err) {
            if (repo != m_repo || commit != m_wantCommit)
                return;
            if (!ok) {
                setError(err.isEmpty() ? "Fetching the runs of that commit failed." : err);
                return;
            }
            m_extraRuns = GitHub::parseRuns(out);
            if (m_extraRuns.isEmpty())
                setError(QString("GitHub has no runs for commit %1.").arg(commit.left(7)));
            rebuild();
            fetchJobs();
        });
}

void Backend::fetchRunJobs(qlonglong runId, bool final, const QString &updatedAt) {
    if (m_jobsInFlight.contains(runId))
        return;
    m_jobsInFlight << runId;
    const auto repo = m_repo;
    const auto path = QString("repos/%1/actions/runs/%2/jobs?per_page=100").arg(m_repo).arg(runId);
    api(path, [this, repo, path, runId, final, updatedAt](bool ok, const QByteArray &out, const QString &err) {
        m_jobsInFlight.remove(runId);
        if (repo != m_repo)
            return;
        if (!ok) {
            setError(err.isEmpty() ? "Fetching jobs from GitHub failed." : err);
            return;
        }
        // A finished run is never asked for again, so its answer needn't be kept.
        if (final)
            m_kept.remove(path);
        m_jobsOfRun[runId].updatedAt = updatedAt;
        applyJobs(runId, GitHub::parseJobs(out), final);
        fetchLog();
    });
}

void Backend::fetchJobs() {
    const auto build = selectedBuild();
    if (build.isEmpty())
        return;
    for (const auto &value : build["runs"].toList()) {
        const auto run = value.toMap();
        const auto id = run["id"].toLongLong();
        const auto state = run["state"].toString();
        if (state == "skipped" && build["state"] != "skipped")
            continue;
        // A finished run's jobs don't change, so only ask again when the run has.
        const auto kept = m_jobsOfRun.value(id);
        if (kept.final && kept.updatedAt == run["updatedAt"].toString())
            continue;
        fetchRunJobs(id, !GitHub::isActive(state), run["updatedAt"].toString());
    }
    // The jobs of earlier builds, for the forecast. Only a build that is
    // still going needs one.
    if (GitHub::isActive(build["state"].toString())) {
        int taken = 0;
        for (const auto &value : m_like) {
            const auto earlier = value.toMap();
            if (earlier["state"] != "success")
                continue;
            if (++taken > EarlierBuilds)
                break;
            for (const auto &run : earlier["runs"].toList()) {
                const auto id = run.toMap()["id"].toLongLong();
                if (run.toMap()["state"] != "skipped" && !m_jobsOfRun.value(id).final)
                    fetchRunJobs(id, true, run.toMap()["updatedAt"].toString());
            }
        }
    }
    fetchLog();
}

void Backend::applyJobs(qlonglong runId, const QVariantList &jobs, bool final) {
    auto &kept = m_jobsOfRun[runId];
    kept.jobs = jobs;
    kept.final = final;
    rebuildJobs();
}

QList<Estimate::Earlier> Backend::earlierBuilds(const QVariantList &like) const {
    QList<Estimate::Earlier> out;
    int taken = 0;
    for (const auto &value : like) {
        const auto build = value.toMap();
        if (build["state"] != "success")
            continue;
        if (++taken > EarlierBuilds)
            break;
        const auto origin = GitHub::ms(build["startedAt"].toString());
        Estimate::Earlier earlier;
        bool whole = true;
        for (const auto &runValue : build["runs"].toList()) {
            const auto run = runValue.toMap();
            if (run["state"] == "skipped")
                continue;
            const auto kept = m_jobsOfRun.value(run["id"].toLongLong());
            if (!kept.final) {
                whole = false;
                break;
            }
            for (const auto &jobValue : kept.jobs) {
                const auto job = jobValue.toMap();
                Estimate::Job sample;
                sample.key = jobKey(job, run);
                sample.state = job["state"].toString();
                sample.start = offset(job["startedAt"].toString(), origin);
                sample.end = offset(job["completedAt"].toString(), origin);
                earlier.insert(sample.key, sample);
            }
        }
        if (whole && !earlier.isEmpty())
            out << earlier;
    }
    return out;
}

// How long each step of a job usually takes, by name.
QHash<QString, double> Backend::usualSteps(const QString &key) const {
    QHash<QString, QList<double>> seconds;
    int taken = 0;
    for (const auto &value : m_like) {
        const auto build = value.toMap();
        if (build["state"] != "success")
            continue;
        if (++taken > EarlierBuilds)
            break;
        for (const auto &runValue : build["runs"].toList()) {
            const auto run = runValue.toMap();
            for (const auto &jobValue : m_jobsOfRun.value(run["id"].toLongLong()).jobs) {
                const auto job = jobValue.toMap();
                if (jobKey(job, run) != key)
                    continue;
                for (const auto &stepValue : job["steps"].toList()) {
                    const auto step = stepValue.toMap();
                    if (step["state"] == "success")
                        seconds[step["name"].toString()]
                            << GitHub::secondsBetween(step["startedAt"].toString(), step["completedAt"].toString());
                }
            }
        }
    }
    QHash<QString, double> usual;
    for (auto it = seconds.cbegin(); it != seconds.cend(); ++it)
        usual.insert(it.key(), Estimate::quantile(it.value(), .5));
    return usual;
}

// The jobs of the picked build: those of all its runs, in the order the runs
// started, and after them the ones earlier builds say are still to come.
void Backend::rebuildJobs() {
    const auto build = selectedBuild();
    const auto origin = GitHub::ms(build["startedAt"].toString());
    const bool several = build["workflows"].toStringList().size() > 1;

    m_like = build.isEmpty() ? QVariantList{} : Estimate::likeBuilds(m_allBuilds, build);
    QVariantList history;
    for (auto it = m_like.crbegin(); it != m_like.crend(); ++it) {
        const auto earlier = it->toMap();
        history << QVariantMap{{"key", earlier["key"]},     {"seconds", earlier["seconds"]},
                               {"state", earlier["state"]}, {"title", earlier["title"]},
                               {"sha", earlier["sha"]},     {"current", false}};
    }
    if (!build.isEmpty())
        history << QVariantMap{{"key", build["key"]},     {"seconds", build["seconds"]},
                               {"state", build["state"]}, {"title", build["title"]},
                               {"sha", build["sha"]},     {"current", true}};
    if (history != m_history) {
        m_history = history;
        emit historyChanged();
    }

    m_realJobs.clear();
    for (const auto &runValue : build["runs"].toList()) {
        const auto run = runValue.toMap();
        for (const auto &jobValue : m_jobsOfRun.value(run["id"].toLongLong()).jobs) {
            auto job = jobValue.toMap();
            const auto state = job["state"].toString();
            const bool started = state != "queued" && state != "skipped";
            job["key"] = jobKey(job, run);
            job["workflow"] = several ? run["workflow"] : QVariant(QString());
            job["runId"] = run["id"];
            job["start"] = started ? offset(job["startedAt"].toString(), origin) : -1.0;
            job["end"] = started ? offset(job["completedAt"].toString(), origin) : -1.0;
            job["expected"] = false;
            m_realJobs << job;
        }
    }

    // In the order they started, which is the order a timeline reads in;
    // the ones still waiting come last.
    std::stable_sort(m_realJobs.begin(), m_realJobs.end(), [](const QVariant &a, const QVariant &b) {
        const double x = a.toMap()["start"].toDouble(), y = b.toMap()["start"].toDouble();
        return (x < 0 ? 1e12 : x) < (y < 0 ? 1e12 : y);
    });

    computeEstimate();

    auto jobs = m_realJobs;
    int phantom = 0;
    for (const auto &value : m_estimate["expectedJobs"].toList()) {
        const auto key = value.toString();
        jobs << QVariantMap{{"id", qlonglong(--phantom)},
                            {"key", key},
                            {"name", key.section('/', 1)},
                            {"workflow", several ? key.section('/', 0, 0) : QString()},
                            {"state", "pending"},
                            {"expected", true},
                            {"start", -1.0},
                            {"end", -1.0},
                            {"steps", QVariantList{}}};
    }
    if (jobs != m_jobs) {
        m_jobs = jobs;
        emit jobsChanged();
    }
    pickJob();
    annotateLog();
    emit selectionChanged();

    const bool active = GitHub::isActive(build["state"].toString());
    if (active != m_tick.isActive())
        active ? m_tick.start() : m_tick.stop();
}

void Backend::computeEstimate() {
    const auto build = selectedBuild();
    QVariantMap map;
    if (build.isEmpty()) {
        if (!m_estimate.isEmpty()) {
            m_estimate.clear();
            emit estimateChanged();
        }
        return;
    }
    const auto usual = Estimate::spread(m_like);
    const bool active = GitHub::isActive(build["state"].toString());
    const auto origin = GitHub::ms(build["startedAt"].toString());
    const double elapsed = active ? qMax(0.0, (QDateTime::currentMSecsSinceEpoch() - origin) / 1000.0)
                                  : build["seconds"].toDouble();
    map["active"] = active;
    map["elapsed"] = elapsed;
    map["usualKnown"] = usual.known();
    map["usualSamples"] = usual.samples;
    map["usualLow"] = usual.low;
    map["usual"] = usual.typical;
    map["usualHigh"] = usual.high;
    map["known"] = false;

    double axis = elapsed;
    for (const auto &job : m_realJobs)
        axis = qMax(axis, job.toMap()["end"].toDouble());

    QVariantMap perJob;
    QVariantList expected;
    if (active) {
        QList<Estimate::Job> now;
        for (const auto &value : m_realJobs) {
            const auto job = value.toMap();
            Estimate::Job entry;
            entry.key = job["key"].toString();
            entry.state = job["state"].toString();
            entry.start = job["start"].toDouble();
            entry.end = job["end"].toDouble();
            now << entry;
        }
        const auto forecast = Estimate::forecast(now, elapsed, usual, earlierBuilds(m_like));
        map["known"] = forecast.known;
        map["basis"] = forecast.basis;
        map["samples"] = forecast.samples;
        map["total"] = forecast.total;
        map["low"] = forecast.low;
        map["high"] = forecast.high;
        map["late"] = forecast.late;
        map["over"] = forecast.over;
        map["remaining"] = qMax(0.0, forecast.total - elapsed);
        map["remainingRounded"] = Estimate::rounded(qMax(0.0, forecast.total - elapsed));
        if (forecast.known)
            axis = qMax(axis, forecast.high);
        for (const auto &job : forecast.jobs) {
            perJob[job.key] = QVariantMap{{"start", job.start}, {"end", job.end},         {"low", job.low},
                                          {"high", job.high},   {"typical", job.typical}, {"late", job.late}};
            if (job.expected)
                expected << job.key;
            if (forecast.basis == "jobs")
                axis = qMax(axis, job.high);
        }
    } else {
        map["total"] = elapsed;
    }
    map["jobs"] = perJob;
    map["expectedJobs"] = expected;
    map["axis"] = qMax(axis, 1.0);
    m_estimate = map;
    emit estimateChanged();
}

// Shows the job worth looking at: the one that failed, else the one running,
// else the last one that did any work. A job the user picked stays picked.
void Backend::pickJob() {
    if (m_jobPinned && !selectedJob().isEmpty())
        return;
    auto find = [this](auto predicate) -> qlonglong {
        for (const auto &job : m_realJobs)
            if (predicate(job.toMap()))
                return job.toMap()["id"].toLongLong();
        return 0;
    };
    qlonglong id = find([](const QVariantMap &job) { return job["state"] == "failure"; });
    if (!id)
        id = find([](const QVariantMap &job) { return job["state"] == "running"; });
    if (!id)
        for (const auto &job : m_realJobs)
            if (!job.toMap()["steps"].toList().isEmpty() && job.toMap()["state"] != "skipped")
                id = job.toMap()["id"].toLongLong();
    if (!id && !m_realJobs.isEmpty())
        id = m_realJobs.first().toMap()["id"].toLongLong();
    if (id != m_jobId) {
        m_jobId = id;
        m_step = -1;
        m_log.clear();
        m_logJobId = 0;
        emit logReset();
    }
}

// Ties the log to the steps: where each one starts, how long it took and
// usually takes, and where in the failed one the failure is.
void Backend::annotateLog() {
    const auto job = selectedJob();
    const auto steps = job["steps"].toList();
    const bool mine = m_logJobId == m_jobId && m_jobId != 0;

    QStringList names;
    for (const auto &step : steps)
        names << step.toMap()["name"].toString();
    const auto starts = mine ? GitHub::mapSteps(steps, m_log.lines()) : QList<int>(steps.size(), -1);
    m_log.setSteps(starts, names);

    const auto usual = usualSteps(job["key"].toString());
    QVariantList out;
    int failedStep = -1;
    for (int i = 0; i < steps.size(); ++i) {
        auto step = steps[i].toMap();
        const auto state = step["state"].toString();
        step["line"] = starts.value(i, -1);
        step["seconds"] = GitHub::isActive(state) || state == "skipped"
                              ? 0
                              : GitHub::secondsBetween(step["startedAt"].toString(), step["completedAt"].toString());
        step["usual"] = usual.value(step["name"].toString(), -1);
        if (state == "failure" && failedStep < 0)
            failedStep = i;
        out << step;
    }
    if (out != m_steps) {
        m_steps = out;
        emit stepsChanged();
    }

    QList<Failures::Failure> found;
    const auto state = job["state"].toString();
    if (mine && state != "success" && state != "skipped") {
        // Inside the failed step when the log says where it is, so the noise
        // of a clean-up step (a database's own error log, say) stays out.
        if (failedStep >= 0 && starts.value(failedStep, -1) >= 0)
            found = Failures::find(m_log.lines(), starts[failedStep], m_log.stepEnd(failedStep));
        else
            found = Failures::find(m_log.lines());
    }
    m_log.setFailures(found);
    m_found = found;
    QVariantList failures;
    for (const auto &failure : found)
        failures << QVariantMap{{"line", failure.line},   {"first", failure.first},
                                {"last", failure.last},   {"title", failure.title},
                                {"location", failure.location}, {"detail", failure.detail}};
    if (failures != m_failures) {
        m_failures = failures;
        emit failuresChanged();
    }
}

void Backend::fetchLog() {
    const auto job = selectedJob();
    if (job.isEmpty() || m_fetchingLog) {
        if (job.isEmpty())
            setLogStatus(m_jobs.isEmpty() ? "" : "Pick a job to see its log.");
        return;
    }
    const auto state = job["state"].toString();
    if (state == "skipped" || (state == "queued" && job["steps"].toList().isEmpty())) {
        m_log.clear();
        setLogStatus(state == "skipped" ? "This job was skipped, so it has no log."
                                        : "This job is waiting for a runner.");
        return;
    }
    if (m_logJobId == m_jobId && m_logFinal)
        return;

    const auto jobId = m_jobId;
    const bool final = !GitHub::isActive(state);
    if (m_logJobId != jobId)
        setLogStatus("Loading log…");
    m_fetchingLog = true;
    gh({"api", "--allow-escape-sequences", QString("repos/%1/actions/jobs/%2/logs").arg(m_repo).arg(jobId)},
       [this, jobId, final](bool ok, const QByteArray &out, const QString &err) {
           m_fetchingLog = false;
           if (jobId != m_jobId) {
               fetchLog();
               return;
           }
           if (!ok) {
               // GitHub only serves a job's log once the runner has uploaded
               // some of it, which lags behind a job that has just started.
               if (!final)
                   setLogStatus("Waiting for GitHub to publish the log of this running job…");
               else
                   setLogStatus(err.isEmpty() ? "GitHub didn't return a log for this job." : err);
               return;
           }
           applyLog(jobId, out, final);
       });
}

void Backend::applyLog(qlonglong jobId, const QByteArray &raw, bool final) {
    if (jobId != m_jobId)
        return;
    const bool reset = m_logJobId != jobId;
    m_logJobId = jobId;
    m_logFinal = final;
    m_log.setLines(GitHub::parseLog(raw));
    setLogStatus({});
    annotateLog();
    if (reset)
        emit logReset();
}

void Backend::selectBuild(const QString &key) {
    if (key == m_key || buildByKey(key).isEmpty())
        return;
    m_key = key;
    clearJob();
    rebuildJobs();
    fetchJobs();
}

void Backend::selectJob(qlonglong id) {
    // A job GitHub hasn't created yet has nothing to show.
    if (id <= 0)
        return;
    m_jobPinned = true;
    if (id == m_jobId)
        return;
    m_jobId = id;
    m_step = -1;
    m_logJobId = 0;
    m_log.clear();
    annotateLog();
    emit selectionChanged();
    emit logReset();
    fetchLog();
}

void Backend::selectStep(int index) {
    if (index == m_step)
        return;
    m_step = index;
    emit stepsChanged();
}

void Backend::moveBuild(int delta) {
    if (m_builds.isEmpty())
        return;
    const int index = qBound(0, selectedIndex() + delta, int(m_builds.size()) - 1);
    selectBuild(m_builds[index].toMap()["key"].toString());
}

void Backend::moveJob(int delta) {
    if (m_realJobs.isEmpty())
        return;
    int index = 0;
    for (int i = 0; i < m_realJobs.size(); ++i)
        if (m_realJobs[i].toMap()["id"].toLongLong() == m_jobId)
            index = i;
    index = (index + delta + m_realJobs.size()) % m_realJobs.size();
    selectJob(m_realJobs[index].toMap()["id"].toLongLong());
}

int Backend::moveStep(int from, int delta) {
    for (int i = from + delta; i >= 0 && i < m_steps.size(); i += delta) {
        if (m_steps[i].toMap()["line"].toInt() >= 0) {
            selectStep(i);
            return i;
        }
    }
    return -1;
}

void Backend::show(const QString &repo, const QString &sha) {
    static const QRegularExpression validRepo(R"(^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$)");
    static const QRegularExpression validSha(R"(^[0-9a-f]{7,40}$)");
    if (!validRepo.match(repo).hasMatch()) {
        setError(QString("\"%1\" isn't a repository; pass it as owner/name.").arg(repo));
        return;
    }
    if (repo != m_repo) {
        m_repo = repo;
        m_listRuns.clear();
        m_extraRuns.clear();
        m_allBuilds.clear();
        m_jobsOfRun.clear();
        m_kept.clear();
        m_branch.clear();
        m_key.clear();
        m_commitFetched.clear();
        emit repoChanged();
    }
    m_wantCommit = validSha.match(sha).hasMatch() ? sha : QString();
    // The build that was asked for has to be in the list to be picked.
    if (!m_wantCommit.isEmpty())
        m_branch.clear();
    // Picks the commit's build if it is already here; otherwise that happens
    // when its runs arrive.
    filterBuilds();
    if (m_fetchingRuns)
        return; // The running fetch sees the change and starts over.
    refresh();
}

void Backend::toggleBranch() {
    m_branch = m_branch.isEmpty() ? selectedBuild()["branch"].toString() : QString();
    filterBuilds();
    fetchJobs();
}

void Backend::toggleSkipped() {
    m_showSkipped = !m_showSkipped;
    filterBuilds();
    fetchJobs();
}

QString Backend::shareUrl() const {
    const auto job = selectedJob();
    const auto build = selectedBuild();
    QVariantMap run;
    for (const auto &value : build["runs"].toList())
        if (run.isEmpty() || value.toMap()["id"] == job["runId"])
            run = value.toMap();
    if (job.isEmpty())
        run = QVariantMap{{"url", build["url"]}};
    return GitHub::shareUrl(m_repo, job["expected"].toBool() ? QVariantMap{} : job, run);
}

QString Backend::openUrl() const {
    auto url = shareUrl();
    const auto step = m_steps.value(m_step).toMap();
    if (!url.isEmpty() && !selectedJob().isEmpty() && step["number"].toInt() > 0)
        url += QString("#step:%1:1").arg(step["number"].toInt());
    return url;
}

QString Backend::failureReport() const {
    if (m_found.isEmpty())
        return {};
    const auto job = selectedJob();
    const auto build = selectedBuild();
    QString step;
    for (const auto &value : m_steps)
        if (value.toMap()["state"] == "failure" && step.isEmpty())
            step = value.toMap()["name"].toString();

    QStringList out;
    out << QString("CI failed in %1: job \"%2\"%3, on %4 at %5.")
               .arg(m_repo, job["name"].toString(), step.isEmpty() ? QString() : QString(", step \"%1\"").arg(step),
                    build["branch"].toString(), build["sha"].toString());
    out << shareUrl() << QString();
    for (const auto &failure : m_found)
        if (!failure.location.isEmpty())
            out << QString("- %1  %2").arg(failure.location, failure.title);
    if (out.last() != QString())
        out << QString();
    out << Failures::excerpt(m_log.lines(), m_found);
    return out.join('\n');
}

QString Backend::copyLink() {
    const auto url = shareUrl();
    if (!url.isEmpty())
        QGuiApplication::clipboard()->setText(url);
    return url;
}

bool Backend::copyFailure() {
    const auto report = failureReport();
    if (report.isEmpty())
        return false;
    QGuiApplication::clipboard()->setText(report);
    return true;
}

void Backend::copyLog() {
    QGuiApplication::clipboard()->setText(m_log.text());
}

void Backend::setError(const QString &error) {
    if (error == m_error)
        return;
    m_error = error;
    emit errorChanged();
}

void Backend::setLogStatus(const QString &status) {
    if (status == m_logStatus)
        return;
    m_logStatus = status;
    emit logStatusChanged();
}

void Backend::notify(const QVariantMap &build) {
    static const QHash<QString, QString> verbs{
        {"success", "passed"}, {"failure", "failed"}, {"cancelled", "was cancelled"}, {"neutral", "finished"}};
    const int seconds = build["seconds"].toInt();
    const auto took = seconds >= 60 ? QString("%1m %2s").arg(seconds / 60).arg(seconds % 60)
                                    : QString("%1s").arg(seconds);
    const auto summary = QString("Build %1").arg(verbs.value(build["state"].toString(), "finished"));
    const auto body = QString("%1\n%2 · %3").arg(build["title"].toString(), build["branch"].toString(), took);
    QStringList args{"--app-name=CI Watch", "--icon=ciwatch", summary, body};
    if (build["state"] == "failure")
        args.prepend("--urgency=critical");
    // Not from a demo, and not from the tests, which run without a screen.
    if (!m_demo && QGuiApplication::platformName() != "offscreen")
        QProcess::startDetached("notify-send", args);
}
