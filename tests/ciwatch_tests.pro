QT += core gui network qml quick quickcontrols2 testlib
CONFIG += c++17 testcase
TARGET = ciwatch_tests
TEMPLATE = app

INCLUDEPATH += ../src
DEFINES += FIXTURES=\\\"$$PWD/fixtures\\\"

HEADERS += ../src/backend.h ../src/compare.h ../src/demo.h ../src/estimate.h ../src/failures.h ../src/github.h \
    ../src/logmodel.h ../src/theme.h
SOURCES += ciwatch_tests.cpp ../src/backend.cpp ../src/compare.cpp ../src/demo.cpp ../src/estimate.cpp ../src/failures.cpp \
    ../src/github.cpp ../src/logmodel.cpp ../src/theme.cpp

# The window test loads the real Main.qml.
RESOURCES += ../src/resources.qrc
