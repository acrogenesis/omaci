QT += core gui network qml quick quickcontrols2

CONFIG += c++17 release
TARGET = ciwatch
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/compare.h \
    src/demo.h \
    src/estimate.h \
    src/failures.h \
    src/github.h \
    src/logmodel.h \
    src/theme.h

SOURCES += \
    src/main.cpp \
    src/backend.cpp \
    src/compare.cpp \
    src/demo.cpp \
    src/estimate.cpp \
    src/failures.cpp \
    src/github.cpp \
    src/logmodel.cpp \
    src/theme.cpp

RESOURCES += src/resources.qrc
