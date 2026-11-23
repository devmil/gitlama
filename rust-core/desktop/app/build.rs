//! Embeds the QML, Meridian, fonts and brand art as one Qt resource.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// A source directory, its resource prefix and which files it contributes.
type ResourceGroup = (PathBuf, &'static str, fn(&Path) -> bool);

fn main() {
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("manifest dir"));
    let root = manifest
        .join("../../..")
        .canonicalize()
        .expect("repository root");
    let version = fs::read_to_string(root.join("VERSION")).expect("VERSION");
    let mut lines = version.lines();
    let marketing = lines.next().unwrap_or("0.0.0").trim().to_owned();
    let build = lines.next().unwrap_or("0").trim().to_owned();
    println!("cargo:rustc-env=GITLAMA_VERSION={marketing}");
    println!("cargo:rustc-env=GITLAMA_BUILD={build}");
    println!("cargo:rerun-if-changed={}", root.join("VERSION").display());

    let groups: Vec<ResourceGroup> = vec![
        (root.join("qml/GitLama"), "GitLama", |_| true),
        (root.join("qml/Meridian"), "Meridian", |_| true),
        (root.join("resources/brand"), "GitLama/brand", |p| {
            p.extension().is_some_and(|e| e == "svg" || e == "png")
        }),
        (root.join("assets/brand"), "GitLama/brand", |p| {
            p.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("tile-") && name.ends_with(".png"))
        }),
    ];
    let mut document = String::from("<RCC>\n  <qresource prefix=\"/\">\n");
    for (directory, alias_root, keep) in &groups {
        println!("cargo:rerun-if-changed={}", directory.display());
        let mut files = Vec::new();
        collect(directory, &mut files);
        files.sort();
        for file in files.into_iter().filter(|f| keep(f)) {
            println!("cargo:rerun-if-changed={}", file.display());
            let relative = file
                .strip_prefix(directory)
                .expect("inside its root")
                .to_string_lossy()
                .replace('\\', "/");
            document.push_str(&format!(
                "    <file alias=\"{}/{}\">{}</file>\n",
                escape(alias_root),
                escape(&relative),
                escape(&file.to_string_lossy())
            ));
        }
    }
    document.push_str("  </qresource>\n</RCC>\n");
    let out = PathBuf::from(env::var("OUT_DIR").expect("out dir"));
    let qrc = out.join("gitlama.qrc");
    fs::write(&qrc, document).expect("write qrc");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux") {
        build_desktop_file_shim(&manifest);
    }
    build_native_items(&manifest, &out_dir());
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        build_windows_resource(&manifest, &out);
    }
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        // Sparkle, loaded at run time from the bundle (sparkle_bridge.m).
        let bridge = manifest.join("src/native/sparkle_bridge.m");
        println!("cargo:rerun-if-changed={}", bridge.display());
        cc::Build::new()
            .file(&bridge)
            .flag("-fobjc-arc")
            .compile("gitlama_sparkle_bridge");
        println!("cargo:rustc-link-lib=framework=Foundation");
        // Qt frameworks are linked by @rpath: the app bundle's Frameworks
        // folder, and Qt's own for development runs (packaging removes it).
        println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path/../Frameworks");
        if let Some(libs) = qt_query("QT_INSTALL_LIBS") {
            println!("cargo:rustc-link-arg=-Wl,-rpath,{libs}");
        }
    }

    let rcc =
        find_rcc().expect("Qt rcc was not found; set RCC or install the Qt 6 development tools");
    let status = Command::new(&rcc)
        .args(["-binary", "-o"])
        .arg(out.join("gitlama.rcc"))
        .arg(&qrc)
        .status()
        .expect("start rcc");
    assert!(status.success(), "rcc failed");
}

fn out_dir() -> PathBuf {
    PathBuf::from(env::var("OUT_DIR").expect("out dir"))
}

/// Compiles the Qt Quick items GitLama paints natively (the history graph
/// rows), with moc, against the Qt that qtbridge links.
fn build_native_items(manifest: &Path, out: &Path) {
    use qtbridge_build_utils::qt_build::QtInstallation;
    let qt = QtInstallation::new();
    let mut builder = cc::Build::new();
    builder.cpp(true).std("c++17");
    for name in ["graph_row", "text_formatter"] {
        let header = manifest.join(format!("src/native/{name}.h"));
        let source = manifest.join(format!("src/native/{name}.cpp"));
        println!("cargo:rerun-if-changed={}", header.display());
        println!("cargo:rerun-if-changed={}", source.display());
        let moc = out.join(format!("moc_{name}.cpp"));
        qt.run_moc(&header, &moc);
        builder.file(&source).file(&moc);
    }
    builder
        .include(manifest.join("src/native"))
        .flag_if_supported("/Zc:__cplusplus")
        .flag_if_supported("/permissive-")
        .flag_if_supported("-Wno-sfinae-incomplete");
    let modules = ["Core", "Gui", "Qml", "Quick"];
    for include in qt.include_dirs(modules, false) {
        builder.include(include);
    }
    qt.configure_builder(&mut builder);
    builder.compile("gitlama_native_items");
    qt.link_modules(modules);
}

