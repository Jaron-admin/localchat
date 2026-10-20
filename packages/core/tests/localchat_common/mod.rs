#![allow(dead_code)]

use localsend::crypto::cert::{generate_self_signed, SelfSignedCert};
use localsend::http::server::v2::ServerEventV2;
use localsend::http::server::web::{WebConfig, WebI18n, WebPages};
use localsend::http::server::{start_with_port, ServerConfigV2, ServerHandle, TlsConfig};
use localsend::http::state::ClientInfo;
use tokio::sync::{mpsc, oneshot};

pub struct TestServer {
    pub identity: SelfSignedCert,
    pub handle: ServerHandle,
    pub events: mpsc::Receiver<ServerEventV2>,
    pub scheme: &'static str,
    _stop: oneshot::Sender<()>,
}

impl TestServer {
    pub async fn new(tls: bool, web: bool, queue: usize) -> Self {
        let identity = generate_self_signed().unwrap();
        let (tx, events) = mpsc::channel(queue);
        let (stop, stop_rx) = oneshot::channel();
        let handle = start_with_port(
            0,
            tls.then(|| TlsConfig {
                cert: identity.certificate_pem.clone(),
                private_key: identity.private_key_pem.clone(),
            }),
            ClientInfo {
                alias: "Chat test".into(),
                version: "2.2".into(),
                device_model: None,
                device_type: None,
                token: identity.fingerprint.clone(),
            },
            None,
            Some(ServerConfigV2 {
                pin: None,
                verify_checksums: true,
                event_tx: tx,
            }),
            web.then(|| WebConfig {
                send: None,
                upload: true,
                i18n: WebI18n::default(),
                pages: WebPages::default(),
            }),
            stop_rx,
        )
        .await
        .unwrap();
        Self {
            identity,
            handle,
            events,
            scheme: if tls { "https" } else { "http" },
            _stop: stop,
        }
    }

    pub fn url(&self, path: &str) -> String {
        format!(
            "{}://127.0.0.1:{}/api/localchat/v1/{path}",
            self.scheme,
            self.handle.port()
        )
    }
}

// Unpinned transport only for adversarial HTTP tests; production uses LsHttpClientV2.
pub fn raw_client(identity: Option<&SelfSignedCert>) -> localsend::reqwest::Client {
    let mut builder = localsend::reqwest::Client::builder()
        .use_rustls_tls()
        .danger_accept_invalid_certs(true)
        .no_proxy()
        .timeout(std::time::Duration::from_secs(10));
    if let Some(identity) = identity {
        builder = builder.identity(
            localsend::reqwest::Identity::from_pem(
                format!("{}\n{}", identity.certificate_pem, identity.private_key_pem).as_bytes(),
            )
            .unwrap(),
        );
    }
    builder.build().unwrap()
}

pub fn message(text: &str) -> serde_json::Value {
    serde_json::json!({"version":1, "messageId":uuid::Uuid::new_v4().to_string(), "sentAtMs":1234,"text":text})
}
