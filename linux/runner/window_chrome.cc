#include "window_chrome.h"

#include "rounded_window.h"

namespace {

constexpr char kChannelName[] = "gitlama/window_chrome";

void respond_success(FlMethodCall* call, FlValue* value = nullptr) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  fl_method_call_respond(call, response, nullptr);
}

void respond_bool(FlMethodCall* call, gboolean value) {
  g_autoptr(FlValue) result = fl_value_new_bool(value);
  respond_success(call, result);
}

// The GTK `gtk-decoration-layout` setting, e.g. "menu:minimize,maximize,close".
// Dart parses it; unknown entries are ignored there.
FlValue* decoration_layout_value(GtkSettings* settings) {
  g_autofree gchar* layout = nullptr;
  g_object_get(settings, "gtk-decoration-layout", &layout, nullptr);
  return layout != nullptr ? fl_value_new_string(layout) : fl_value_new_null();
}

}  // namespace

struct _GitLamaWindowChrome {
  GtkWindow* window;
  FlMethodChannel* channel;
  // The last primary/secondary press inside the window. Compositor move drags
  // and the window menu need the originating press (Wayland uses its serial).
  GdkEvent* last_press;
  // The widget that received [last_press]; weak, cleared on destruction.
  GtkWidget* press_widget;
  gulong press_hook_id;
  // Held so teardown can disconnect even after the default display closed.
  GtkSettings* settings;
  gulong layout_handler_id;
};

static void clear_press(GitLamaWindowChrome* self) {
  g_clear_pointer(&self->last_press, gdk_event_free);
  if (self->press_widget != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(self->press_widget),
                                 reinterpret_cast<gpointer*>(
                                     &self->press_widget));
    self->press_widget = nullptr;
  }
}

static gboolean button_press_hook(GSignalInvocationHint*,
                                  guint n_param_values,
                                  const GValue* param_values,
                                  gpointer user_data) {
  auto* self = static_cast<GitLamaWindowChrome*>(user_data);
  if (n_param_values < 2) {
    return TRUE;
  }
  GtkWidget* widget = GTK_WIDGET(g_value_get_object(param_values));
  auto* event = static_cast<GdkEvent*>(g_value_get_boxed(param_values + 1));
  if (event == nullptr || event->type != GDK_BUTTON_PRESS ||
      gtk_widget_get_toplevel(widget) != GTK_WIDGET(self->window)) {
    return TRUE;
  }
  clear_press(self);
  self->last_press = gdk_event_copy(event);
  self->press_widget = widget;
  g_object_add_weak_pointer(G_OBJECT(widget),
                            reinterpret_cast<gpointer*>(&self->press_widget));
  return TRUE;
}

// The compositor owns the pointer once a move drag starts, so the Flutter view
// never sees the matching release. Deliver one so the caption gesture ends
// instead of leaving the engine believing the button is still held.
static void release_press(GitLamaWindowChrome* self) {
  if (self->last_press == nullptr || self->press_widget == nullptr) {
    return;
  }
  GdkEvent* release = gdk_event_copy(self->last_press);
  release->button.type = GDK_BUTTON_RELEASE;
  gboolean handled = FALSE;
  g_signal_emit_by_name(self->press_widget, "button-release-event", release,
                        &handled);
  gdk_event_free(release);
}

static gboolean begin_move(GitLamaWindowChrome* self) {
  if (self->last_press == nullptr) {
    return FALSE;
  }
  const GdkEventButton& press = self->last_press->button;
  gtk_window_begin_move_drag(self->window, static_cast<gint>(press.button),
                             static_cast<gint>(press.x_root),
                             static_cast<gint>(press.y_root), press.time);
  release_press(self);
  return TRUE;
}

static gboolean show_window_menu(GitLamaWindowChrome* self) {
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(self->window));
  if (self->last_press == nullptr || window == nullptr) {
    return FALSE;
  }
  return gdk_window_show_window_menu(window, self->last_press);
}

