#include "logmodel.h"

int LogModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_lines.size();
}

QVariant LogModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_lines.size())
        return {};
    const auto &line = m_lines.at(index.row());
    switch (role) {
    case TimeRole: return line.time;
    case TextRole: return line.text;
    case KindRole: return line.kind;
    case StepRole: return m_headings.value(index.row());
    case MarkRole: return m_marks.value(index.row(), NoMark);
    }
    return {};
}

QHash<int, QByteArray> LogModel::roleNames() const {
    return {{TimeRole, "time"}, {TextRole, "text"}, {KindRole, "kind"}, {StepRole, "step"}, {MarkRole, "mark"}};
}

void LogModel::setLines(const QList<GitHub::LogLine> &lines) {
    const int old = m_lines.size();
    const bool grows = old > 0 && lines.size() > old && lines.at(old - 1).text == m_lines.last().text &&
                       lines.at(old - 1).time == m_lines.last().time;
    if (grows) {
        beginInsertRows({}, old, lines.size() - 1);
        m_lines = lines;
        endInsertRows();
    } else if (lines.size() != old || old == 0 || lines.last().text != m_lines.last().text) {
        beginResetModel();
        m_lines = lines;
        m_headings.clear();
        m_marks.clear();
        m_starts.clear();
        endResetModel();
    }
}

void LogModel::clear() {
    if (m_lines.isEmpty())
        return;
    beginResetModel();
    m_lines.clear();
    m_headings.clear();
    m_marks.clear();
    m_starts.clear();
    endResetModel();
}

QString LogModel::text() const {
    QStringList out;
    for (const auto &line : m_lines)
        out << line.text;
    return out.join('\n');
}

void LogModel::touch(const QList<int> &roles) {
    if (!m_lines.isEmpty())
        emit dataChanged(index(0), index(m_lines.size() - 1), roles);
}

void LogModel::setSteps(const QList<int> &starts, const QStringList &names) {
    QHash<int, QString> headings;
    for (int i = 0; i < starts.size(); ++i)
        if (starts[i] >= 0)
            headings.insert(starts[i], names.value(i));
    m_starts = starts;
    if (headings == m_headings)
        return;
    m_headings = headings;
    touch({StepRole});
}

void LogModel::setFailures(const QList<Failures::Failure> &failures) {
    QHash<int, int> marks;
    for (const auto &failure : failures) {
        for (int i = failure.first; i <= failure.last; ++i)
            if (!marks.contains(i))
                marks.insert(i, InFailure);
        marks.insert(failure.line, FailureLine);
    }
    if (marks == m_marks)
        return;
    m_marks = marks;
    touch({MarkRole});
}

int LogModel::stepAt(int row) const {
    int found = -1;
    for (int i = 0; i < m_starts.size(); ++i)
        if (m_starts[i] >= 0 && m_starts[i] <= row)
            found = i;
    return found;
}

int LogModel::stepEnd(int stepIndex) const {
    for (int i = stepIndex + 1; i < m_starts.size(); ++i)
        if (m_starts[i] >= 0)
            return m_starts[i] - 1;
    return m_lines.size() - 1;
}
