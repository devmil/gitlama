//! Repository and tab group appearance values (the Dart
//! `repository_appearance.dart`).

/// The icons a repository tab can show (Meridian's Lucide names).
pub const REPOSITORY_ICONS: [&str; 24] = [
    "folder-git-2",
    "code-xml",
    "square-terminal",
    "box",
    "blocks",
    "puzzle",
    "layers",
    "book-open",
    "palette",
    "image",
    "smartphone",
    "monitor",
    "server",
    "cloud",
    "zap",
    "star",
    "flag",
    "bug",
    "wand-sparkles",
    "graduation-cap",
    "shield-check",
    "chart-line",
    "house",
    "users",
];

/// Meridian's categorical series colours, in order (`series-1` … `series-8`).
pub const PALETTE_COLORS: [&str; 8] = [
    "blue", "teal", "amber", "orange", "rose", "violet", "cyan", "olive",
];

/// The longest tab or group name, in UTF-8 bytes.
pub const MAX_TAB_NAME_BYTES: usize = 256;

/// Whether `key` names a colour: a palette name or `rgb-rrggbb`.
pub fn is_color_key(key: &str) -> bool {
    PALETTE_COLORS.contains(&key)
        || key
            .strip_prefix("rgb-")
            .is_some_and(|hex| hex.len() == 6 && hex.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)))
}

pub fn is_icon(name: &str) -> bool {
    REPOSITORY_ICONS.contains(&name)
}

/// `name` as a tab or group name: one line, trimmed and bounded; None when
/// nothing is left.
pub fn normalize_tab_name(name: &str) -> Option<String> {
    let mut normalized = String::with_capacity(name.len());
    let mut in_control = false;
    for ch in name.chars() {
        let control = ('\u{0}'..='\u{1f}').contains(&ch) || ('\u{7f}'..='\u{9f}').contains(&ch);
        if control {
            if !in_control {
                normalized.push(' ');
            }
            in_control = true;
        } else {
            normalized.push(ch);
            in_control = false;
        }
    }
    let mut normalized = normalized.trim().to_owned();
    while normalized.len() > MAX_TAB_NAME_BYTES {
        normalized.pop();
        normalized = normalized.trim_end().to_owned();
    }
    (!normalized.is_empty()).then_some(normalized)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_one_trimmed_bounded_line() {
        assert_eq!(normalize_tab_name("  a\n\tb  "), Some("a b".into()));
        assert_eq!(normalize_tab_name(" \n "), None);
        assert_eq!(normalize_tab_name(&"x".repeat(300)).unwrap().len(), 256);
        assert!(is_color_key("rgb-00ff10"));
        assert!(!is_color_key("rgb-00FF10"));
    }
}
