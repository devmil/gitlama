#ifndef DEVMIL_ROUNDED_WINDOW_H_
#define DEVMIL_ROUNDED_WINDOW_H_

#include <gtk/gtk.h>
#include <initializer_list>

// Keep the accelerated child rectangular. A curved Cairo clip or libhandy's
// offscreen surface forces GTK3 to read the entire GL texture back to the CPU.
// The small native border instead carries the rounded corners and shadows.
inline bool rounded_window_is_floating(GtkWidget* window) {
  GtkStyleContext* style = gtk_widget_get_style_context(window);
  if (!gdk_screen_is_composited(gtk_widget_get_screen(window)) ||
      !gtk_style_context_has_class(style, "csd") ||
      gtk_style_context_has_class(style, "solid-csd")) return false;
  for (const char* state : {"maximized", "fullscreen", "tiled", "tiled-top",
                            "tiled-bottom", "tiled-left", "tiled-right"}) {
    if (gtk_style_context_has_class(style, state)) return false;
  }
  GdkWindow* native = gtk_widget_get_window(window);
  return !native || !(gdk_window_get_state(native) &
                     (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN |
                      GDK_WINDOW_STATE_TILED));
}

inline void update_rounded_window_insets(GtkWidget* window, GtkWidget* content) {
  const bool floating = rounded_window_is_floating(window);
  // For an 8px circle, (2,3) lies inside the curve at every corner.
  gtk_widget_set_margin_start(content, floating ? 2 : 0);
  gtk_widget_set_margin_end(content, floating ? 2 : 0);
  gtk_widget_set_margin_top(content, floating ? 3 : 0);
  gtk_widget_set_margin_bottom(content, floating ? 3 : 0);
}

inline gboolean rounded_window_state_changed(GtkWidget* window,
                                             GdkEventWindowState*,
                                             GtkWidget* content) {
  update_rounded_window_insets(window, content);
  return FALSE;
}

// Gives a client-decorated window the rounded floating border. The window
// must already have a hidden titlebar, or GTK draws no client-side frame.
inline void style_rounded_window(GtkWindow* window) {
  GtkStyleContext* context = gtk_widget_get_style_context(GTK_WIDGET(window));
  gtk_style_context_add_class(context, "devmil-rounded-window");
  // The screen keeps one provider for every rounded window on it.
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  if (g_object_get_data(G_OBJECT(screen), "devmil-rounded-window-style")) {
    return;
  }
  constexpr const char* floating =
      "window.devmil-rounded-window.csd:not(.solid-csd):not(.maximized)"
      ":not(.fullscreen):not(.tiled):not(.tiled-top):not(.tiled-bottom)"
      ":not(.tiled-left):not(.tiled-right)";
  g_autoptr(GString) css = g_string_new(
      "window.devmil-rounded-window.csd, "
      "window.devmil-rounded-window.csd > decoration "
      "{ border-radius: 0; }");
  g_string_append_printf(css, "%s, %s > decoration { border-radius: 8px; }",
                         floating, floating);
  g_autoptr(GtkCssProvider) provider = gtk_css_provider_new();
  gtk_css_provider_load_from_data(provider, css->str, -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      screen, GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_set_data_full(G_OBJECT(screen), "devmil-rounded-window-style",
                         g_object_ref(provider), g_object_unref);
}

inline GtkWindow* create_rounded_application_window(GtkApplication* application) {
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(application));
  // An explicitly hidden titlebar enables native CSD without a second toolbar.
  gtk_window_set_titlebar(window, gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
  style_rounded_window(window);
  return window;
}

// Keeps [content], already the window's child, inset inside the curve while
// the window floats.
inline void track_rounded_window_content(GtkWindow* window, GtkWidget* content) {
  g_signal_connect_object(window, "style-updated",
                          G_CALLBACK(update_rounded_window_insets), content,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(window, "window-state-event",
                          G_CALLBACK(rounded_window_state_changed), content,
                          static_cast<GConnectFlags>(0));
  update_rounded_window_insets(GTK_WIDGET(window), content);
}

inline void add_rounded_window_content(GtkWindow* window, GtkWidget* content) {
  gtk_container_add(GTK_CONTAINER(window), content);
  track_rounded_window_content(window, content);
}

// Gives a window that another component already realized with a GTK header
// bar the same frame, with [content] as its child. The titlebar can no longer
// be replaced, so hiding it keeps the client-side frame without a second
// caption. A window without one uses server-side decorations and is left
// unchanged; returns whether the window now has the rounded frame.
inline bool adopt_rounded_window(GtkWindow* window, GtkWidget* content) {
  GtkWidget* titlebar = gtk_window_get_titlebar(window);
  if (titlebar == nullptr) return false;
  gtk_widget_hide(titlebar);
  gtk_widget_set_no_show_all(titlebar, TRUE);
  style_rounded_window(window);
  track_rounded_window_content(window, content);
  return true;
}


// The window owns this provider; updating it never clips the accelerated child.
inline void set_rounded_window_background(GtkWindow* window, guint32 argb) {
  auto* provider = static_cast<GtkCssProvider*>(
      g_object_get_data(G_OBJECT(window), "devmil-background-provider"));
  if (provider == nullptr) {
    provider = gtk_css_provider_new();
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(GTK_WIDGET(window)),
        GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_set_data_full(G_OBJECT(window), "devmil-background-provider",
                           provider, g_object_unref);
  }
  const GdkRGBA color = {((argb >> 16) & 255) / 255.0,
                         ((argb >> 8) & 255) / 255.0,
                         (argb & 255) / 255.0, (argb >> 24) / 255.0};
  g_autofree gchar* rgba = gdk_rgba_to_string(&color);
  g_autofree gchar* css =
      g_strdup_printf("window { background-color: %s; }", rgba);
  gtk_css_provider_load_from_data(provider, css, -1, nullptr);
}

#endif  // DEVMIL_ROUNDED_WINDOW_H_
