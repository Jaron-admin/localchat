use flutter_rust_bridge::frb;
pub use localsend::http::chat_dto::{
    ChatAck, ChatCapabilities, ChatErrorCode, ChatInvitationStatus, ChatInvite, ChatInviteStatus,
    ChatMessageDto, ChatOperation, ChatReply, ChatTransferRef,
};
pub use localsend::http::dto::{
    PrepareUploadRequestDto, PrepareUploadResponseDto, RegisterDto, RegisterResponseDto,
};
pub use localsend::model::discovery::DeviceType;
pub use localsend::model::discovery::ProtocolType;
pub use localsend::model::transfer::{FileDto, FileMetadata};
use std::collections::HashMap;

#[frb(mirror(ChatTransferRef))]
pub struct _ChatTransferRef {
    pub message_id: String,
    pub transfer_id: String,
    pub attachments: HashMap<String, String>,
}

#[frb(mirror(ChatCapabilities))]
pub struct _ChatCapabilities {
    pub version: u32,
    pub features: Vec<String>,
    pub max_text_bytes: u32,
}
#[frb(mirror(ChatInvite))]
pub struct _ChatInvite {
    pub version: u32,
    pub invitation_id: String,
}
#[frb(mirror(ChatInviteStatus))]
pub struct _ChatInviteStatus {
    pub invitation_id: String,
    pub status: ChatInvitationStatus,
}
#[frb(mirror(ChatInvitationStatus))]
pub enum _ChatInvitationStatus {
    Pending,
    Accepted,
    Rejected,
}
#[frb(mirror(ChatMessageDto))]
pub struct _ChatMessageDto {
    pub version: u32,
    pub message_id: String,
    pub sent_at_ms: i64,
    pub text: String,
}
#[frb(mirror(ChatAck))]
pub struct _ChatAck {
    pub message_id: String,
    pub duplicate: bool,
}
#[frb(mirror(ChatOperation))]
pub enum _ChatOperation {
    Invite(ChatInvite),
    InviteStatus(String),
    Deliver(ChatMessageDto),
}
#[frb(mirror(ChatReply))]
pub enum _ChatReply {
    Invitation(ChatInviteStatus),
    Stored(ChatAck),
    Rejected(ChatErrorCode),
}
#[frb(mirror(ChatErrorCode))]
pub enum _ChatErrorCode {
    Denied,
    Conflict,
    Unavailable,
    Overloaded,
}

#[frb(mirror(RegisterDto))]
pub struct _RegisterDto {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub token: String,
    pub port: u16,
    pub protocol: ProtocolType,
    pub has_web_interface: bool,
}

#[frb(mirror(RegisterResponseDto))]
pub struct _RegisterResponseDto {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub token: String,
    pub has_web_interface: bool,
}

#[frb(mirror(DeviceType))]
pub enum _DeviceType {
    Mobile,
    Desktop,
    Web,
    Headless,
    Server,
}

#[frb(mirror(ProtocolType))]
pub enum _ProtocolType {
    Http,
    Https,
}

#[frb(mirror(FileDto))]
pub struct _FileDto {
    pub id: String,
    pub file_name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
    pub preview: Option<String>,
    pub metadata: Option<FileMetadata>,
}

#[frb(mirror(FileMetadata))]
pub struct _FileMetadata {
    pub modified: Option<String>,
    pub accessed: Option<String>,
}

#[frb(mirror(PrepareUploadRequestDto))]
pub struct _PrepareUploadRequestDto {
    pub info: RegisterDto,
    pub files: HashMap<String, FileDto>,
    pub localchat: Option<ChatTransferRef>,
}

#[frb(mirror(PrepareUploadResponseDto))]
pub struct _PrepareUploadResponseDto {
    pub session_id: String,
    pub files: HashMap<String, String>,
}
