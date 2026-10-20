#![cfg(feature = "http")]

use localsend::http::client::LsHttpClientV2;
use localsend::http::dto_v2::RegisterDtoV2;
use localsend::http::server::v2::ServerEventV2;
use localsend::http::server::{ServerConfigV2, start_with_port, start_with_port_fallback};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::ProtocolType;
use std::io::ErrorKind;
use std::time::Duration;
use tokio::net::TcpListener;
use tokio::sync::{mpsc, oneshot};

fn info() -> ClientInfo {
    ClientInfo {
        alias: "LocalChat coexistence".into(),
        version: "2.2".into(),
        device_model: None,
        device_type: None,
        token: "test-server".into(),
    }
}

#[tokio::test]
async fn occupied_preferred_port_falls_back_and_retains_events_and_shutdown() {
    let occupied = TcpListener::bind("0.0.0.0:0").await.unwrap();
    let preferred = occupied.local_addr().unwrap().port();
    let (event_tx, mut events) = mpsc::channel(16);
    let (stop_tx, stop_rx) = oneshot::channel();
    let server = start_with_port_fallback(
        preferred,
        None,
        info(),
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
        }),
        None,
        stop_rx,
    )
    .await
    .unwrap();
    let actual = server.port();
    assert_ne!(actual, 0);
    assert_ne!(actual, preferred);

    let client = LsHttpClientV2::try_new_without_cert().unwrap();
    let registered = client
        .register(
            ProtocolType::Http,
            "127.0.0.1",
            actual,
            RegisterDtoV2 {
                alias: "test-peer".into(),
                version: "2.2".into(),
                device_model: None,
                device_type: None,
                fingerprint: "test-peer-id".into(),
                port: 12345,
                protocol: ProtocolType::Http,
                download: false,
            },
        )
        .await
        .unwrap();
    assert_eq!(registered.body.alias, "LocalChat coexistence");
    assert!(
        matches!(tokio::time::timeout(Duration::from_secs(3), events.recv()).await.unwrap(),
        Some(ServerEventV2::Register { info, .. }) if info.fingerprint == "test-peer-id")
    );

    stop_tx.send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(3), server.wait_stopped())
        .await
        .unwrap();
    let _rebound = TcpListener::bind((std::net::Ipv4Addr::UNSPECIFIED, actual))
        .await
        .unwrap();
}

#[tokio::test]
async fn strict_start_still_reports_address_in_use() {
    let occupied = TcpListener::bind("0.0.0.0:0").await.unwrap();
    let (_stop_tx, stop_rx) = oneshot::channel();
    let error = start_with_port(
        occupied.local_addr().unwrap().port(),
        None,
        info(),
        None,
        None,
        None,
        stop_rx,
    )
    .await
    .err()
    .expect("strict bind must fail");
    assert_eq!(
        error.downcast_ref::<std::io::Error>().unwrap().kind(),
        ErrorKind::AddrInUse
    );
}

#[tokio::test]
async fn zero_port_is_allocated_and_keeps_the_original_stop_channel() {
    let (stop_tx, stop_rx) = oneshot::channel();
    let server = start_with_port_fallback(0, None, info(), None, None, None, stop_rx)
        .await
        .unwrap();
    assert_ne!(server.port(), 0);
    stop_tx.send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(3), server.wait_stopped())
        .await
        .unwrap();
}

/// Explicit network acceptance test: unlike the upstream multicast suite this
/// never silently succeeds when multicast is unavailable. Run with --ignored.
#[tokio::test]
#[ignore = "requires a LAN interface that carries multicast"]
async fn multicast_stays_on_53317_and_advertises_fallback_http_port() {
    use localsend::multicast::{self, MulticastConfig, MulticastDevice, MulticastEvent};
    use std::net::Ipv4Addr;

    let _occupied = match TcpListener::bind((Ipv4Addr::UNSPECIFIED, 53317)).await {
        Ok(listener) => Some(listener),
        Err(error) if error.kind() == ErrorKind::AddrInUse => None,
        Err(error) => panic!("cannot reserve preferred port: {error}"),
    };
    let (stop_http, stop_rx) = oneshot::channel();
    let server = start_with_port_fallback(53317, None, info(), None, None, None, stop_rx)
        .await
        .unwrap();
    assert_ne!(server.port(), 53317);
    let fingerprint = uuid::Uuid::new_v4().to_string();
    let (events_tx, mut events) = mpsc::channel(32);
    let (sender_tx, _sender_rx) = mpsc::channel(32);
    let config = |identity: String, port, event_tx| MulticastConfig {
        group: Ipv4Addr::new(224, 0, 0, 170),
        group_v6: None,
        port: 53317,
        interface_filter: Default::default(),
        device: MulticastDevice {
            alias: "LocalChat coexistence probe".into(),
            version: "2.2".into(),
            device_model: None,
            device_type: None,
            fingerprint: identity,
            port,
            protocol: ProtocolType::Http,
            download: false,
        },
        event_tx,
    };
    let (stop_receiver, receiver_stop) = oneshot::channel();
    let receiver = multicast::start(
        config(uuid::Uuid::new_v4().to_string(), 42424, events_tx),
        receiver_stop,
    )
    .await
    .unwrap();
    let (stop_sender, sender_stop) = oneshot::channel();
    let sender = multicast::start(
        config(fingerprint.clone(), server.port(), sender_tx),
        sender_stop,
    )
    .await
    .unwrap();
    sender.announce().await;
    let actual = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let MulticastEvent::Discovered { message, .. } =
                events.recv().await.expect("multicast stopped")
            else {
                panic!("multicast sockets failed");
            };
            if message.fingerprint == fingerprint {
                break message.port;
            }
        }
    })
    .await
    .expect("no datagram received on UDP 53317");
    assert_eq!(actual, server.port());
    stop_sender.send(()).unwrap();
    stop_receiver.send(()).unwrap();
    stop_http.send(()).unwrap();
    sender.wait_stopped().await;
    receiver.wait_stopped().await;
    server.wait_stopped().await;
}
