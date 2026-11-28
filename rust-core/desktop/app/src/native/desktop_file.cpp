// The Wayland app id and X11 window class come from the desktop file name;
// qtbridge does not expose the setter.
#include <QtGui/QGuiApplication>

extern "C" void gitlama_set_desktop_file_name(const char *name) {
    QGuiApplication::setDesktopFileName(QString::fromUtf8(name));
}


// Wayland's basic render loop: present without waiting in eglSwapBuffers for the
// previous frame's callback. Qt Quick still paces animation frames by frame
// callbacks; only frames for a new window size (configure events) go out at
// once instead of a vsync later. Qt 6's ListView requests one more frame after
// every height change, so with a blocking swap each resize step waited a vsync
// for it and the content followed the window edge at half the display rate.
#include <QtGui/QSurfaceFormat>

extern "C" void gitlama_present_without_swap_wait() {
    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setSwapInterval(0);
    QSurfaceFormat::setDefaultFormat(format);
}
