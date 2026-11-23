//! Native window hooks the QML window calls once it is shown.

use qtbridge::qobject;

unsafe extern "C" {
    fn gitlama_keyboard_modifiers() -> i32;
}

#[qobject(ConvertToCamelCase)]
mod platform_hooks {
    #[derive(Default)]
    pub struct PlatformHooks {}

    impl PlatformHooks {
        /// Gives macOS windows the unified, transparent toolbar title bar.
        #[qslot]
        fn configure_window(&self) {}

        /// Development: `GITLAMA_SCREENSHOT=<png>[;<step>...]` saves the
        /// window after startup (optionally after steps) and quits.
        #[qslot]
        fn screenshot_request(&self) -> String {
            std::env::var("GITLAMA_SCREENSHOT").unwrap_or_default()
        }

        /// The desktop's text scale: Linux follows GTK's text-scaling-factor
        /// like the GTK applications beside it; elsewhere 1.
        #[qslot]
        fn text_scale(&self) -> f64 {
            #[cfg(target_os = "linux")]
            {
                gsettings("org.gnome.desktop.interface", "text-scaling-factor")
                    .and_then(|value| value.parse::<f64>().ok())
                    .filter(|scale| scale.is_finite())
                    .map_or(1.0, |scale| scale.clamp(0.5, 3.0))
            }
            #[cfg(not(target_os = "linux"))]
            {
                1.0
            }
        }

        /// The platform's reduce-motion accessibility setting.
        /// The modifier keys held now (Qt.KeyboardModifiers).
        #[qslot]
        fn keyboard_modifiers(&self) -> i32 {
            // SAFETY: reads the GUI application's keyboard state on the GUI thread.
            unsafe { super::gitlama_keyboard_modifiers() }
        }

        #[qslot]
        fn reduce_motion(&self) -> bool {
            #[cfg(target_os = "linux")]
            {
                gsettings("org.gnome.desktop.interface", "enable-animations")
                    .is_some_and(|value| value == "false")
            }
            #[cfg(not(target_os = "linux"))]
            {
                false
            }
        }

        /// GTK's window button layout (`gtk-decoration-layout`), or "@none".
        #[qslot]
        fn caption_layout(&self) -> String {
            #[cfg(target_os = "linux")]
            {
                gsettings("org.gnome.desktop.wm.preferences", "button-layout")
                    .map(|value| value.trim_matches('\'').to_owned())
                    .unwrap_or_else(|| "@none".to_owned())
            }
            #[cfg(not(target_os = "linux"))]
            {
                "@none".to_owned()
            }
        }
    }

    #[cfg(target_os = "linux")]
    fn gsettings(schema: &str, key: &str) -> Option<String> {
        std::process::Command::new("gsettings")
            .args(["get", schema, key])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
    }
}

pub use platform_hooks::PlatformHooks;
