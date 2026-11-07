#ifndef GITLAMA_WINDOW_CHROME_H_
#define GITLAMA_WINDOW_CHROME_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Owns the Linux implementation of gitlama/window_chrome for the lifetime
// of one window. The GTK title bar is hidden; the Flutter caption asks
// this channel to move, minimize, maximize and close the window. All functions
// must be called on the GTK thread.
typedef struct _GitLamaWindowChrome GitLamaWindowChrome;

// Creates a titlebar-free window with native rounded borders, shadows
// and resize edges. Add the Flutter view with add_rounded_window_content before realization.
GtkWindow* gitlama_window_chrome_new_window(GtkApplication* application);

GitLamaWindowChrome* gitlama_window_chrome_new(
    GtkWindow* window,
    FlBinaryMessenger* messenger);

void gitlama_window_chrome_free(GitLamaWindowChrome* chrome);

// Gives a window created by desktop_multi_window the main window's treatment:
// its GTK header bar is hidden, the native border carries the rounded
// corners, and a chrome owned by the window serves the Flutter caption of
// [view]'s engine until the window is destroyed.
void gitlama_window_chrome_adopt_view(FlView* view);

#endif  // GITLAMA_WINDOW_CHROME_H_
