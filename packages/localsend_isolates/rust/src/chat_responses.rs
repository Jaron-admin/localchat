use localsend::http::chat_dto::{ChatErrorCode, ChatReply};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::oneshot;

#[derive(Default)]
pub(crate) struct PendingChatRequests {
    entries: Arc<Mutex<HashMap<String, oneshot::Sender<ChatReply>>>>,
}

impl PendingChatRequests {
    pub fn register(&self, id: String, mut response: oneshot::Sender<ChatReply>) -> bool {
        if response.is_closed() {
            return false;
        }
        let (tx, rx) = oneshot::channel();
        {
            let mut map = self.entries.lock().unwrap();
            if map.len() >= 64 || map.contains_key(&id) {
                let _ = response.send(ChatReply::Rejected(ChatErrorCode::Overloaded));
                return false;
            }
            map.insert(id.clone(), tx);
        }
        let entries = self.entries.clone();
        tokio::spawn(async move {
            tokio::select! {
                biased;
                _ = response.closed() => {},
                reply = rx => { if let Ok(reply) = reply {let _ = response.send(reply);} },
            }
            entries.lock().unwrap().remove(&id);
        });
        true
    }
    pub fn respond(&self, id: &str, reply: ChatReply) -> anyhow::Result<()> {
        let tx = self
            .entries
            .lock()
            .unwrap()
            .remove(id)
            .ok_or_else(|| anyhow::anyhow!("Chat request is no longer pending"))?;
        tx.send(reply)
            .map_err(|_| anyhow::anyhow!("Chat request is no longer pending"))
    }
    pub fn clear(&self) {
        self.entries.lock().unwrap().clear();
    }
    #[cfg(test)]
    fn len(&self) -> usize {
        self.entries.lock().unwrap().len()
    }
}

#[cfg(test)]
mod tests {
    use super::PendingChatRequests;
    use localsend::http::chat_dto::{ChatErrorCode, ChatReply};
    use std::time::Duration;
    use tokio::sync::oneshot;

    #[tokio::test]
    async fn closed_or_unknown_request_never_answers_another_request() {
        let map = PendingChatRequests::default();
        let (tx, rx) = oneshot::channel();
        assert!(map.register("old".into(), tx));
        drop(rx);
        tokio::time::timeout(Duration::from_secs(1), async {
            while map.len() != 0 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        let (tx, mut rx) = oneshot::channel();
        assert!(map.register("new".into(), tx));
        assert!(
            map.respond("old", ChatReply::Rejected(ChatErrorCode::Denied))
                .is_err()
        );
        assert!(rx.try_recv().is_err());
        map.respond("new", ChatReply::Rejected(ChatErrorCode::Denied))
            .unwrap();
        assert!(matches!(
            rx.await.unwrap(),
            ChatReply::Rejected(ChatErrorCode::Denied)
        ));
    }

    #[tokio::test]
    async fn responders_are_bounded_and_shutdown_releases_every_request() {
        let map = PendingChatRequests::default();
        let mut held = Vec::new();
        for i in 0..64 {
            let (tx, rx) = oneshot::channel();
            assert!(map.register(i.to_string(), tx));
            held.push(rx);
        }
        let (tx, rx) = oneshot::channel();
        assert!(!map.register("overflow".into(), tx));
        assert!(matches!(
            rx.await.unwrap(),
            ChatReply::Rejected(ChatErrorCode::Overloaded)
        ));
        map.clear();
        for rx in held {
            assert!(rx.await.is_err());
        }
        assert_eq!(map.len(), 0);
    }
}
