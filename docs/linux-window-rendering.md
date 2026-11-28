# Linux window rendering

On Linux the main window is a frameless Qt Quick window (`Qt.FramelessWindowHint` in
`qml/GitLama/Main.qml`) that draws its own caption in the top toolbar row, the way GTK
applications with client-side decorations do. Qt renders the window through its default
scene graph backend for the session (OpenGL on Wayland and X11); there is no
offscreen content mask or toolkit wrapper around the surface. On Wayland sessions
(`WAYLAND_DISPLAY` set and `QSG_RENDER_LOOP` unset), `main.rs` defaults
`QSG_RENDER_LOOP=basic` so interactive resizes do not stall the GUI thread waiting on
the render thread's `eglSwapBuffers` frame callback.

- **Window buttons** follow the desktop's configuration: `PlatformHooks.captionLayout`
  reads GNOME's `button-layout` (`gtk-decoration-layout`), and `WindowControls` shows the
  buttons it names at the leading and trailing ends of the toolbar. `@none` shows none.
- **Moving and maximizing**: `WindowDragArea` covers the empty toolbar; a drag starts the
  compositor's move (`startSystemMove`) and a double click toggles maximized.
- **Resizing**: `LinuxResizeEdges` puts 6px grips along the edges and corners that start
  the compositor's resize (`startSystemResize`). Tiling compositors such as Hyprland
  manage the size themselves and never deliver these.
- **Text scale** follows GNOME's `text-scaling-factor` (`PlatformHooks.textScale`) so GitLama
  matches the GTK applications beside it.
- **Desktop identity**: the Wayland app ID and the desktop entry are `de.devmil.gitlama`,
  so docks, launchers and window rules keep matching after an update from earlier releases.

macOS keeps the native frame with a unified, transparent toolbar title bar
(`PlatformHooks.configureWindow`); Windows keeps the native frame.

The port ran on Arch Linux (Omarchy, Hyprland, Wayland). Moving and resizing on floating
compositors, other desktops (GNOME, KDE, X11 sessions) and fractional scaling have not been
checked yet.
