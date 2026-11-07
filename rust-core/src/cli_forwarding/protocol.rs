//! Versioned and bounded local command-forwarding protocol.

use std::fmt;
use std::io::{Read, Write};

pub const PROTOCOL_VERSION: u16 = 1;
pub const TOKEN_LEN: usize = 32;
pub const NONCE_LEN: usize = 16;
pub const MAX_FRAME_LEN: usize = 64 * 1024;
pub const MAX_PATH_LEN: usize = 16 * 1024;
/// The longest SSH alias a host profile accepts.
pub const MAX_ALIAS_LEN: usize = 128;
pub const MAX_DETAIL_LEN: usize = 1024;
const MAGIC: &[u8; 4] = b"NSPF";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ForwardRequest {
    pub nonce: [u8; NONCE_LEN],
    pub token: [u8; TOKEN_LEN],
    pub action: ForwardAction,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ForwardAction {
    Activate,
    OpenRepository {
        native_path: Vec<u8>,
    },
    /// An absolute POSIX path on the saved host with SSH alias `alias`.
    OpenRemoteRepository {
        alias: String,
        path: Vec<u8>,
    },
    Invoke(AllowedCommand),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AllowedCommand {
    Refresh,
    Fetch,
    Pull { strategy: AllowedPullStrategy },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AllowedPullStrategy {
    FastForwardOnly,
    FastForwardIfPossible,
    Rebase,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ForwardResponse {
    Accepted,
    Rejected { code: ResponseCode, detail: String },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum ResponseCode {
    Authentication = 1,
    Replay = 2,
    InvalidPath = 3,
    NotRepository = 4,
    UnsupportedCommand = 5,
    Busy = 6,
    Internal = 7,
    Precondition = 8,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ProtocolError {
    Io(std::io::ErrorKind),
    Oversized,
    Truncated,
    InvalidMagic,
    VersionSkew { received: u16 },
    Malformed,
    InvalidUtf8,
}

impl fmt::Display for ProtocolError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{self:?}")
    }
}

impl std::error::Error for ProtocolError {}

pub fn write_request(
    writer: &mut impl Write,
    request: &ForwardRequest,
) -> Result<(), ProtocolError> {
    let mut payload = Vec::new();
    payload.extend_from_slice(MAGIC);
    payload.extend_from_slice(&PROTOCOL_VERSION.to_be_bytes());
    payload.extend_from_slice(&request.nonce);
    payload.extend_from_slice(&request.token);
    match &request.action {
        ForwardAction::Activate => payload.push(1),
        ForwardAction::OpenRepository { native_path } => {
            bounded(native_path.len(), MAX_PATH_LEN)?;
            payload.push(2);
            push_bytes(&mut payload, native_path)?;
        }
        ForwardAction::Invoke(AllowedCommand::Refresh) => payload.push(3),
        ForwardAction::Invoke(AllowedCommand::Fetch) => payload.push(4),
        ForwardAction::Invoke(AllowedCommand::Pull { strategy }) => payload.push(match strategy {
            AllowedPullStrategy::FastForwardOnly => 5,
            AllowedPullStrategy::FastForwardIfPossible => 6,
            AllowedPullStrategy::Rebase => 7,
        }),
        ForwardAction::OpenRemoteRepository { alias, path } => {
            bounded(alias.len(), MAX_ALIAS_LEN)?;
            bounded(path.len(), MAX_PATH_LEN)?;
            payload.push(8);
            push_bytes(&mut payload, alias.as_bytes())?;
            push_bytes(&mut payload, path)?;
        }
    }
    write_frame(writer, &payload)
}

pub fn read_request(reader: &mut impl Read) -> Result<ForwardRequest, ProtocolError> {
    let payload = read_frame(reader)?;
    let mut cursor = Cursor::new(&payload);
    if cursor.take(4)? != MAGIC {
        return Err(ProtocolError::InvalidMagic);
    }
    let received = u16::from_be_bytes(cursor.array()?);
    if received != PROTOCOL_VERSION {
        return Err(ProtocolError::VersionSkew { received });
    }
    let nonce = cursor.array()?;
    let token = cursor.array()?;
    let action = match cursor.byte()? {
        1 => ForwardAction::Activate,
        2 => ForwardAction::OpenRepository {
            native_path: cursor.bytes(MAX_PATH_LEN)?.to_vec(),
        },
        3 => ForwardAction::Invoke(AllowedCommand::Refresh),
        4 => ForwardAction::Invoke(AllowedCommand::Fetch),
        5 => ForwardAction::Invoke(AllowedCommand::Pull {
            strategy: AllowedPullStrategy::FastForwardOnly,
        }),
        6 => ForwardAction::Invoke(AllowedCommand::Pull {
            strategy: AllowedPullStrategy::FastForwardIfPossible,
        }),
        7 => ForwardAction::Invoke(AllowedCommand::Pull {
            strategy: AllowedPullStrategy::Rebase,
        }),
        8 => ForwardAction::OpenRemoteRepository {
            alias: String::from_utf8(cursor.bytes(MAX_ALIAS_LEN)?.to_vec())
                .map_err(|_| ProtocolError::InvalidUtf8)?,
            path: cursor.bytes(MAX_PATH_LEN)?.to_vec(),
        },
        _ => return Err(ProtocolError::Malformed),
    };
    if !cursor.is_empty() {
        return Err(ProtocolError::Malformed);
    }
    Ok(ForwardRequest {
        nonce,
        token,
        action,
    })
}

pub fn write_response(
    writer: &mut impl Write,
    response: &ForwardResponse,
) -> Result<(), ProtocolError> {
    let mut payload = Vec::new();
    payload.extend_from_slice(MAGIC);
    payload.extend_from_slice(&PROTOCOL_VERSION.to_be_bytes());
    match response {
        ForwardResponse::Accepted => payload.push(0),
        ForwardResponse::Rejected { code, detail } => {
            bounded(detail.len(), MAX_DETAIL_LEN)?;
            payload.push(*code as u8);
            push_bytes(&mut payload, detail.as_bytes())?;
        }
    }
    write_frame(writer, &payload)
}

pub fn read_response(reader: &mut impl Read) -> Result<ForwardResponse, ProtocolError> {
    let payload = read_frame(reader)?;
    let mut cursor = Cursor::new(&payload);
    if cursor.take(4)? != MAGIC {
        return Err(ProtocolError::InvalidMagic);
    }
    let received = u16::from_be_bytes(cursor.array()?);
    if received != PROTOCOL_VERSION {
        return Err(ProtocolError::VersionSkew { received });
    }
    let raw_code = cursor.byte()?;
    let response = if raw_code == 0 {
        ForwardResponse::Accepted
    } else {
        let detail = String::from_utf8(cursor.bytes(MAX_DETAIL_LEN)?.to_vec())
            .map_err(|_| ProtocolError::InvalidUtf8)?;
        let code = match raw_code {
            1 => ResponseCode::Authentication,
            2 => ResponseCode::Replay,
            3 => ResponseCode::InvalidPath,
            4 => ResponseCode::NotRepository,
            5 => ResponseCode::UnsupportedCommand,
            6 => ResponseCode::Busy,
            7 => ResponseCode::Internal,
            8 => ResponseCode::Precondition,
            _ => return Err(ProtocolError::Malformed),
        };
        ForwardResponse::Rejected { code, detail }
    };
    if !cursor.is_empty() {
        return Err(ProtocolError::Malformed);
    }
    Ok(response)
}

fn write_frame(writer: &mut impl Write, payload: &[u8]) -> Result<(), ProtocolError> {
    bounded(payload.len(), MAX_FRAME_LEN)?;
    let length = u32::try_from(payload.len()).map_err(|_| ProtocolError::Oversized)?;
    writer
        .write_all(&length.to_be_bytes())
        .and_then(|()| writer.write_all(payload))
        .map_err(io_error)
}

fn read_frame(reader: &mut impl Read) -> Result<Vec<u8>, ProtocolError> {
    let mut length = [0; 4];
    reader.read_exact(&mut length).map_err(read_error)?;
    let length =
        usize::try_from(u32::from_be_bytes(length)).map_err(|_| ProtocolError::Oversized)?;
    bounded(length, MAX_FRAME_LEN)?;
    let mut payload = vec![0; length];
    reader.read_exact(&mut payload).map_err(read_error)?;
    Ok(payload)
}

fn push_bytes(payload: &mut Vec<u8>, bytes: &[u8]) -> Result<(), ProtocolError> {
    let length = u32::try_from(bytes.len()).map_err(|_| ProtocolError::Oversized)?;
    payload.extend_from_slice(&length.to_be_bytes());
    payload.extend_from_slice(bytes);
    Ok(())
}

fn bounded(length: usize, maximum: usize) -> Result<(), ProtocolError> {
    if length > maximum {
        Err(ProtocolError::Oversized)
    } else {
        Ok(())
    }
}

fn io_error(error: std::io::Error) -> ProtocolError {
    ProtocolError::Io(error.kind())
}

fn read_error(error: std::io::Error) -> ProtocolError {
    if error.kind() == std::io::ErrorKind::UnexpectedEof {
        ProtocolError::Truncated
    } else {
        io_error(error)
    }
}

struct Cursor<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Cursor<'a> {
    const fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn take(&mut self, length: usize) -> Result<&'a [u8], ProtocolError> {
        let end = self
            .offset
            .checked_add(length)
            .ok_or(ProtocolError::Malformed)?;
        let value = self
            .bytes
            .get(self.offset..end)
            .ok_or(ProtocolError::Truncated)?;
        self.offset = end;
        Ok(value)
    }

    fn array<const N: usize>(&mut self) -> Result<[u8; N], ProtocolError> {
        self.take(N)?
            .try_into()
            .map_err(|_| ProtocolError::Truncated)
    }

    fn byte(&mut self) -> Result<u8, ProtocolError> {
        Ok(self.array::<1>()?[0])
    }

    fn bytes(&mut self, maximum: usize) -> Result<&'a [u8], ProtocolError> {
        let length = usize::try_from(u32::from_be_bytes(self.array()?))
            .map_err(|_| ProtocolError::Oversized)?;
        bounded(length, maximum)?;
        self.take(length)
    }

    fn is_empty(&self) -> bool {
        self.offset == self.bytes.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_round_trip_and_version_bounds() {
        let request = ForwardRequest {
            nonce: [7; NONCE_LEN],
            token: [9; TOKEN_LEN],
            action: ForwardAction::Invoke(AllowedCommand::Pull {
                strategy: AllowedPullStrategy::Rebase,
            }),
        };
        let mut bytes = Vec::new();
        write_request(&mut bytes, &request).unwrap();
        assert_eq!(read_request(&mut bytes.as_slice()).unwrap(), request);

        let mut skewed = bytes;
        skewed[8] = 0;
        skewed[9] = 2;
        assert_eq!(
            read_request(&mut skewed.as_slice()),
            Err(ProtocolError::VersionSkew { received: 2 })
        );
        let oversized = u32::try_from(MAX_FRAME_LEN + 1).unwrap().to_be_bytes();
        assert_eq!(
            read_request(&mut oversized.as_slice()),
            Err(ProtocolError::Oversized)
        );
    }

    #[test]
    fn remote_open_round_trips() {
        let request = ForwardRequest {
            nonce: [3; NONCE_LEN],
            token: [4; TOKEN_LEN],
            action: ForwardAction::OpenRemoteRepository {
                alias: "fedora".into(),
                path: b"/home/me/notelama".to_vec(),
            },
        };
        let mut bytes = Vec::new();
        write_request(&mut bytes, &request).unwrap();
        assert_eq!(read_request(&mut bytes.as_slice()).unwrap(), request);
    }

    #[test]
    fn truncated_and_malformed_frames_fail_closed() {
        let request = ForwardRequest {
            nonce: [1; NONCE_LEN],
            token: [2; TOKEN_LEN],
            action: ForwardAction::Activate,
        };
        let mut bytes = Vec::new();
        write_request(&mut bytes, &request).unwrap();
        bytes.pop();
        assert_eq!(
            read_request(&mut bytes.as_slice()),
            Err(ProtocolError::Truncated)
        );

        let mut bytes = Vec::new();
        write_request(&mut bytes, &request).unwrap();
        bytes.push(0);
        let payload_length = u32::from_be_bytes(bytes[..4].try_into().unwrap()) + 1;
        bytes[..4].copy_from_slice(&payload_length.to_be_bytes());
        assert_eq!(
            read_request(&mut bytes.as_slice()),
            Err(ProtocolError::Malformed)
        );
    }
}
