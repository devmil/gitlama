//! Repository paths as text that QML can hold and hand back unchanged.
//!
//! Git paths are bytes, and on Unix they need not be UTF-8. A path that is
//! valid UTF-8 keeps its text; every byte of an invalid sequence becomes the
//! private-use character U+10FF00 + byte, so [`path_bytes`] returns the exact
//! bytes. A real U+10FF00..=U+10FFFF character is escaped byte by byte too,
//! which keeps the mapping reversible for every input.

const ESCAPE_BASE: u32 = 0x10_FF00;

fn escape(out: &mut String, bytes: &[u8]) {
    for byte in bytes {
        out.push(char::from_u32(ESCAPE_BASE + u32::from(*byte)).expect("a private-use scalar"));
    }
}

/// `bytes` as text: the same text when it is UTF-8 without escape-range characters.
pub fn path_text(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len());
    for chunk in bytes.utf8_chunks() {
        for character in chunk.valid().chars() {
            if u32::from(character) >= ESCAPE_BASE {
                let mut buffer = [0; 4];
                escape(&mut out, character.encode_utf8(&mut buffer).as_bytes());
            } else {
                out.push(character);
            }
        }
        escape(&mut out, chunk.invalid());
    }
    out
}

/// The bytes [`path_text`] made `text` from.
pub fn path_bytes(text: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(text.len());
    for character in text.chars() {
        let code = u32::from(character);
        if code >= ESCAPE_BASE {
            out.push((code - ESCAPE_BASE) as u8);
        } else {
            let mut buffer = [0; 4];
            out.extend_from_slice(character.encode_utf8(&mut buffer).as_bytes());
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf8_paths_keep_their_text() {
        assert_eq!(path_text("src/café.rs".as_bytes()), "src/café.rs");
        assert_eq!(path_bytes("src/café.rs"), "src/café.rs".as_bytes());
    }

    #[test]
    fn invalid_bytes_round_trip() {
        for bytes in [
            b"caf\xe9.txt".to_vec(),
            b"dir/\xff\xfe/x".to_vec(),
            b"\xc3".to_vec(),
            "a\u{10FF41}b".as_bytes().to_vec(),
        ] {
            let text = path_text(&bytes);
            assert!(!text.contains('\u{FFFD}'));
            assert_eq!(path_bytes(&text), bytes);
        }
        // The folder separator stays a separator.
        assert_eq!(path_text(b"dir/\xff\xfe/x").split('/').count(), 3);
    }
}
