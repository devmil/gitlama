//! GitLama's desktop library: the flutter_rust_bridge facade (`api`) Flutter loads and the
//! desktop-only services (hosting, CLI forwarding, child processes, avatars). Product
//! behaviour lives in `gitlama_application`; the bridge types in `gitlama_contract`.
pub mod api;
pub mod avatar;
pub mod child_process;
pub mod cli_forwarding;
mod frb_generated;
pub mod hosting;
pub mod hosting_reference;
pub mod hosting_review;
pub mod hosting_runtime;
#[cfg(test)]
mod loopback_fixture;

/// Restarts the process with the login shell's PATH when it differs, so Git
/// finds helpers such as `git-lfs` after a launch from the desktop. The macOS
/// runner calls this first in `main`, before a thread or a window exists.
///
/// `GITLAMA_KEEP_PATH` keeps the inherited PATH. Package qualification
/// sets it to start the application without Git.
#[no_mangle]
pub extern "C" fn gitlama_prepare_desktop_environment() {
    if std::env::var_os("GITLAMA_KEEP_PATH").is_none() {
        devmil_git::environment::prepare_desktop_process_environment();
    }
}
