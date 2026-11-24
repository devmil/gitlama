//! Adds Qt's framework directory to the macOS test binary rpath so `cargo test -p gitlama-qt`
//! can load `@rpath/QtCore.framework`.

use std::env;
use std::process::Command;

fn main() {
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    println!("cargo:rerun-if-env-changed=QMAKE");
    if let Some(libs) = qt_query("QT_INSTALL_LIBS") {
        println!("cargo:rustc-link-arg-tests=-Wl,-rpath,{libs}");
    }
}

fn qt_query(key: &str) -> Option<String> {
    let configured = env::var("QMAKE").ok();
    for qmake in configured
        .iter()
        .map(String::as_str)
        .chain(["qmake6", "qmake"])
    {
        if let Ok(output) = Command::new(qmake).args(["-query", key]).output()
            && output.status.success()
        {
            return Some(String::from_utf8_lossy(&output.stdout).trim().to_owned());
        }
    }
    None
}
