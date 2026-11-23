//! Native window hooks the QML window calls once it is shown.

use qtbridge::qobject;

unsafe extern "C" {
    fn gitlama_keyboard_modifiers() -> i32;
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn gitlama_configure_windows();
    fn gitlama_system_reduce_motion() -> bool;
    fn gitlama_share_text(
        text: *const std::ffi::c_char,
        x: f64,
        y: f64,
        width: f64,
        height: f64,
    ) -> bool;
}

#[qobject(ConvertToCamelCase)]
mod platform_hooks {
    #[derive(Default)]
    pub struct PlatformHooks {}

    impl PlatformHooks {
        /// Gives macOS windows the unified, transparent toolbar title bar.
        #[qslot]
        fn configure_window(&self) {
            #[cfg(target_os = "macos")]
            // SAFETY: configures the application's windows on the GUI thread.
            unsafe {
                super::gitlama_configure_windows();
            }
        }

        /// Whether `shareText` can offer the platform's share sheet: macOS and Windows.
        #[qslot]
        fn can_share(&self) -> bool {
            cfg!(any(target_os = "macos", target_os = "windows"))
        }

        /// Offers `text` to the platform's share sheet under the localized `title`, anchored
        /// below the rectangle (window coordinates, logical pixels). No file is written. False
        /// when it cannot be shown.
        #[qslot]
        fn share_text(
            &self,
            text: String,
            title: String,
            x: f64,
            y: f64,
            width: f64,
            height: f64,
        ) -> bool {
            #[cfg(target_os = "macos")]
            {
                let _ = title;
                let Ok(text) = std::ffi::CString::new(text) else {
                    return false;
                };
                // SAFETY: a NUL-terminated string valid for the call, on the GUI thread.
                unsafe { super::gitlama_share_text(text.as_ptr(), x, y, width, height) }
            }
            #[cfg(target_os = "windows")]
            {
                let _ = (x, y, width, height);
                super::windows_share::share_text(&text, &title)
            }
            #[cfg(not(any(target_os = "macos", target_os = "windows")))]
            {
                let _ = (text, title, x, y, width, height);
                false
            }
        }

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
            #[cfg(target_os = "macos")]
            // SAFETY: reads the accessibility setting on the GUI thread.
            unsafe {
                super::gitlama_system_reduce_motion()
            }
            #[cfg(target_os = "windows")]
            {
                super::windows_share::reduce_motion()
            }
            #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
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

#[cfg(target_os = "windows")]
mod windows_share {
    use windows::ApplicationModel::DataTransfer::{DataRequestedEventArgs, DataTransferManager};
    use windows::Foundation::TypedEventHandler;
    use windows::Win32::UI::Input::KeyboardAndMouse::GetActiveWindow;
    use windows::Win32::UI::Shell::IDataTransferManagerInterop;
    use windows::Win32::UI::WindowsAndMessaging::{
        SPI_GETCLIENTAREAANIMATION, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS, SystemParametersInfoW,
    };
    use windows::core::{HSTRING, factory};

    /// Shows the Share UI for the active window with `text` as its data.
    pub fn share_text(text: &str, title: &str) -> bool {
        let shown = || -> windows::core::Result<()> {
            // SAFETY: the active window of this (the GUI) thread.
            let window = unsafe { GetActiveWindow() };
            if window.is_invalid() {
                return Err(windows::core::Error::empty());
            }
            let interop = factory::<DataTransferManager, IDataTransferManagerInterop>()?;
            // SAFETY: a valid top-level window of this process.
            let manager: DataTransferManager = unsafe { interop.GetForWindow(window)? };
            let text = HSTRING::from(text);
            let title = HSTRING::from(title);
            let token = std::sync::Arc::new(std::sync::Mutex::new(None::<i64>));
            let handler_token = std::sync::Arc::clone(&token);
            let handler = TypedEventHandler::<DataTransferManager, DataRequestedEventArgs>::new(
                move |sender, args| {
                    let request = args.ok()?.Request()?;
                    let data = request.Data()?;
                    data.Properties()?.SetTitle(&title)?;
                    data.SetText(&text)?;
                    // One request per Share: the handler removes itself.
                    if let Some(token) = handler_token.lock().ok().and_then(|mut slot| slot.take())
                    {
                        let _ = sender.ok()?.RemoveDataRequested(token);
                    }
                    Ok(())
                },
            );
            *token.lock().map_err(|_| windows::core::Error::empty())? =
                Some(manager.DataRequested(&handler)?);
            // SAFETY: the same window the manager belongs to.
            unsafe { interop.ShowShareUIForWindow(window) }
        };
        shown().is_ok()
    }

    /// Windows' "Show animations in Windows" setting, off meaning reduce motion.
    pub fn reduce_motion() -> bool {
        let mut animations = windows::core::BOOL(1);
        // SAFETY: SPI_GETCLIENTAREAANIMATION writes one BOOL.
        let read = unsafe {
            SystemParametersInfoW(
                SPI_GETCLIENTAREAANIMATION,
                0,
                Some((&raw mut animations).cast()),
                SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
            )
        };
        read.is_ok() && !animations.as_bool()
    }
}
