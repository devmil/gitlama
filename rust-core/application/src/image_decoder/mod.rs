//! Single-worker, bounded decoding of repository-controlled raster images and passive SVGs.
//!
//! The decoded-image types are always available. Decoding itself needs the `image-codecs`
//! feature, which the desktop library enables; the headless remote helper builds without it and
//! answers every request as unsupported.
pub use gitlama_contract::image_decoder::*;

pub(crate) struct DecodeResult {
    pub old: Option<NativeDecodedImage>,
    pub new: Option<NativeDecodedImage>,
    pub failure: Option<NativeImageDecodeFailureKind>,
}

#[cfg(feature = "image-codecs")]
mod engine;
#[cfg(feature = "image-codecs")]
pub(crate) use engine::{cancel_session, decode_pair};

#[cfg(not(feature = "image-codecs"))]
pub(crate) fn decode_pair(
    _session_id: u64,
    _old: Option<Vec<u8>>,
    _new: Option<Vec<u8>>,
) -> DecodeResult {
    DecodeResult {
        old: None,
        new: None,
        failure: Some(NativeImageDecodeFailureKind::Unsupported),
    }
}

#[cfg(not(feature = "image-codecs"))]
pub(crate) fn cancel_session(_session_id: u64) {}

crate::family_failures!(NativeImageDecodeFailureKind, "imageDecode", {
    Busy => Busy,
    Unsupported => Unsupported,
    Malformed => Internal,
    TooLarge => TooLarge,
    TimedOut => TimedOut,
    Canceled => Canceled,
});
