import 'dart:convert';
import 'dart:isolate';

import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_conversation.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/model/chat/chat_transfer_context.dart';
import 'package:localsend_app/repository/chat/chat_schema.dart';
import 'package:sqlite3/sqlite3.dart';

/// The only database connection used by the application. No async callbacks
/// inside a transaction: permission checks and their effects are serialized.
void chatDatabaseWorker((String, String, SendPort) configuration) {
  final (path, fingerprint, replies) = configuration;
  Database? database;
  try {
    database = sqlite3.open(path);
    database.execute('PRAGMA busy_timeout=1000');
    database.execute('PRAGMA foreign_keys=ON');
    database.execute('PRAGMA journal_mode=WAL');
    database.execute('PRAGMA synchronous=FULL');
    final worker = _Worker(database);
    worker.initialize(fingerprint);
    final requests = ReceivePort();
    replies.send(requests.sendPort);
    requests.listen((dynamic request) {
      final (int id, String method, List<Object?> args) = request as (int, String, List<Object?>);
      if (method == 'close') {
        database!.close();
        requests.close();
        replies.send((id, null, null, <String>{}));
        return;
      }
      try {
        final value = worker.transaction(() => worker.execute(method, args));
        replies.send((id, value, null, Set<String>.of(worker.changed)));
      } catch (error) {
        // SQL errors can contain bound values. Never send/log the original text.
        replies.send((id, null, error is ChatStorageException ? error : const ChatStorageException('unavailable'), <String>{}));
      }
    });
  } catch (_) {
    database?.close();
    replies.send(const ChatStorageException('unavailable'));
  }
}

class _Worker {
  final Database db;
  final changed = <String>{};
  String owner = '';
  _Worker(this.db);

  T transaction<T>(T Function() action) {
    changed.clear();
    final previousOwner = owner;
    db.execute('BEGIN IMMEDIATE');
    try {
      final value = action();
      db.execute('COMMIT');
      return value;
    } catch (_) {
      db.execute('ROLLBACK');
      owner = previousOwner;
      changed.clear();
      rethrow;
    }
  }

  void initialize(String fingerprint) {
    final version = db.select('PRAGMA user_version').single.values.single as int;
    if (version > chatSchemaVersion) throw const ChatStorageException('unsupported_schema');
    transaction(() {
      db.execute(chatSchema);
      if (version == 1) db.execute('ALTER TABLE attachments ADD COLUMN remote_session_id TEXT');
      db.execute('PRAGMA user_version=$chatSchemaVersion');
      changeIdentity(fingerprint);
      recover();
    });
  }

  void validateFingerprint(String value) {
    if (!RegExp(r'^[0-9A-F]{64}$').hasMatch(value)) throw const ChatStorageException('invalid_identity');
  }

