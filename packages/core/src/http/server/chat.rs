use super::common::error::AppError;
use super::common::response::{BoxedBody, JsonResponse};
use super::v2::ServerEventV2;
use super::{AppState, RequestClientInfo};
use crate::http::chat_dto::*;
use http_body_util::{BodyExt, LengthLimitError, Limited};
use hyper::{body::Incoming, Method, Request, Response, StatusCode};
use serde::de::DeserializeOwned;
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;
use tokio::sync::{mpsc::error::TrySendError, oneshot};

const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Default)]
pub(crate) struct ChatState {
    counts: Mutex<Counts>,
}
#[derive(Default)]
struct Counts {
    total: usize,
    peers: HashMap<String, usize>,
}
struct Permit<'a> {
    state: &'a ChatState,
    fingerprint: String,
}

impl ChatState {
    fn acquire(&self, fingerprint: String) -> Result<Permit<'_>, AppError> {
        let mut counts = self
            .counts
            .lock()
            .map_err(|_| error(StatusCode::SERVICE_UNAVAILABLE, "unavailable"))?;
        if counts.total >= 64 || counts.peers.get(&fingerprint).copied().unwrap_or(0) >= 8 {
            return Err(error(StatusCode::TOO_MANY_REQUESTS, "overloaded"));
        }
        counts.total += 1;
        *counts.peers.entry(fingerprint.clone()).or_default() += 1;
        Ok(Permit {
            state: self,
            fingerprint,
        })
    }
}
impl Drop for Permit<'_> {
    fn drop(&mut self) {
        if let Ok(mut counts) = self.state.counts.lock() {
            counts.total -= 1;
            if let Some(count) = counts.peers.get_mut(&self.fingerprint) {
                *count -= 1;
                if *count == 0 {
                    counts.peers.remove(&self.fingerprint);
                }
            }
        }
    }
}

fn error(status: StatusCode, code: &str) -> AppError {
    AppError::Message(status, code.into())
}
fn validate(version: u32, id: &str) -> Result<(), AppError> {
    if version != CHAT_VERSION || !is_chat_id(id) {
        return Err(error(StatusCode::BAD_REQUEST, "invalid_version_or_id"));
    }
    Ok(())
}
async fn body<T: DeserializeOwned>(req: Request<Incoming>) -> Result<T, AppError> {
    let bytes = tokio::time::timeout(
        REQUEST_TIMEOUT,
        Limited::new(req.into_body(), MAX_CHAT_JSON_BYTES).collect(),
    )
    .await
    .map_err(|_| error(StatusCode::GATEWAY_TIMEOUT, "body_timeout"))?
    .map_err(|err| {
        if err.is::<LengthLimitError>() {
            error(StatusCode::PAYLOAD_TOO_LARGE, "json_too_large")
        } else {
            error(StatusCode::BAD_REQUEST, "invalid_body")
        }
    })?
    .to_bytes();
    serde_json::from_slice(&bytes).map_err(|_| error(StatusCode::BAD_REQUEST, "invalid_json"))
}

pub(crate) async fn handle(
    req: Request<Incoming>,
    state: AppState,
    client: RequestClientInfo,
) -> Result<Response<BoxedBody>, AppError> {
    let v2 = state
        .v2
        .as_ref()
        .ok_or(AppError::Status(StatusCode::NOT_FOUND))?;
    let fingerprint = client
        .cert_fingerprint()
        .ok_or_else(|| error(StatusCode::FORBIDDEN, "certificate_required"))?;
    let _permit = v2.chat.acquire(fingerprint.clone())?;
    let operation = match (req.method(), req.uri().path()) {
        (&Method::GET, "/api/localchat/v1/capabilities") => {
            return Ok(JsonResponse {
                status: StatusCode::OK,
                body: ChatCapabilities {
                    version: CHAT_VERSION,
                    features: vec!["text".into(), "file-ref".into()],
                    max_text_bytes: MAX_TEXT_BYTES as u32,
                },
            }
            .into_response())
        }
        (&Method::POST, "/api/localchat/v1/invitations") => {
            let dto: ChatInvite = body(req).await?;
            validate(dto.version, &dto.invitation_id)?;
            ChatOperation::Invite(dto)
        }
        (&Method::GET, path) if path.starts_with("/api/localchat/v1/invitations/") => {
            let id = path.trim_start_matches("/api/localchat/v1/invitations/");
            validate(CHAT_VERSION, id)?;
            ChatOperation::InviteStatus(id.into())
        }
        (&Method::POST, "/api/localchat/v1/messages") => {
            let dto: ChatMessageDto = body(req).await?;
            validate(dto.version, &dto.message_id)?;
            if dto.text.len() > MAX_TEXT_BYTES {
                return Err(error(StatusCode::PAYLOAD_TOO_LARGE, "text_too_large"));
            }
            if dto.text.trim().is_empty() {
                return Err(error(StatusCode::BAD_REQUEST, "empty_text"));
            }
            ChatOperation::Deliver(dto)
        }
        _ => return Err(AppError::Status(StatusCode::NOT_FOUND)),
    };
    let (response_tx, response_rx) = oneshot::channel();
    // Keep only the operation and identifier needed to validate the reply, not a second text copy.
    let (kind, id) = match &operation {
        ChatOperation::Invite(dto) => (0, dto.invitation_id.clone()),
        ChatOperation::InviteStatus(id) => (1, id.clone()),
        ChatOperation::Deliver(dto) => (2, dto.message_id.clone()),
    };
    v2.event_tx
        .try_send(ServerEventV2::ChatRequest {
            request_id: uuid::Uuid::new_v4().to_string(),
            ip: client.ip,
            peer_fingerprint: fingerprint,
            operation,
            response_tx,
        })
        .map_err(|err| match err {
            TrySendError::Full(_) => error(StatusCode::TOO_MANY_REQUESTS, "overloaded"),
            TrySendError::Closed(_) => error(StatusCode::SERVICE_UNAVAILABLE, "unavailable"),
        })?;
    let reply = tokio::time::timeout(REQUEST_TIMEOUT, response_rx)
        .await
        .map_err(|_| error(StatusCode::GATEWAY_TIMEOUT, "response_timeout"))?
        .map_err(|_| error(StatusCode::SERVICE_UNAVAILABLE, "unavailable"))?;
    match reply {
        ChatReply::Invitation(dto) if kind < 2 && dto.invitation_id == id => Ok(JsonResponse {
            status: if kind == 0 && dto.status == ChatInvitationStatus::Pending {
                StatusCode::ACCEPTED
            } else {
                StatusCode::OK
            },
            body: dto,
        }
        .into_response()),
        ChatReply::Stored(dto) if kind == 2 && dto.message_id == id => Ok(JsonResponse {
            status: if dto.duplicate {
                StatusCode::OK
            } else {
                StatusCode::CREATED
            },
            body: dto,
        }
        .into_response()),
        ChatReply::Rejected(code) => Err(match code {
            ChatErrorCode::Denied => error(StatusCode::FORBIDDEN, "denied"),
            ChatErrorCode::Conflict => error(StatusCode::CONFLICT, "conflict"),
            ChatErrorCode::Unavailable => error(StatusCode::SERVICE_UNAVAILABLE, "unavailable"),
            ChatErrorCode::Overloaded => error(StatusCode::TOO_MANY_REQUESTS, "overloaded"),
        }),
        _ => Err(error(
            StatusCode::SERVICE_UNAVAILABLE,
            "invalid_application_reply",
        )),
    }
}
