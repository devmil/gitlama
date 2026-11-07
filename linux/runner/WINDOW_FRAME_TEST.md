# Linux window frame regression

The opt-in native fixture draws opaque blue accelerated content through the same
window factory as the app. It checks opaque rectangular GL content inside smooth transparent native corners,
2px horizontal/3px vertical floating insets, retained decorations and
resize capability, resize/restore, and square edges when the compositor
acknowledges maximize. It also supports desktops without compositing, which
must keep solid square frames. The same checks then run on a window built in
desktop_multi_window's order (realized with a visible GTK header bar before
the content is added) after `adopt_rounded_window`, which inspection windows
use.

Compile without building Flutter or Rust:

```sh
c++ -std=c++14 -Wall -Werror linux/runner/window_frame_test.cc \
  $(pkg-config --cflags --libs gtk+-3.0 epoxy) \
  -o /tmp/window-frame-test
/tmp/window-frame-test
```

Run in an isolated X11 session with a window manager and compositor, or in a
Wayland session with an input seat. Repeat with `GDK_SCALE=2` and Adwaita,
Adwaita-dark, Breeze and Breeze-Dark themes. Set `FRAME_CAPTURE` to a PNG path
for visual inspection. The CMake option `BUILD_LINUX_WINDOW_TESTS=ON` builds the
same fixture beside the runner. Headless Xvfb without a compositor exercises
only the solid-frame fallback. A Wayland server without a seat is insufficient
for GTK initialization.

These checks cover native corners and content placement. The GL child must not
receive a curved clip or be redirected through an offscreen Cairo surface;
verify the actual app with `perf` as well to detect full-window GL readback. Full app appearance,
physical input and native WebView acceptance remain separate checks.
