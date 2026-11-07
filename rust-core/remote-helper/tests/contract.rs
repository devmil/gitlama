//! The helper's wire names match the shared contract vectors and the protocol document.
use gitlama_application::wire::contract::{
    RemoteCapability, RemoteErrorCode, RemoteFatalCode, RemoteOutcome, RemoteWriteFamily,
    FRAME_BYTES, PAGE_ROWS, PATCH_BYTES, PATH_BYTES, STAGE_PATHS, STAGE_ROWS, SUMMARY_CHARACTERS,
    TRANSACTION_BYTES,
};
use serde_json::Value;
use std::path::Path;

fn vectors() -> Value {
    serde_json::from_str(include_str!("../fixtures/contract_vectors.json")).unwrap()
}

fn strings(value: &Value) -> Vec<&str> {
    value
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap())
        .collect()
}

fn family_capability(method: &str) -> Option<RemoteCapability> {
    let suffix = method
        .strip_prefix("preview")
        .or_else(|| method.strip_prefix("execute"))?;
    RemoteWriteFamily::of_method(suffix).map(RemoteWriteFamily::capability)
}

#[test]
fn methods_capabilities_outcomes_and_errors_match_the_vectors() {
    let v = vectors();
    for pair in v["methodCapabilities"].as_array().unwrap() {
        let method = pair[0].as_str().unwrap();
        let capability = pair[1].as_str().unwrap();
        assert_eq!(
            family_capability(method).map(RemoteCapability::name),
            Some(capability),
            "{method}"
        );
    }
    for method in strings(&v["notWriteMethods"]) {
        assert_eq!(family_capability(method), None, "{method}");
    }
    for name in strings(&v["capabilities"]["accept"]) {
        assert_eq!(
            RemoteCapability::parse(name).map(RemoteCapability::name),
            Some(name)
        );
    }
    for name in strings(&v["capabilities"]["reject"]) {
        assert_eq!(RemoteCapability::parse(name), None, "{name}");
    }
    let names = |list: &[RemoteCapability]| list.iter().map(|c| c.name()).collect::<Vec<_>>();
    assert_eq!(
        names(&RemoteCapability::WRITES),
        strings(&v["writeCapabilities"])
    );
    assert_eq!(
        names(&RemoteCapability::RECEIPT_WRITES),
        strings(&v["receiptWriteCapabilities"])
    );
    for name in strings(&v["outcomes"]["definite"]) {
        assert!(RemoteOutcome::parse(name).unwrap().definite(), "{name}");
    }
    for name in strings(&v["outcomes"]["open"]) {
        assert!(!RemoteOutcome::parse(name).unwrap().definite(), "{name}");
    }
    for name in strings(&v["outcomes"]["reject"]) {
        assert_eq!(RemoteOutcome::parse(name), None, "{name}");
    }
    let accepted = strings(&v["errors"]["accept"]);
    assert_eq!(
        RemoteErrorCode::ALL.map(RemoteErrorCode::name).to_vec(),
        accepted
    );
    for name in strings(&v["errors"]["reject"]) {
        assert_eq!(RemoteErrorCode::parse(name), None, "{name}");
    }
    let limits = &v["limits"];
    for (name, value) in [
        ("stagePaths", STAGE_PATHS),
        ("stageRows", STAGE_ROWS),
        ("patchBytes", PATCH_BYTES),
        ("frameBytes", FRAME_BYTES),
        ("transactionBytes", TRANSACTION_BYTES),
        ("pathBytes", PATH_BYTES),
        ("summaryCharacters", SUMMARY_CHARACTERS),
        ("pageRows", PAGE_ROWS),
    ] {
        assert_eq!(limits[name].as_u64(), Some(value as u64), "{name}");
    }
}

#[test]
fn every_error_the_helper_returns_is_a_contract_code() {
    let pattern = regex_lite_free_scan;
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    for entry in std::fs::read_dir(source).unwrap() {
        let path = entry.unwrap().path();
        let text = std::fs::read_to_string(&path).unwrap();
        for code in pattern(&text) {
            assert!(
                RemoteErrorCode::parse(&code).is_some(),
                "{}: {code} is not a contract error code",
                path.display()
            );
        }
    }
}

/// Quoted names inside `Err("…")`, `ok_or("…")` and `|_| "…"` error positions.
fn regex_lite_free_scan(text: &str) -> Vec<String> {
    let mut codes = Vec::new();
    for marker in ["Err(\"", "ok_or(\"", "|_| \""] {
        let mut rest = text;
        while let Some(index) = rest.find(marker) {
            rest = &rest[index + marker.len()..];
            let end = rest.find('"').unwrap();
            let name = &rest[..end];
            if !name.is_empty() && name.bytes().all(|b| b.is_ascii_alphabetic()) {
                codes.push(name.to_owned());
            }
        }
    }
    codes
}

#[test]
fn the_protocol_document_lists_the_contract_codes() {
    let document = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/remote-workspaces/PROTOCOL.md"),
    )
    .unwrap();
    let section = document
        .split("## Error codes")
        .nth(1)
        .unwrap()
        .split("\n## ")
        .next()
        .unwrap();
    for code in RemoteErrorCode::ALL {
        assert!(
            section.contains(&format!("`{}`", code.name())),
            "{}",
            code.name()
        );
    }
    for code in RemoteFatalCode::ALL {
        assert!(
            section.contains(&format!("`{}`", code.name())),
            "{}",
            code.name()
        );
    }
}