  void validateId(String value) {
    if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(value)) {
      throw const ChatStorageException('invalid_id');
    }
  }

  void validateText(String text) {
    if (text.trim().isEmpty) throw const ChatStorageException('empty_text');
    if (utf8.encode(text).length > 32768) throw const ChatStorageException('text_too_large');
  }

  ChatPeer ensurePeer(String fingerprint) {
    validateFingerprint(fingerprint);
    db.execute('INSERT OR IGNORE INTO peers(fingerprint,alias) VALUES(?,?)', [fingerprint, fingerprint.substring(0, 12)]);
    return getPeer(fingerprint)!;
  }

  ChatPeer? getPeer(String fingerprint) {
    final rows = db.select('SELECT * FROM peers WHERE fingerprint=?', [fingerprint]);
    if (rows.isEmpty) return null;
    final r = rows.single;
    return ChatPeer(
      fingerprint: r['fingerprint'] as String,
      alias: r['alias'] as String,
      platform: r['platform'] as String?,
      host: r['host'] as String?,
      port: r['port'] as int?,
      lastSeen: r['last_seen'] as int?,
      isOwnDevice: r['is_own_device'] == 1,
      localPermission: ChatPermission.values.byName(r['local_permission'] as String),
      remotePermission: ChatPermission.values.byName(r['remote_permission'] as String),
    );
  }

  String conversation(String fingerprint) {
    ensurePeer(fingerprint);
    final id = 'c_$fingerprint';
    db.execute('INSERT OR IGNORE INTO conversations(id,peer_fingerprint) VALUES(?,?)', [id, fingerprint]);
    return id;
  }

  void changePeer(String fingerprint) {
    changed.add(conversation(fingerprint));
  }

  ChatConversation readConversation(Row r) => ChatConversation(
    id: r['id'] as String,
    peerFingerprint: r['peer_fingerprint'] as String,
    lastActivity: r['last_activity'] as int,
    unreadCount: r['unread_count'] as int,
  );
  ChatMessage readMessage(Row r) => ChatMessage(
    key: MessageKey(r['sender_fingerprint'] as String, r['message_id'] as String),
    conversationId: r['conversation_id'] as String,
    peerFingerprint: r['peer_fingerprint'] as String,
    localSequence: r['local_sequence'] as int,
    kind: MessageKind.values.byName(r['kind'] as String),
    direction: MessageDirection.values.byName(r['direction'] as String),
    text: r['text'] as String?,
    sentAtMs: r['sent_at_ms'] as int,
    receivedAtMs: r['received_at_ms'] as int?,
    deliveryState: DeliveryState.values.byName(r['delivery_state'] as String),
    attemptCount: r['attempt_count'] as int,
    nextAttemptAt: r['next_attempt_at'] as int?,
    lastError: r['last_error'] as String?,
  );
  List<Object?> keyArgs(MessageKey key) => [key.senderFingerprint, key.messageId];
  ChatMessage message(MessageKey key) {
    final rows = db.select('SELECT * FROM messages WHERE sender_fingerprint=? AND message_id=?', keyArgs(key));
    if (rows.isEmpty) throw const ChatStorageException('not_found');
    return readMessage(rows.single);
  }

  ChatInvitation readInvitation(String fingerprint, String id) {
    final rows = db.select('SELECT * FROM invitations WHERE peer_fingerprint=? AND invitation_id=?', [fingerprint, id]);
    if (rows.isEmpty) throw const ChatStorageException('denied');
    return invitation(rows.single);
  }

  ChatInvitation invitation(Row r) => ChatInvitation(
    invitationId: r['invitation_id'] as String,
    peerFingerprint: r['peer_fingerprint'] as String,
    direction: MessageDirection.values.byName(r['direction'] as String),
    status: InvitationStatus.values.byName(r['status'] as String),
  );

  void invite(String fingerprint, String id, bool outgoing) {
    validateId(id);
    final peer = ensurePeer(fingerprint);
    final existing = db.select('SELECT * FROM invitations WHERE peer_fingerprint=? AND invitation_id=?', [fingerprint, id]);
    if (existing.isNotEmpty) {
      if ((existing.single['direction'] == 'outgoing') != outgoing) throw const ChatStorageException('conflict');
      return;
    }
    final blocked = peer.localPermission == ChatPermission.blocked;
    final denied = peer.localPermission == ChatPermission.denied;
    if (outgoing && blocked) throw const ChatStorageException('denied');
    final status = outgoing
        ? InvitationStatus.pending
        : blocked || denied
        ? InvitationStatus.rejected
        : peer.localPermission == ChatPermission.allowed
        ? InvitationStatus.accepted
        : InvitationStatus.pending;
    if (status == InvitationStatus.pending && (db.select("SELECT COUNT(*) n FROM invitations WHERE status='pending'").single['n'] as int) >= 64) {
      throw const ChatStorageException('overloaded');
    }
    db.execute('INSERT INTO invitations VALUES(?,?,?,?,?)', [
      id,
      fingerprint,
      outgoing ? 'outgoing' : 'incoming',
      status.name,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    if (outgoing) {
      db.execute("UPDATE peers SET local_permission='allowed',remote_permission='pending' WHERE fingerprint=?", [fingerprint]);
    } else if (!blocked && !denied) {
      db.execute("UPDATE peers SET local_permission=?,remote_permission='allowed' WHERE fingerprint=?", [
        status == InvitationStatus.accepted ? 'allowed' : 'pending',
        fingerprint,
      ]);
    }
    changePeer(fingerprint);
  }

  void decide(String fingerprint, String id, bool accept, bool outgoing) {
    final value = readInvitation(fingerprint, id);
    if ((value.direction == MessageDirection.outgoing) != outgoing) throw const ChatStorageException('denied');
    if (value.status != InvitationStatus.pending) return;
    final peer = getPeer(fingerprint)!;
    if (peer.localPermission == ChatPermission.blocked || peer.localPermission == ChatPermission.denied) throw const ChatStorageException('denied');
    db.execute('UPDATE invitations SET status=? WHERE peer_fingerprint=? AND invitation_id=?', [accept ? 'accepted' : 'rejected', fingerprint, id]);
    if (outgoing) {
      db.execute('UPDATE peers SET remote_permission=? WHERE fingerprint=?', [accept ? 'allowed' : 'denied', fingerprint]);
    } else {
      db.execute('UPDATE peers SET local_permission=? WHERE fingerprint=?', [accept ? 'allowed' : 'denied', fingerprint]);
    }
    // All pending requests in this direction describe the same consent, whether
    // accepted or rejected. A local rejection also cancels our pending requests:
    // they can no longer complete while local permission is denied.
    db.execute("UPDATE invitations SET status=? WHERE peer_fingerprint=? AND direction=? AND status='pending'", [
      accept ? 'accepted' : 'rejected',
      fingerprint,
      outgoing ? 'outgoing' : 'incoming',
    ]);
    if (!outgoing && !accept) {
      db.execute("UPDATE invitations SET status='rejected' WHERE peer_fingerprint=? AND status='pending'", [fingerprint]);
    }
    changePeer(fingerprint);
  }

  void requireAllowed(String fingerprint, {required bool outgoing}) {
    final peer = getPeer(fingerprint);
    if (peer == null || peer.localPermission != ChatPermission.allowed || (outgoing && peer.remotePermission != ChatPermission.allowed)) {
      throw const ChatStorageException('denied');
    }
  }

  Object saveText(String fingerprint, String id, String text, int sentAt, int? receivedAt) {
    validateId(id);
    validateText(text);
    final outgoing = receivedAt == null;
    requireAllowed(fingerprint, outgoing: outgoing);
    final key = MessageKey(outgoing ? owner : fingerprint, id);
    final existing = db.select('SELECT * FROM messages WHERE sender_fingerprint=? AND message_id=?', keyArgs(key));
    if (existing.isNotEmpty) {
      final row = readMessage(existing.single);
      if (row.peerFingerprint != fingerprint || row.kind != MessageKind.text || row.text != text || row.sentAtMs != sentAt) {
        throw const ChatStorageException('conflict');
      }
      return outgoing ? row : IncomingCommit(key: key, duplicate: true);
    }
    if (outgoing &&
        (db.select("SELECT COUNT(*) n FROM messages WHERE direction='outgoing' AND delivery_state IN ('queued','sending','unconfirmed')").single['n']
                as int) >=
            1000) {
      throw const ChatStorageException('overloaded');
    }
    final cid = conversation(fingerprint);
    db.execute(
      '''INSERT INTO messages(sender_fingerprint,message_id,conversation_id,peer_fingerprint,kind,direction,text,sent_at_ms,received_at_ms,delivery_state,next_attempt_at)
      VALUES(?,?,?,?,'text',?,?,?,?,?,?)''',
      [
        key.senderFingerprint,
        id,
        cid,
        fingerprint,
        outgoing ? 'outgoing' : 'incoming',
        text,
        sentAt,
        receivedAt,
        outgoing ? 'queued' : 'delivered',
        outgoing ? sentAt : null,
      ],
    );
    final sequence = db.lastInsertRowId;
    db.execute('UPDATE conversations SET last_activity=MAX(last_activity,?),last_sequence=?,unread_count=unread_count+? WHERE id=?', [
      receivedAt ?? sentAt,
      sequence,
      outgoing ? 0 : 1,
      cid,
    ]);
    changed.add(cid);
    return outgoing ? message(key) : IncomingCommit(key: key, duplicate: false);
  }

  ChatAttachment attachment(Row r) => ChatAttachment(
    attachmentId: r['attachment_id'] as String,
    messageKey: MessageKey(r['sender_fingerprint'] as String, r['message_id'] as String),
    transferId: r['transfer_id'] as String,
    sessionId: r['session_id'] as String?,
    remoteSessionId: r['remote_session_id'] as String?,
    fileId: r['file_id'] as String,
    name: r['name'] as String,
    size: r['size'] as int,
    localPath: r['local_path'] as String?,
    state: AttachmentState.values.byName(r['state'] as String),
  );
  List<ChatAttachment> attachments(MessageKey key) =>
      db.select('SELECT * FROM attachments WHERE sender_fingerprint=? AND message_id=? ORDER BY file_id', keyArgs(key)).map(attachment).toList();

  void fileOffer(String fingerprint, ChatTransferContext context, List<ChatAttachment> files, bool incoming) {
    validateId(context.messageId);
    validateId(context.transferId);
    requireAllowed(fingerprint, outgoing: !incoming);
    if (context.conversationId != conversation(fingerprint) || files.isEmpty || files.length > 1000) {
      throw const ChatStorageException('invalid_mapping');
    }
    final key = MessageKey(incoming ? fingerprint : owner, context.messageId);
    final ids = <String>{}, wireIds = <String>{};
    final session = files.first.sessionId;
    for (final file in files) {
      validateId(file.attachmentId);
      if (file.messageKey != key ||
          file.transferId != context.transferId ||
          file.sessionId != session ||
          session == null ||
          session.isEmpty ||
          file.fileId.isEmpty ||
          file.fileId.length > 128 ||
          !ids.add(file.attachmentId) ||
          !wireIds.add(file.fileId) ||
          file.size < 0 ||
          file.name.isEmpty ||
          utf8.encode(file.name).length > 4096 ||
          file.state != AttachmentState.offered) {
        throw const ChatStorageException('invalid_mapping');
      }
    }
    final reused = db.select('SELECT message_id FROM attachments WHERE sender_fingerprint=? AND transfer_id=? AND message_id<>? LIMIT 1', [
      key.senderFingerprint,
      context.transferId,
      key.messageId,
    ]);
    if (reused.isNotEmpty) throw const ChatStorageException('conflict');
    final existing = db.select('SELECT * FROM messages WHERE sender_fingerprint=? AND message_id=?', keyArgs(key));
    if (existing.isNotEmpty) {
      final m = readMessage(existing.single);
      final prior = {for (final f in attachments(key)) f.fileId: f};
      if (m.kind != MessageKind.attachment || m.peerFingerprint != fingerprint || prior.length != files.length) {
        throw const ChatStorageException('conflict');
      }
      for (final f in files) {
        final p = prior[f.fileId];
        if (p == null ||
            p.attachmentId != f.attachmentId ||
            p.transferId != f.transferId ||
            p.sessionId != f.sessionId ||
            p.name != f.name ||
            p.size != f.size) {
          throw const ChatStorageException('conflict');
        }
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      '''INSERT INTO messages(sender_fingerprint,message_id,conversation_id,peer_fingerprint,kind,direction,sent_at_ms,received_at_ms,delivery_state)
      VALUES(?,?,?,?,'attachment',?,?,?,?)''',
      [
        key.senderFingerprint,
        key.messageId,
        context.conversationId,
        fingerprint,
        incoming ? 'incoming' : 'outgoing',
        now,
        incoming ? now : null,
        'queued',
      ],
    );
    final sequence = db.lastInsertRowId;
    for (final f in files) {
      db.execute(
        '''INSERT INTO attachments(attachment_id,sender_fingerprint,message_id,transfer_id,session_id,file_id,name,size,local_path,state)
        VALUES(?,?,?,?,?,?,?,?,?,'offered')''',
        [f.attachmentId, key.senderFingerprint, key.messageId, context.transferId, session, f.fileId, f.name, f.size, f.localPath],
      );
    }
    db.execute('UPDATE conversations SET last_activity=MAX(last_activity,?),last_sequence=?,unread_count=unread_count+? WHERE id=?', [
      now,
      sequence,
      incoming ? 1 : 0,
      context.conversationId,
    ]);
    changed.add(context.conversationId);
  }

  void attachmentResult(AttachmentResult result) {
    final m = message(result.messageKey);
    final rows = db.select('SELECT * FROM attachments WHERE sender_fingerprint=? AND message_id=? AND file_id=?', [
      ...keyArgs(result.messageKey),
      result.fileId,
    ]);
    if (rows.isEmpty || m.kind != MessageKind.attachment || m.peerFingerprint != result.peerFingerprint) throw const ChatStorageException('denied');
    final a = attachment(rows.single);
    if (a.sessionId != result.sessionId ||
        a.transferId != result.transferId ||
        (a.remoteSessionId != null && result.remoteSessionId != null && a.remoteSessionId != result.remoteSessionId)) {
      throw const ChatStorageException('denied');
    }
    // A finished or rejected file cannot be reopened by a stale callback. A write
    // already in progress may truthfully finish after the user cancelled the batch.
    if (a.state == AttachmentState.complete || a.state == AttachmentState.rejected) return;
    if ({AttachmentState.cancelled, AttachmentState.failed}.contains(a.state) &&
        !{AttachmentState.complete, AttachmentState.failed}.contains(result.state)) {
      return;
    }
    db.execute(
      '''UPDATE attachments SET state=?,local_path=COALESCE(?,local_path),remote_session_id=COALESCE(?,remote_session_id)
      WHERE sender_fingerprint=? AND message_id=? AND file_id=?''',
      [result.state.name, result.localPath, result.remoteSessionId, ...keyArgs(result.messageKey), result.fileId],
    );
    final statuses = attachments(result.messageKey).map((a) => a.state).toList();
    final delivery = statuses.every((s) => s == AttachmentState.complete)
        ? 'delivered'
        : statuses.every((s) => s == AttachmentState.rejected)
        ? 'rejected'
        : statuses.any((s) => {AttachmentState.offered, AttachmentState.waiting, AttachmentState.transferring}.contains(s))
        ? 'sending'
        : 'failed';
    updateMessage(m, 'delivery_state=?', [delivery]);
  }

  void changeIdentity(String fingerprint) {
    validateFingerprint(fingerprint);
    final rows = db.select("SELECT value FROM metadata WHERE key='owner'");
    if (rows.isNotEmpty && rows.single['value'] != fingerprint) {
      db.execute("UPDATE peers SET local_permission='unknown',remote_permission='unknown'");
      db.execute("UPDATE invitations SET status='rejected' WHERE status='pending'");
      db.execute(
        "UPDATE messages SET delivery_state='failed',next_attempt_at=NULL,last_error='identity_changed' WHERE direction='outgoing' AND delivery_state<>'delivered'",
      );
      changed.addAll(db.select('SELECT id FROM conversations').map((r) => r['id'] as String));
    }
    db.execute("INSERT INTO metadata(key,value) VALUES('owner',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [fingerprint]);
    owner = fingerprint;
  }

  void recover() {
    changed.addAll(db.select("SELECT conversation_id FROM messages WHERE delivery_state='sending'").map((r) => r['conversation_id'] as String));
    db.execute("UPDATE messages SET delivery_state='unconfirmed',last_error='interrupted' WHERE kind='text' AND delivery_state='sending'");
    db.execute("UPDATE attachments SET state='failed' WHERE state IN ('offered','waiting','transferring')");
    db.execute(
      "UPDATE messages SET delivery_state='failed',last_error='interrupted' WHERE kind='attachment' AND delivery_state IN ('queued','sending')",
    );
  }

  bool canAttempt(ChatMessage value, int now) {
    final peer = getPeer(value.peerFingerprint)!;
    return value.key.senderFingerprint == owner &&
        value.direction == MessageDirection.outgoing &&
        value.kind == MessageKind.text &&
        [DeliveryState.queued, DeliveryState.unconfirmed].contains(value.deliveryState) &&
        value.attemptCount < 4 &&
        value.nextAttemptAt != null &&
        value.nextAttemptAt! <= now &&
        peer.localPermission == ChatPermission.allowed &&
        peer.remotePermission == ChatPermission.allowed;
  }

  void updateMessage(ChatMessage value, String sql, List<Object?> args) {
    db.execute('UPDATE messages SET $sql WHERE sender_fingerprint=? AND message_id=?', [...args, ...keyArgs(value.key)]);
    changed.add(value.conversationId);
  }

  Object? execute(String method, List<Object?> a) {
    switch (method) {
      case 'recordFileOffer':
        fileOffer(a[0] as String, a[1] as ChatTransferContext, (a[2] as List).cast<ChatAttachment>(), a[3] as bool);
        return null;
      case 'listAttachments':
        return attachments(a[0] as MessageKey);
      case 'attachmentResult':
        attachmentResult(a[0] as AttachmentResult);
        return null;
      case 'sessionAttachmentResult':
        final state = a[2] as AttachmentState;
        if (a[1] == null && state == AttachmentState.complete) throw const ChatStorageException('invalid_state');
        final rows = db.select(
          '''SELECT a.*, m.peer_fingerprint FROM attachments a JOIN messages m
          ON a.sender_fingerprint=m.sender_fingerprint AND a.message_id=m.message_id
          WHERE a.session_id=? AND (? IS NULL OR a.file_id=?)''',
          [a[0], a[1], a[1]],
        );
        for (final r in rows) {
          final file = attachment(r);
          attachmentResult(
            AttachmentResult(
              peerFingerprint: r['peer_fingerprint'] as String,
              messageKey: file.messageKey,
              transferId: file.transferId,
              sessionId: a[0] as String,
              fileId: file.fileId,
              state: state,
              localPath: a[3] as String?,
              remoteSessionId: a[4] as String?,
            ),
          );
        }
        return null;
      case 'upsertPeer':
        final peer = a[0] as ChatPeer;
        ensurePeer(peer.fingerprint);
        db.execute('UPDATE peers SET alias=?,platform=?,host=?,port=?,last_seen=? WHERE fingerprint=?', [
          peer.alias,
          peer.platform,
          peer.host,
          peer.port,
          peer.lastSeen,
          peer.fingerprint,
        ]);
        final rows = db.select('SELECT id FROM conversations WHERE peer_fingerprint=?', [peer.fingerprint]);
        changed.addAll(rows.map((r) => r['id'] as String));
        return null;
      case 'getPeer':
        return getPeer(a[0] as String);
      case 'setOwnDevice':
        final fingerprint = a[0] as String;
        ensurePeer(fingerprint);
        db.execute('UPDATE peers SET is_own_device=? WHERE fingerprint=?', [a[1] == true ? 1 : 0, fingerprint]);
        changePeer(fingerprint);
        return null;
      case 'beginInvitation':
        invite(a[0] as String, a[1] as String, true);
        return null;
      case 'recordInvitation':
        invite(a[0] as String, a[1] as String, false);
        return null;
      case 'decideInvitation':
        decide(a[0] as String, a[1] as String, a[2] as bool, false);
        return null;
      case 'completeInvitation':
        decide(a[0] as String, a[1] as String, a[2] as bool, true);
        return null;
      case 'readInvitation':
        return readInvitation(a[0] as String, a[1] as String);
      case 'listInvitations':
        return db
            .select('SELECT * FROM invitations WHERE (? IS NULL OR peer_fingerprint=?) ORDER BY created_at DESC', [a[0], a[0]])
            .map(invitation)
            .toList();
      case 'revokePermission':
        final fingerprint = a[0] as String;
        ensurePeer(fingerprint);
        db.execute("UPDATE peers SET local_permission=?,remote_permission='unknown' WHERE fingerprint=?", [
          a[1] == true ? 'blocked' : 'denied',
          fingerprint,
        ]);
        db.execute("UPDATE invitations SET status='rejected' WHERE peer_fingerprint=? AND status='pending'", [fingerprint]);
        db.execute(
          "UPDATE messages SET delivery_state='rejected',next_attempt_at=NULL,last_error='permission_revoked' WHERE peer_fingerprint=? AND direction='outgoing' AND delivery_state IN ('queued','sending','unconfirmed')",
          [fingerprint],
        );
        changePeer(fingerprint);
        return null;
      case 'ensureConversation':
        return readConversation(db.select('SELECT * FROM conversations WHERE id=?', [conversation(a[0] as String)]).single);
      case 'listConversations':
        return db.select('SELECT * FROM conversations ORDER BY last_sequence DESC,last_activity DESC,id').map(readConversation).toList();
      case 'listMessages':
        final limit = a[2] as int;
        if (limit < 1 || limit > 200) throw const ChatStorageException('invalid_limit');
        return db
            .select('SELECT * FROM messages WHERE conversation_id=? AND (? IS NULL OR local_sequence<?) ORDER BY local_sequence DESC LIMIT ?', [
              a[0],
              a[1],
              a[1],
              limit,
            ])
            .map(readMessage)
            .toList();
      case 'enqueueText':
        return saveText(a[0] as String, a[1] as String, a[2] as String, a[3] as int, null);
      case 'commitIncoming':
        return saveText(a[0] as String, a[1] as String, a[2] as String, a[3] as int, a[4] as int);
      case 'loadDueOutbox':
        return db
            .select(
              "SELECT * FROM messages WHERE direction='outgoing' AND kind='text' AND delivery_state IN ('queued','unconfirmed') AND attempt_count<4 AND next_attempt_at<=? AND (? IS NULL OR peer_fingerprint=?) ORDER BY local_sequence",
              [a[0], a[1], a[1]],
            )
            .map(readMessage)
            .where((m) => canAttempt(m, a[0] as int))
            .toList();
      case 'tryStartAttempt':
        final value = message(a[0] as MessageKey);
        final now = a[1] as int;
        if (!canAttempt(value, now)) return false;
        // Persist the attempt and recovery deadline BEFORE starting network IO.
        final count = value.attemptCount + 1;
        updateMessage(value, "delivery_state='sending',attempt_count=?,next_attempt_at=?,last_error=NULL", [count, now + (1000 << (count - 1))]);
        return true;
      case 'recordDelivery':
        final value = message(a[0] as MessageKey);
        if (value.kind != MessageKind.text) throw const ChatStorageException('invalid_state');
        if (value.peerFingerprint != a[1] || value.key.senderFingerprint != owner || value.direction != MessageDirection.outgoing) {
          throw const ChatStorageException('denied');
        }
        if (value.deliveryState == DeliveryState.delivered) return null;
        if (value.deliveryState != DeliveryState.sending) throw const ChatStorageException('invalid_state');
        requireAllowed(value.peerFingerprint, outgoing: true);
        updateMessage(value, "delivery_state='delivered',next_attempt_at=NULL,last_error=NULL", []);
        return null;
      case 'recordAttemptFailure':
        final value = message(a[0] as MessageKey);
        final failure = a[1] as DeliveryFailure;
        if (value.deliveryState != DeliveryState.sending || value.key.senderFingerprint != owner) return null;
        final next = failure.retryable && value.attemptCount < 4
            ? failure.occurredAt.millisecondsSinceEpoch + (1000 << (value.attemptCount - 1))
            : null;
        updateMessage(value, 'delivery_state=?,next_attempt_at=?,last_error=?', [
          failure.retryable
              ? 'unconfirmed'
              : failure.code == 'denied'
              ? 'rejected'
              : 'failed',
          next,
          failure.code,
        ]);
        return null;
      case 'scheduleManualRetry':
        final value = message(a[0] as MessageKey);
        if (value.key.senderFingerprint != owner || value.attemptCount < 4 || value.deliveryState != DeliveryState.unconfirmed) {
          throw const ChatStorageException('invalid_state');
        }
        requireAllowed(value.peerFingerprint, outgoing: true);
        updateMessage(value, "delivery_state='queued',attempt_count=0,next_attempt_at=?,last_error=NULL", [a[1]]);
        return null;
      case 'recover':
        recover();
        return null;
      case 'changeIdentity':
        changeIdentity(a[0] as String);
        return null;
      case 'markRead':
        db.execute('UPDATE conversations SET read_sequence=MAX(read_sequence,MIN(last_sequence,?)) WHERE id=?', [a[1], a[0]]);
        db.execute(
          "UPDATE conversations SET unread_count=(SELECT COUNT(*) FROM messages WHERE conversation_id=? AND direction='incoming' AND local_sequence>conversations.read_sequence) WHERE id=?",
          [a[0], a[0]],
        );
        changed.add(a[0] as String);
        return null;
      default:
        throw const ChatStorageException('invalid_command');
    }
  }
}
