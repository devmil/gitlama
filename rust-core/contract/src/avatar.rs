//! The bridge types of `avatar`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the desktop library's (`gitlama_core`) module of the same name.

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NativeAvatarSource {
    Gravatar,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeAvatarImage {
    pub source: NativeAvatarSource,
    pub bytes: Vec<u8>,
}
