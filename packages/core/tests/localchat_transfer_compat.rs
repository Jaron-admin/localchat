mod localchat_common;

use localchat_common::{raw_client, TestServer};
use localsend::crypto::cert::generate_self_signed;
use localsend::http::dto::PrepareUploadRequestDto;
use localsend::http::dto_v2::{PrepareUploadRequestDtoV2, PrepareUploadResponseDtoV2};
use localsend::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2};
use serde_json::{json, Value};
use std::time::Duration;

fn offer() -> Value {
    json!({"info":{"alias":"sender","version":"2.2","port":53317,"protocol":"https","fingerprint":"spoofed"},
        "files":{"wire-file":{"id":"wire-file","fileName":"fixture.txt","size":4,"fileType":"text/plain"}},
        "localchat":{"messageId":uuid::Uuid::new_v4().to_string(),"transferId":uuid::Uuid::new_v4().to_string(),
        "attachments":{"wire-file":uuid::Uuid::new_v4().to_string()}}})
}
fn url(server: &TestServer, suffix: &str) -> String {
    format!("{}://127.0.0.1:{}/api/localsend/v2/{suffix}", server.scheme, server.handle.port())
}

#[test]
fn legacy_omits_extension_and_generic_conversion_preserves_it() {
    let mut legacy = offer();
    legacy.as_object_mut().unwrap().remove("localchat");
    let dto: PrepareUploadRequestDtoV2 = serde_json::from_value(legacy).unwrap();
    assert!(dto.localchat.is_none());
    assert!(serde_json::to_value(dto).unwrap().get("localchat").is_none());
    let mut extended = offer();
    extended["info"]["token"] = json!("sender-token");
    extended["info"]["protocol"] = json!("HTTPS");
    let generic: PrepareUploadRequestDto = serde_json::from_value(extended.clone()).unwrap();
    let converted: PrepareUploadRequestDtoV2 = generic.into();
    assert_eq!(serde_json::to_value(converted).unwrap()["localchat"], extended["localchat"]);
}

#[tokio::test]
async fn invalid_file_mapping_and_missing_tls_fail_before_claiming_the_slot() {
    let mut server = TestServer::new(true, true, 16).await;
    let identity = generate_self_signed().unwrap();
    let client = raw_client(Some(&identity));
    let mut bad = offer();
    bad["localchat"]["attachments"] = json!({"unknown":uuid::Uuid::new_v4().to_string()});
    assert_eq!(client.post(url(&server, "prepare-upload")).json(&bad).send().await.unwrap().status(), 400);
    let mut mismatch = offer();
    mismatch["files"]["wire-file"]["id"] = json!("different");
    assert_eq!(client.post(url(&server, "prepare-upload")).json(&mismatch).send().await.unwrap().status(), 400);
    assert_eq!(raw_client(None).post(url(&server, "prepare-upload")).json(&offer()).send().await.unwrap().status(), 403);
    assert!(server.events.try_recv().is_err());
    let plaintext = TestServer::new(false, false, 16).await;
    assert_eq!(raw_client(None).post(url(&plaintext, "prepare-upload")).json(&offer()).send().await.unwrap().status(), 403);
}

#[tokio::test]
async fn extension_is_bound_to_tls_identity_for_prepare_upload_and_cancel() {
    let mut server = TestServer::new(true, false, 16).await;
    let a = generate_self_signed().unwrap();
    let b = generate_self_signed().unwrap();
    let client_a = raw_client(Some(&a));
    let client_b = raw_client(Some(&b));
    let request = tokio::spawn(client_a.post(url(&server, "prepare-upload")).json(&offer()).send());
    let event = tokio::time::timeout(Duration::from_secs(3), server.events.recv()).await.unwrap().unwrap();
    let ServerEventV2::PrepareUpload { cert_fingerprint, localchat, decision_tx, .. } = event else { panic!("prepare expected") };
    assert_eq!(cert_fingerprint.as_deref(), Some(a.fingerprint.as_str()));
    assert!(localchat.is_some());
    // Same IP, different certificate must not cancel an invitation still awaiting acceptance.
    assert_eq!(client_b.post(url(&server, "cancel")).send().await.unwrap().status(), 403);
    decision_tx.send(PrepareUploadDecisionV2::Accept(["wire-file".into()].into())).unwrap();
    let accepted: PrepareUploadResponseDtoV2 = request.await.unwrap().unwrap().json().await.unwrap();
    let upload = format!("upload?sessionId={}&fileId=wire-file&token={}", accepted.session_id, accepted.files["wire-file"]);
    assert_eq!(client_b.post(url(&server, &upload)).body("data").send().await.unwrap().status(), 403);
    let cancel = format!("cancel?sessionId={}", accepted.session_id);
    assert_eq!(client_b.post(url(&server, &cancel)).send().await.unwrap().status(), 403);
    assert_eq!(client_a.post(url(&server, &cancel)).send().await.unwrap().status(), 200);
    assert!(matches!(server.events.recv().await.unwrap(), ServerEventV2::SessionEnd {..}));
}
