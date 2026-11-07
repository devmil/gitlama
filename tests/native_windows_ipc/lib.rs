//! Compile and exercise the production Windows IPC boundary without the UI engine.
#[cfg(windows)]
#[path = "../../rust-core/src/cli_forwarding/protocol.rs"]
pub mod protocol;
#[cfg(windows)]
#[path = "../../rust-core/src/cli_forwarding/windows.rs"]
pub mod native_windows;
