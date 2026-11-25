#pragma once

#include <QList>
#include <QString>

#include "github.h"

// Finds what actually went wrong in a job's log. The runner's own error line
// ("Process completed with exit code 1.") is the last line of a failed step
// and says nothing; what the test runner printed above it does.
namespace Failures {

struct Failure {
    int line = -1;    // The line that names this failure: where to land.
    int first = -1;   // The block it belongs to, for showing and copying.
    int last = -1;
    QString title;    // What failed, in the test runner's words.
    QString location; // file:line when the runner gave one.
    QString detail;   // The first line of the reason.
};

// Looks at lines from..to (inclusive; the whole log by default), which is
// meant to be the failed step, so a noisy clean-up step can't add its own.
QList<Failure> find(const QList<GitHub::LogLine> &lines, int from = 0, int to = -1);

// The text of the failures, block by block, without repeating a block that
// several failures share.
QString excerpt(const QList<GitHub::LogLine> &lines, const QList<Failure> &failures, int maxLines = 200);

}
