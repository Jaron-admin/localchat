const chatSchemaVersion = 2;
const chatSchema = '''
CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS peers (
 fingerprint TEXT PRIMARY KEY, alias TEXT NOT NULL, platform TEXT, host TEXT, port INTEGER, last_seen INTEGER,
 is_own_device INTEGER NOT NULL DEFAULT 0, local_permission TEXT NOT NULL DEFAULT 'unknown', remote_permission TEXT NOT NULL DEFAULT 'unknown'
);
CREATE TABLE IF NOT EXISTS conversations (
 id TEXT PRIMARY KEY, peer_fingerprint TEXT NOT NULL UNIQUE REFERENCES peers(fingerprint),
 last_activity INTEGER NOT NULL DEFAULT 0, last_sequence INTEGER NOT NULL DEFAULT 0,
 unread_count INTEGER NOT NULL DEFAULT 0, read_sequence INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS invitations (
 invitation_id TEXT NOT NULL, peer_fingerprint TEXT NOT NULL REFERENCES peers(fingerprint),
 direction TEXT NOT NULL, status TEXT NOT NULL, created_at INTEGER NOT NULL,
 PRIMARY KEY(peer_fingerprint, invitation_id)
);
CREATE TABLE IF NOT EXISTS messages (
 local_sequence INTEGER PRIMARY KEY AUTOINCREMENT,
 sender_fingerprint TEXT NOT NULL, message_id TEXT NOT NULL,
 conversation_id TEXT NOT NULL REFERENCES conversations(id), peer_fingerprint TEXT NOT NULL REFERENCES peers(fingerprint),
 kind TEXT NOT NULL, direction TEXT NOT NULL, text TEXT, sent_at_ms INTEGER NOT NULL, received_at_ms INTEGER,
 delivery_state TEXT NOT NULL, attempt_count INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER, last_error TEXT,
 UNIQUE(sender_fingerprint, message_id)
);
CREATE INDEX IF NOT EXISTS history ON messages(conversation_id, local_sequence DESC);
CREATE INDEX IF NOT EXISTS outbox ON messages(direction, delivery_state, next_attempt_at);
CREATE TABLE IF NOT EXISTS attachments (
 attachment_id TEXT NOT NULL, sender_fingerprint TEXT NOT NULL, message_id TEXT NOT NULL,
 transfer_id TEXT NOT NULL, session_id TEXT, file_id TEXT NOT NULL, name TEXT NOT NULL, size INTEGER NOT NULL,
 local_path TEXT, state TEXT NOT NULL, remote_session_id TEXT,
 PRIMARY KEY(sender_fingerprint, message_id, attachment_id),
 FOREIGN KEY(sender_fingerprint, message_id) REFERENCES messages(sender_fingerprint, message_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS attachment_session_file ON attachments(session_id,file_id);
CREATE INDEX IF NOT EXISTS attachment_transfer ON attachments(sender_fingerprint,transfer_id);
''';
