#![cfg(feature = "http")]
mod localchat_common;
use localchat_common::*;
use localsend::crypto::cert::generate_self_signed;
use localsend::http::chat_dto::*;
use localsend::http::server::v2::ServerEventV2;
use std::time::Duration;
use tokio::sync::oneshot;

async fn next_chat(server: &mut TestServer) -> (ChatOperation, oneshot::Sender<ChatReply>) {
    match tokio::time::timeout(Duration::from_secs(2), server.events.recv())
        .await
        .unwrap()
        .unwrap()
    {
        ServerEventV2::ChatRequest {
            operation,
            response_tx,
            ..
        } => (operation, response_tx),
        event => panic!("unexpected event {event:?}"),
    }
}

#[tokio::test]
async fn capabilities_and_utf8_validation() {
    let mut server = TestServer::new(true, false, 32).await;
    let sender = generate_self_signed().unwrap();
    let client = raw_client(Some(&sender));
    let capabilities: ChatCapabilities = client
        .get(server.url("capabilities"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(capabilities.version, 1);
    assert_eq!(capabilities.max_text_bytes, 32768);
    assert_eq!(capabilities.features, ["text", "file-ref"]);
    let mut cases = vec![(message(&"中".repeat(10923)), 413), (message(" \n\t"), 400)];
    let mut invalid = message("hello");
    invalid["messageId"] = "not-a-uuid".into();
    cases.push((invalid, 400));
    let mut version = message("hello");
    version["version"] = 2.into();
    cases.push((version, 400));
    for (body, status) in cases {
        assert_eq!(
            client
                .post(server.url("messages"))
                .json(&body)
                .send()
                .await
                .unwrap()
                .status()
                .as_u16(),
            status
        );
    }
    assert!(server.events.try_recv().is_err());
    let text = format!(" {} ", "中".repeat(10921)); // preserve surrounding whitespace
    let text = format!("{text}aaa");
    assert_eq!(text.len(), 32768);
    let body = message(&text);
    let pending = tokio::spawn(client.post(server.url("messages")).json(&body).send());
    let (operation, tx) = next_chat(&mut server).await;
    let ChatOperation::Deliver(delivered) = operation else {
        panic!()
    };
    assert_eq!(delivered.text, text);
    tx.send(ChatReply::Stored(ChatAck {
        message_id: delivered.message_id,
        duplicate: false,
    }))
    .unwrap();
    assert_eq!(pending.await.unwrap().unwrap().status().as_u16(), 201);
}

#[tokio::test]
async fn replies_and_invitation_statuses_are_bound_to_the_operation() {
    let mut server = TestServer::new(true, false, 32).await;
    let client = raw_client(Some(&generate_self_signed().unwrap()));
    let id = uuid::Uuid::new_v4().to_string();
    for (post, status, expected) in [
        (true, ChatInvitationStatus::Pending, 202),
        (false, ChatInvitationStatus::Pending, 200),
        (true, ChatInvitationStatus::Accepted, 200),
        (false, ChatInvitationStatus::Rejected, 200),
    ] {
        let request = if post {
            client
                .post(server.url("invitations"))
                .json(&serde_json::json!({"version":1,"invitationId":id}))
        } else {
            client.get(server.url(&format!("invitations/{id}")))
        };
        let pending = tokio::spawn(request.send());
        let (_, tx) = next_chat(&mut server).await;
        tx.send(ChatReply::Invitation(ChatInviteStatus {
            invitation_id: id.clone(),
            status,
        }))
        .unwrap();
        assert_eq!(pending.await.unwrap().unwrap().status().as_u16(), expected);
    }
    for (reply, expected) in [
        (ChatReply::Rejected(ChatErrorCode::Denied), 403),
        (ChatReply::Rejected(ChatErrorCode::Conflict), 409),
        (ChatReply::Rejected(ChatErrorCode::Unavailable), 503),
        (ChatReply::Rejected(ChatErrorCode::Overloaded), 429),
        (
            ChatReply::Stored(ChatAck {
                message_id: uuid::Uuid::new_v4().to_string(),
                duplicate: false,
            }),
            503,
        ),
    ] {
        let pending = tokio::spawn(
            client
                .post(server.url("messages"))
                .json(&message("test"))
                .send(),
        );
        let (_, tx) = next_chat(&mut server).await;
        tx.send(reply).unwrap();
        assert_eq!(pending.await.unwrap().unwrap().status().as_u16(), expected);
    }
    let pending = tokio::spawn(
        client
            .post(server.url("messages"))
            .json(&message("duplicate"))
            .send(),
    );
    let (ChatOperation::Deliver(dto), tx) = next_chat(&mut server).await else {
        panic!()
    };
    tx.send(ChatReply::Stored(ChatAck {
        message_id: dto.message_id,
        duplicate: true,
    }))
    .unwrap();
    assert_eq!(pending.await.unwrap().unwrap().status().as_u16(), 200);
}

#[tokio::test]
async fn chunked_body_and_event_queue_are_bounded() {
    let mut server = TestServer::new(true, false, 1).await;
    let client = raw_client(Some(&generate_self_signed().unwrap()));
    let chunks =
        futures_util::stream::iter((0..65).map(|_| Ok::<_, std::io::Error>(vec![b' '; 4096])));
    let response = client
        .post(server.url("messages"))
        .body(localsend::reqwest::Body::wrap_stream(chunks))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status().as_u16(), 413);
    let first = tokio::spawn(
        client
            .post(server.url("messages"))
            .json(&message("held"))
            .send(),
    );
    // Wait until a request occupies the queue without draining it.
    tokio::time::timeout(Duration::from_secs(2), async {
        while server.events.is_empty() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(
        client
            .post(server.url("messages"))
            .json(&message("overflow"))
            .send()
            .await
            .unwrap()
            .status()
            .as_u16(),
        429
    );
    let (_, tx) = next_chat(&mut server).await;
    drop(tx);
    assert_eq!(first.await.unwrap().unwrap().status().as_u16(), 503);
    server.events.close();
    assert_eq!(
        client
            .post(server.url("messages"))
            .json(&message("unavailable"))
            .send()
            .await
            .unwrap()
            .status()
            .as_u16(),
        503
    );
}

#[tokio::test]
async fn certificate_limit_timeout_and_disconnect_release_slots() {
    let mut server = TestServer::new(true, false, 32).await;
    let sender = generate_self_signed().unwrap();
    let mut held = Vec::new();
    for _ in 0..8 {
        let client = raw_client(Some(&sender)); // separate connections, same identity
        let task = tokio::spawn(
            client
                .post(server.url("messages"))
                .json(&message("held"))
                .send(),
        );
        let (_, tx) = next_chat(&mut server).await;
        held.push((task, tx));
    }
    let client = raw_client(Some(&sender));
    assert_eq!(
        client
            .post(server.url("messages"))
            .json(&message("over"))
            .send()
            .await
            .unwrap()
            .status()
            .as_u16(),
        429
    );
    let (task, mut tx) = held.remove(0);
    task.abort();
    let _ = task.await;
    tokio::time::timeout(Duration::from_secs(2), tx.closed())
        .await
        .expect("TLS disconnect must release responder");
    let retry = tokio::spawn(
        client
            .post(server.url("messages"))
            .json(&message("after disconnect"))
            .send(),
    );
    let (_, tx) = next_chat(&mut server).await;
    drop(tx);
    assert_eq!(retry.await.unwrap().unwrap().status().as_u16(), 503);
    for (task, mut tx) in held {
        assert_eq!(task.await.unwrap().unwrap().status().as_u16(), 504);
        tokio::time::timeout(Duration::from_secs(1), tx.closed())
            .await
            .unwrap();
    }
    let retry = tokio::spawn(
        client
            .post(server.url("messages"))
            .json(&message("after timeout"))
            .send(),
    );
    let (_, tx) = next_chat(&mut server).await;
    drop(tx);
    assert_eq!(retry.await.unwrap().unwrap().status().as_u16(), 503);
}

#[tokio::test]
async fn global_limit_is_shared_between_identities() {
    let mut server = TestServer::new(true, false, 128).await;
    let mut held = Vec::new();
    let clients: Vec<_> = (0..9)
        .map(|_| raw_client(Some(&generate_self_signed().unwrap())))
        .collect();
    for client in &clients[..8] {
        for _ in 0..8 {
            let task = tokio::spawn(
                client
                    .post(server.url("messages"))
                    .json(&message("held"))
                    .send(),
            );
            let (_, tx) = next_chat(&mut server).await;
            held.push((task, tx));
        }
    }
    let client = &clients[8];
    assert_eq!(
        client
            .post(server.url("messages"))
            .json(&message("global overflow"))
            .send()
            .await
            .unwrap()
            .status()
            .as_u16(),
        429
    );
    for (task, tx) in held {
        drop(tx);
        assert_eq!(task.await.unwrap().unwrap().status().as_u16(), 503);
    }
}

#[tokio::test]
async fn chat_is_independent_of_pending_file_acceptance() {
    let mut server = TestServer::new(true, false, 32).await;
    let sender = generate_self_signed().unwrap();
    let client = raw_client(Some(&sender));
    let upload = tokio::spawn(client.post(format!("https://127.0.0.1:{}/api/localsend/v2/prepare-upload",server.handle.port()))
        .json(&serde_json::json!({"info":{"alias":"sender","version":"2.2","fingerprint":sender.fingerprint,"port":53317,"protocol":"https"},
            "files":{"file":{"id":"file","fileName":"test.bin","size":10,"fileType":"application/octet-stream"}}})).send());
    let ServerEventV2::PrepareUpload { decision_tx, .. } = server.events.recv().await.unwrap()
    else {
        panic!()
    };
    let request = tokio::spawn(
        client
            .post(server.url("messages"))
            .json(&message("while transferring"))
            .send(),
    );
    let (ChatOperation::Deliver(dto), tx) = next_chat(&mut server).await else {
        panic!()
    };
    tx.send(ChatReply::Stored(ChatAck {
        message_id: dto.message_id,
        duplicate: false,
    }))
    .unwrap();
    assert_eq!(request.await.unwrap().unwrap().status().as_u16(), 201);
    decision_tx
        .send(localsend::http::server::v2::PrepareUploadDecisionV2::Decline)
        .unwrap();
    assert_eq!(upload.await.unwrap().unwrap().status().as_u16(), 403);
}
