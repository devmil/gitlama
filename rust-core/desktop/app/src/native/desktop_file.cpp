// The Wayland app id and X11 window class come from the desktop file name;
// qtbridge does not expose the setter.
#include <QtGui/QGuiApplication>

extern "C" void gitlama_set_desktop_file_name(const char *name) {
    QGuiApplication::setDesktopFileName(QString::fromUtf8(name));
}