fn collect(directory: &Path, files: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect(&path, files);
        } else {
            files.push(path);
        }
    }
}

fn escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('"', "&quot;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn find_rcc() -> Option<PathBuf> {
    if let Some(configured) = env::var_os("RCC") {
        return Some(PathBuf::from(configured));
    }
    let exe = if cfg!(windows) { "rcc.exe" } else { "rcc" };
    let configured = env::var("QMAKE").ok();
    println!("cargo:rerun-if-env-changed=QMAKE");
    for qmake in configured
        .iter()
        .map(String::as_str)
        .chain(["qmake6", "qmake"])
    {
        for key in [
            "QT_HOST_LIBEXECS",
            "QT_HOST_BINS",
            "QT_INSTALL_LIBEXECS",
            "QT_INSTALL_BINS",
        ] {
            if let Ok(output) = Command::new(qmake).args(["-query", key]).output()
                && output.status.success()
            {
                let candidate =
                    PathBuf::from(String::from_utf8_lossy(&output.stdout).trim()).join(exe);
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }
    }
    None
}

/// The executable's icon and version information (the Flutter runner's
/// Runner.rc), compiled with the MSVC resource compiler.
fn build_windows_resource(manifest: &Path, out: &Path) {
    let root = manifest.join("../../..");
    let version_file = root.join("VERSION");
    let icon = root.join("packaging/windows/app_icon.ico");
    println!("cargo:rerun-if-changed={}", version_file.display());
    println!("cargo:rerun-if-changed={}", icon.display());
    let text = fs::read_to_string(&version_file).expect("read VERSION");
    let mut lines = text.lines();
    let marketing = lines.next().unwrap_or("0.0.0").trim().to_owned();
    let build: u32 = lines
        .next()
        .and_then(|line| line.trim().parse().ok())
        .unwrap_or(0);
    let numbers: Vec<u32> = marketing
        .split(|c: char| !c.is_ascii_digit())
        .filter(|part| !part.is_empty())
        .take(3)
        .map(|part| part.parse().unwrap_or(0))
        .collect();
    let (major, minor, patch) = (
        numbers.first().copied().unwrap_or(0),
        numbers.get(1).copied().unwrap_or(0),
        numbers.get(2).copied().unwrap_or(0),
    );
    let rc = out.join("gitlama.rc");
    fs::write(
        &rc,
        format!(
            r#"#include <winver.h>
1 ICON "{icon}"
VS_VERSION_INFO VERSIONINFO
 FILEVERSION {major},{minor},{patch},{build}
 PRODUCTVERSION {major},{minor},{patch},{build}
 FILEOS VOS__WINDOWS32
 FILETYPE VFT_APP
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904e4"
    BEGIN
      VALUE "CompanyName", "de.devmil\0"
      VALUE "FileDescription", "GitLama\0"
      VALUE "FileVersion", "{marketing}\0"
      VALUE "InternalName", "gitlama\0"
      VALUE "LegalCopyright", "Copyright (C) 2026 de.devmil. All rights reserved.\0"
      VALUE "OriginalFilename", "gitlama.exe\0"
      VALUE "ProductName", "GitLama\0"
      VALUE "ProductVersion", "{marketing}\0"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1252
  END
END
"#,
            icon = icon.display().to_string().replace('\\', "\\\\"),
        ),
    )
    .expect("write gitlama.rc");
    let res = out.join("gitlama.res");
    let status = Command::new("rc.exe")
        .arg("/nologo")
        .arg(format!("/fo{}", res.display()))
        .arg(&rc)
        .status()
        .expect("rc.exe: run it from an MSVC developer environment");
    assert!(status.success(), "rc.exe failed");
    println!("cargo:rustc-link-arg-bins={}", res.display());
}

/// Compiles the QGuiApplication::setDesktopFileName shim against Qt's headers.
fn build_desktop_file_shim(manifest: &Path) {
    let source = manifest.join("src/native/desktop_file.cpp");
    println!("cargo:rerun-if-changed={}", source.display());
    let headers = qt_query("QT_INSTALL_HEADERS").expect("qmake -query QT_INSTALL_HEADERS");
    let headers = PathBuf::from(headers);
    cc::Build::new()
        .cpp(true)
        .std("c++17")
        .flag_if_supported("-fPIC")
        .include(&headers)
        .include(headers.join("QtCore"))
        .include(headers.join("QtGui"))
        .file(&source)
        .compile("gitlama_desktop_file");
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
