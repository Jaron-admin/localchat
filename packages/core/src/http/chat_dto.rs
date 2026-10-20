use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

pub const CHAT_VERSION: u32 = 1;
pub const MAX_TEXT_BYTES: usize = 32_768;
pub const MAX_CHAT_JSON_BYTES: usize = 262_144;

/// Optional top-level LocalSend prepare-upload extension; never placed in file metadata.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ChatTransferRef {
    pub message_id: String,
    pub transfer_id: String,
    pub attachments: HashMap<String, String>,
}

impl ChatTransferRef {
    pub fn matches_files(&self, files: &HashMap<String, crate::model::transfer::FileDto>) -> bool {
        is_chat_id(&self.message_id)
            && is_chat_id(&self.transfer_id)
            && !files.is_empty()
            && files.len() <= 1000
            && self.attachments.len() == files.len()
            && self.attachments.values().collect::<HashSet<_>>().len() == files.len()
            && self.attachments.iter().all(|(id, attachment)| {
                !id.is_empty() && id.len() <= 128 && is_chat_id(attachment)
                    && files.get(id).is_some_and(|file| file.id == *id)
            })
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ChatCapabilities {
    pub version: u32,
    pub features: Vec<String>,
    pub max_text_bytes: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ChatInvite {
    pub version: u32,
    pub invitation_id: String,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ChatInvitationStatus {
    Pending,
    Accepted,
    Rejected,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ChatInviteStatus {
    pub invitation_id: String,
    pub status: ChatInvitationStatus,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessageDto {
    pub version: u32,
    pub message_id: String,
    pub sent_at_ms: i64,
    pub text: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ChatAck {
    pub message_id: String,
    pub duplicate: bool,
}

#[derive(Clone, Debug)]
pub enum ChatOperation {
    Invite(ChatInvite),
    InviteStatus(String),
    Deliver(ChatMessageDto),
}

#[derive(Clone, Debug)]
pub enum ChatReply {
    Invitation(ChatInviteStatus),
    Stored(ChatAck),
    Rejected(ChatErrorCode),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChatErrorCode {
    Denied,
    Conflict,
    Unavailable,
    Overloaded,
}

/// Canonical UUID v4 spelling avoids multiple database keys for one UUID.
pub fn is_chat_id(value: &str) -> bool {
    uuid::Uuid::parse_str(value).is_ok_and(|id| {
        id.get_version() == Some(uuid::Version::Random)
            && id.get_variant() == uuid::Variant::RFC4122
            && id.hyphenated().to_string() == value
    })
}
