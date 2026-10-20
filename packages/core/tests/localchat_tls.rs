#![cfg(feature = "http")]
mod localchat_common;
use localchat_common::*;
use localsend::crypto::cert::generate_self_signed;
use localsend::http::chat_dto::*;
use localsend::http::client::{ClientError, LsHttpClientV2};
use localsend::http::server::v2::ServerEventV2;

#[tokio::test]
async fn plaintext_and_browser_without_certificate_cannot_chat() {
    for (tls, web) in [(false, false), (true, true)] {
        let mut server = TestServer::new(tls, web, 16).await;
        let client = raw_client(None);
        for endpoint in ["messages", "invitations"] {
            assert_eq!(
                client
                    .post(server.url(endpoint))
                    .json(&message("private"))
                    .send()
                    .await
                    .unwrap()
                    .status()
                    .as_u16(),
                403
            );
        }
        assert!(server.events.try_recv().is_err());
    }
}

#[tokio::test]
async fn pinned_client_checks_identity_before_transmitting_chat() {
    let mut server = TestServer::new(true, false, 16).await;
    let sender = generate_self_signed().unwrap();
    let payload = ChatMessageDto {
        version: 1,
        message_id: uuid::Uuid::new_v4().to_string(),
        sent_at_ms: 1,
        text: "private".into(),
    };
    for fingerprint in [None, Some(generate_self_signed().unwrap().fingerprint)] {
        let client = LsHttpClientV2::try_new(
            &sender.private_key_pem,
            &sender.certificate_pem,
            fingerprint.clone(),
            None,
        )
        .unwrap();
        let result = client
            .chat_deliver("127.0.0.1", server.handle.port(), payload.clone())
            .await;
        if fingerprint.is_none() {
            assert!(matches!(result, Err(ClientError::Other(_))));
        } else {
            assert!(matches!(result, Err(ClientError::Reqwest(_))));
        }
        assert!(
            server.events.try_recv().is_err(),
            "unpinned or wrong identity must receive no body"
        );
    }
    let client = LsHttpClientV2::try_new(
        &sender.private_key_pem,
        &sender.certificate_pem,
        Some(server.identity.fingerprint.clone()),
        None,
    )
    .unwrap();
    let caps = client
        .chat_capabilities("127.0.0.1", server.handle.port())
        .await
        .unwrap();
    assert_eq!(caps.version, 1);
    let port = server.handle.port();
    let sent = payload.clone();
    let task = tokio::spawn(async move { client.chat_deliver("127.0.0.1", port, sent).await });
    let ServerEventV2::ChatRequest {
        peer_fingerprint,
        operation,
        response_tx,
        ..
    } = server.events.recv().await.unwrap()
    else {
        panic!()
    };
    assert_eq!(peer_fingerprint, sender.fingerprint);
    let ChatOperation::Deliver(dto) = operation else {
        panic!()
    };
    assert_eq!(dto.text, payload.text);
    response_tx
        .send(ChatReply::Stored(ChatAck {
            message_id: dto.message_id,
            duplicate: false,
        }))
        .unwrap();
    assert_eq!(task.await.unwrap().unwrap().message_id, payload.message_id);
}
