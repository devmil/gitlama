//! Embeds the canonical release identity so the running application can
//! compare itself with published releases, and the remote helper ID both the
//! desktop library and the helper report.
use std::path::PathBuf;

fn main() {
    let manifest = PathBuf::from(
        std::env::var_os("CARGO_MANIFEST_DIR").expect("Cargo sets CARGO_MANIFEST_DIR"),
    );
    let path = manifest.join("../../VERSION");
    println!("cargo:rerun-if-changed={}", path.display());
    let text = std::fs::read_to_string(&path).expect("VERSION must be readable");
    let mut lines = text.lines();
    let version = lines.next().unwrap_or_default().trim();
    let build = lines.next().unwrap_or_default().trim();
    assert!(
        !version.is_empty() && version.len() <= 64 && version.is_ascii(),
        "VERSION line 1 must be the marketing version"
    );
    assert!(
        build.parse::<u32>().is_ok_and(|value| value > 0),
        "VERSION line 2 must be the positive build number"
    );
    println!("cargo:rustc-env=GITLAMA_RELEASE_VERSION={version}");
    println!(
        "cargo:rustc-env=GITLAMA_SOURCE_COMMIT={}",
        source_commit(&manifest)
    );
    println!("cargo:rustc-env=GITLAMA_RELEASE_BUILD={build}");
    println!(
        "cargo:rustc-env=GITLAMA_REMOTE_HELPER_ID={}",
        remote_helper_id(&manifest)
    );
}

/// The ID a remote helper reports and is installed under: its compatibility version from
/// `rust-core/remote-helper/COMPATIBILITY`, as 40 decimal digits. Builds that leave the helper's
/// behaviour alone keep the version, so hosts keep the helper they already run.
fn remote_helper_id(manifest: &std::path::Path) -> String {
    let path = manifest.join("../remote-helper/COMPATIBILITY");
    println!("cargo:rerun-if-changed={}", path.display());
    let text =
        std::fs::read_to_string(&path).expect("remote-helper/COMPATIBILITY must be readable");
    let version = text
        .lines()
        .find_map(|line| line.trim().strip_prefix("version "))
        .map(str::trim)
        .expect("remote-helper/COMPATIBILITY must declare a version");
    assert!(
        !version.is_empty()
            && version.len() <= 6
            && !version.starts_with('0')
            && version.bytes().all(|b| b.is_ascii_digit()),
        "the remote helper compatibility version must be a positive integer"
    );
    format!("{version:0>40}")
}

/// The 40-hex source commit, from `GITLAMA_SOURCE_COMMIT` in release builds or the checkout.
/// A build without either reports all zeros, which no published helper matches.
fn source_commit(manifest: &std::path::Path) -> String {
    println!("cargo:rerun-if-env-changed=GITLAMA_SOURCE_COMMIT");
    let valid = |value: &str| {
        value.len() == 40
            && value
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
    };
    if let Ok(value) = std::env::var("GITLAMA_SOURCE_COMMIT") {
        assert!(
            valid(&value),
            "GITLAMA_SOURCE_COMMIT must be 40 lowercase hex digits"
        );
        return value;
    }
    let git = |args: &[&str]| {
        std::process::Command::new("git")
            .arg("-C")
            .arg(manifest)
            .args(args)
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
    };
    for reference in ["HEAD", "logs/HEAD"] {
        if let Some(path) = git(&[
            "rev-parse",
            "--path-format=absolute",
            "--git-path",
            reference,
        ]) {
            println!("cargo:rerun-if-changed={path}");
        }
    }
    git(&["rev-parse", "HEAD"])
        .filter(|value| valid(value))
        .unwrap_or_else(|| "0".repeat(40))
}