static void method_call_cb(FlMethodChannel*,
                           FlMethodCall* call,
                           gpointer user_data) {
  auto* self = static_cast<GitLamaWindowChrome*>(user_data);
  const gchar* method = fl_method_call_get_name(call);

  if (g_str_equal(method, "captionLayout")) {
    g_autoptr(FlValue) value = decoration_layout_value(self->settings);
    respond_success(call, value);
    return;
  }
  if (g_str_equal(method, "setBackgroundColor")) {
    FlValue* value = fl_method_call_get_args(call);
    if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT ||
        fl_value_get_int(value) < 0 || fl_value_get_int(value) > G_MAXUINT32) {
      fl_method_call_respond_error(call, "invalid-background", "Expected ARGB32",
                                   nullptr, nullptr);
      return;
    }
    set_rounded_window_background(
        self->window, static_cast<guint32>(fl_value_get_int(value)));
    respond_success(call);
    return;
  }
  if (g_str_equal(method, "beginMove")) {
    respond_bool(call, begin_move(self));
    return;
  }
  if (g_str_equal(method, "showWindowMenu")) {
    respond_bool(call, show_window_menu(self));
    return;
  }
  if (g_str_equal(method, "minimize")) {
    gtk_window_iconify(self->window);
    respond_success(call);
    return;
  }
  if (g_str_equal(method, "toggleMaximize")) {
    if (gtk_window_is_maximized(self->window)) {
      gtk_window_unmaximize(self->window);
    } else {
      gtk_window_maximize(self->window);
    }
    respond_success(call);
    return;
  }
  if (g_str_equal(method, "close")) {
    gtk_window_close(self->window);
    respond_success(call);
    return;
  }

  fl_method_call_respond_not_implemented(call, nullptr);
}

static void decoration_layout_changed(GObject*, GParamSpec*,
                                      gpointer user_data) {
  auto* self = static_cast<GitLamaWindowChrome*>(user_data);
  g_autoptr(FlValue) value = decoration_layout_value(self->settings);
  fl_method_channel_invoke_method(self->channel, "captionLayoutChanged", value,
                                  nullptr, nullptr, nullptr);
}

GtkWindow* gitlama_window_chrome_new_window(GtkApplication* application) {
  return create_rounded_application_window(application);
}

GitLamaWindowChrome* gitlama_window_chrome_new(
    GtkWindow* window,
    FlBinaryMessenger* messenger) {
  auto* self = new GitLamaWindowChrome();
  self->window = GTK_WINDOW(g_object_ref(window));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger, kChannelName,
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                            nullptr);
  self->press_hook_id = g_signal_add_emission_hook(
      g_signal_lookup("button-press-event", GTK_TYPE_WIDGET), 0,
      button_press_hook, self, nullptr);
  self->settings = GTK_SETTINGS(g_object_ref(gtk_settings_get_default()));
  self->layout_handler_id = g_signal_connect(
      self->settings, "notify::gtk-decoration-layout",
      G_CALLBACK(decoration_layout_changed), self);
  return self;
}

void gitlama_window_chrome_free(GitLamaWindowChrome* self) {
  if (self == nullptr) {
    return;
  }
  g_signal_remove_emission_hook(
      g_signal_lookup("button-press-event", GTK_TYPE_WIDGET),
      self->press_hook_id);
  g_signal_handler_disconnect(self->settings, self->layout_handler_id);
  g_clear_object(&self->settings);
  clear_press(self);
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                            nullptr);
  g_clear_object(&self->channel);
  g_clear_object(&self->window);
  delete self;
}

void gitlama_window_chrome_adopt_view(FlView* view) {
  auto* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  if (!GTK_IS_WINDOW(window)) {
    return;
  }
  adopt_rounded_window(window, GTK_WIDGET(view));
  // The chrome holds a reference on the window, so it ends with "destroy"
  // rather than with the window's data.
  GitLamaWindowChrome* chrome = gitlama_window_chrome_new(
      window, fl_engine_get_binary_messenger(fl_view_get_engine(view)));
  g_signal_connect(window, "destroy",
                   G_CALLBACK(+[](GtkWidget*, gpointer data) {
                     gitlama_window_chrome_free(
                         static_cast<GitLamaWindowChrome*>(data));
                   }),
                   chrome);
}
