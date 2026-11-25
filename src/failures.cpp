#include "failures.h"

#include <QRegularExpression>
#include <QStringList>

namespace Failures {

namespace {

// RSpec prints a "Failures:" section with every failure numbered and its
// reason under it, and after the summary a "Failed examples:" list with the
// command that reruns each one. parallel_rspec prints that once per process.
struct RSpec {
    int section = -1;
    QList<int> open; // Failures of this section still waiting for a location.
};

bool blank(const QString &text) {
    return text.trimmed().isEmpty();
}

}

QList<Failure> find(const QList<GitHub::LogLine> &lines, int from, int to) {
    static const QRegularExpression numbered(R"(^\s{1,6}(\d+)\) (.+)$)");
    static const QRegularExpression rspecCommand(R"(^rspec (?:\./)?(\S+?:\d+)(?:\s+#\s*(.*))?$)");
    static const QRegularExpression cucumberCommand(R"(^cucumber (\S+?:\d+)(?:\s+#\s*(.*))?$)");
    static const QRegularExpression minitestName(R"(^(\S+#\S+) \[([^\]]+:\d+)\]:?$)");
    static const QRegularExpression pytest(R"(^FAILED (\S+)(?: - (.*))?$)");
    static const QRegularExpression jest(R"(^\s*● (.+ › .+)$)");
    static const QRegularExpression goTest(R"(^\s*--- FAIL: (\S+))");
    static const QRegularExpression annotation(R"(^(\S+?)#L(\d+)(?:C\d+)?: (.+)$)");

    if (to < 0 || to >= lines.size())
        to = lines.size() - 1;
    from = qMax(0, from);

    QList<Failure> found;
    QList<Failure> lastResort;
    RSpec rspec;
    int cucumberSection = -1;
    int current = -1; // The RSpec failure whose reason is being read.

    auto closeCurrent = [&](int before) {
        if (current >= 0 && found[current].last < 0)
            found[current].last = before;
        current = -1;
    };

    for (int i = from; i <= to; ++i) {
        const auto &line = lines.at(i);
        const auto text = line.text;
        const auto trimmed = text.trimmed();

        if (line.kind == GitHub::Error) {
            closeCurrent(i - 1);
            Failure failure;
            failure.line = failure.first = failure.last = i;
            failure.title = text;
            const auto match = annotation.match(text);
            if (match.hasMatch()) {
                failure.location = match.captured(1) + ":" + match.captured(2);
                failure.title = match.captured(3);
            }
            // Every failed step ends in this line, whatever went wrong.
            if (text.startsWith("Process completed with exit code"))
                lastResort << failure;
            else
                found << failure;
            continue;
        }

        if (trimmed == "Failures:") {
            closeCurrent(i - 1);
            rspec = RSpec{i, {}};
            cucumberSection = -1;
            continue;
        }
        if (rspec.section >= 0) {
            const auto match = numbered.match(text);
            if (match.hasMatch()) {
                closeCurrent(i - 1);
                Failure failure;
                failure.line = i;
                failure.first = rspec.open.isEmpty() ? rspec.section : i;
                failure.title = match.captured(2).trimmed();
                found << failure;
                current = found.size() - 1;
                rspec.open << current;
                continue;
            }
            if (current >= 0 && found[current].detail.isEmpty() && trimmed.startsWith("Failure/Error:")) {
                found[current].detail = trimmed.mid(QString("Failure/Error:").size()).trimmed();
                continue;
            }
            if (trimmed.startsWith("Finished in ") || trimmed == "Failed examples:") {
                // Leave out the blank lines between the reason and the summary.
                int end = i - 1;
                while (end > rspec.section && blank(lines.at(end).text))
                    --end;
                closeCurrent(end);
                continue;
            }
        }
        {
            const auto match = rspecCommand.match(trimmed);
            if (match.hasMatch()) {
                if (!rspec.open.isEmpty()) {
                    auto &failure = found[rspec.open.takeFirst()];
                    failure.location = match.captured(1);
                    // The last failure of a section takes the summary and
                    // the rerun commands along, so a copy of it is complete.
                    if (rspec.open.isEmpty() || failure.last < 0)
                        failure.last = i;
                } else {
                    // The list without the section: a log cut off above it.
                    Failure failure;
                    failure.line = failure.first = failure.last = i;
                    failure.location = match.captured(1);
                    failure.title = match.captured(2).isEmpty() ? match.captured(1) : match.captured(2);
                    found << failure;
                }
                continue;
            }
        }

        if (trimmed == "Failing Scenarios:") {
            closeCurrent(i - 1);
            cucumberSection = i;
            rspec.section = -1;
            continue;
        }
        if (cucumberSection >= 0) {
            const auto match = cucumberCommand.match(trimmed);
            if (match.hasMatch()) {
                Failure failure;
                failure.line = i;
                failure.first = cucumberSection;
                failure.last = i;
                failure.location = match.captured(1);
                failure.title = match.captured(2).isEmpty() ? match.captured(1) : match.captured(2);
                for (auto &other : found)
                    if (other.first == cucumberSection)
                        other.last = i;
                found << failure;
                continue;
            }
            if (!blank(text))
                cucumberSection = -1;
        }

        // Minitest: "Failure:" or "Error:" on a line of its own, the test and
        // its file on the next.
        if ((trimmed == "Failure:" || trimmed == "Error:") && i < to) {
            const auto match = minitestName.match(lines.at(i + 1).text.trimmed());
            if (match.hasMatch()) {
                Failure failure;
                failure.line = i;
                failure.first = i;
                failure.title = match.captured(1);
                failure.location = match.captured(2);
                int end = i + 1;
                while (end < to && !blank(lines.at(end + 1).text))
                    ++end;
                failure.last = end;
                if (i + 2 <= end)
                    failure.detail = lines.at(i + 2).text.trimmed();
                found << failure;
                i = end;
                continue;
            }
        }

        for (const auto *expression : {&pytest, &jest, &goTest}) {
            const auto match = expression->match(text);
            if (!match.hasMatch())
                continue;
            Failure failure;
            failure.line = failure.first = failure.last = i;
            failure.title = match.captured(1).trimmed();
            if (expression == &pytest) {
                failure.location = match.captured(1).section("::", 0, 0);
                failure.detail = match.captured(2);
            }
            found << failure;
            break;
        }
    }
    closeCurrent(to);

    for (auto &failure : found)
        if (failure.last < failure.line)
            failure.last = failure.line;
    return found.isEmpty() ? lastResort : found;
}

QString excerpt(const QList<GitHub::LogLine> &lines, const QList<Failure> &failures, int maxLines) {
    QStringList out;
    int covered = -1;
    for (const auto &failure : failures) {
        const int first = qMax(covered + 1, failure.first);
        const int last = qMin(failure.last, int(lines.size()) - 1);
        if (first > last)
            continue;
        if (!out.isEmpty())
            out << QString();
        for (int i = first; i <= last; ++i) {
            if (out.size() >= maxLines) {
                out << "…";
                return out.join('\n');
            }
            out << lines.at(i).text;
        }
        covered = last;
    }
    return out.join('\n');
}

}
