//! The bridge types of `hosting_settings`: plain data the FRB facade and the remote wire adapter
//! carry. Behaviour lives in the application crate's module of the same name.
use crate::domain::path_identity::NativePathIdentity;
use serde::{Deserialize, Serialize};

// Stored-document defaults for fields older settings omit.
const fn default_true() -> bool {
    true
}

fn default_hosting_authentication() -> String {
    "oauth".into()
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeHostingConnectionSettings {
    pub id: String,
    pub preset: String,
    pub login: String,
    pub web_base_url: String,
    pub api_base_url: String,
    pub oauth_client_id: String,
    #[serde(default = "default_hosting_authentication")]
    pub authentication: String,
    pub enabled: bool,
    #[serde(default = "default_true")]
    pub refresh_enabled: bool,
    pub capabilities: Vec<String>,
    pub credential_identity: String,
    pub allow_split_origin: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeHostingBindingSettings {
    pub repository: NativePathIdentity,
    pub remote: Vec<u8>,
    pub connection_id: String,
    pub provider_repository: String,
}
