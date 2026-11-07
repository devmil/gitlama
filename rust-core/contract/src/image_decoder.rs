//! The bridge types of `image_decoder`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeDecodedImage {
    pub width: u32,
    pub height: u32,
    /// Size of the stored file the pixels were decoded from.
    pub encoded_bytes: u64,
    pub rgba: Vec<u8>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NativeImageDecodeFailureKind {
    Busy,
    Unsupported,
    Malformed,
    TooLarge,
    TimedOut,
    Canceled,
}
