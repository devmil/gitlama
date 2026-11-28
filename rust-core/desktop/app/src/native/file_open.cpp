// Open-document events: macOS delivers `open -a GitLama <folder>`, Finder drops on the Dock
// icon and "Open With" as QFileOpenEvent, also before the window exists. The filter hands
// each local path to Rust, which queues it for the window.

#include <QtCore/QByteArray>
#include <QtCore/QEvent>
#include <QtCore/QObject>
#include <QtCore/QUrl>
#include <QtGui/QFileOpenEvent>
#include <QtGui/QGuiApplication>

extern "C" void gitlama_file_open_requested(const char *path, size_t length);

namespace {

class FileOpenFilter : public QObject {
public:
    using QObject::QObject;

protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (event->type() == QEvent::FileOpen) {
            auto *open = static_cast<QFileOpenEvent *>(event);
            const QString file = open->file().isEmpty() && open->url().isLocalFile()
                ? open->url().toLocalFile()
                : open->file();
            if (!file.isEmpty()) {
                const QByteArray bytes = file.toUtf8();
                gitlama_file_open_requested(bytes.constData(), static_cast<size_t>(bytes.size()));
                return true;
            }
        }
        return QObject::eventFilter(watched, event);
    }
};

} // namespace

extern "C" void gitlama_install_file_open_filter() {
    auto *application = QGuiApplication::instance();
    if (application != nullptr) {
        application->installEventFilter(new FileOpenFilter(application));
    }
}
