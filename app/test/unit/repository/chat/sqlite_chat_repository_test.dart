import 'dart:io';

import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const owner = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const peer = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const other = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
String id() => const Uuid().v4();

void main() {
  late Directory directory;
  late String path;
  late ChatRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('localchat-db-');
    path = '${directory.path}/chat.sqlite3';
    repository = await ChatRepository.open(path, localFingerprint: owner);
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<void> allow([String fingerprint = peer]) async {
    final invitation = id();
    await repository.recordInvitation(fingerprint, invitation);
    await repository.decideInvitation(fingerprint, invitation, true);
  }

  Future<IncomingCommit> incoming(String messageId, {String text = '你好 👋', int sentAt = 1}) => repository.commitIncoming(
    verifiedFingerprint: peer,
    messageId: messageId,
    text: text,
    sentAtMs: sentAt,
    receivedAtMs: 100,
  );

  test('commits once, rejects conflicting body/timestamp, survives reopening', () async {
    await allow();
    final messageId = id();
    expect((await incoming(messageId)).duplicate, isFalse);
    expect((await incoming(messageId)).duplicate, isTrue);
    await expectLater(incoming(messageId, text: 'changed'), throwsA(isA<ChatStorageException>().having((e) => e.code, 'code', 'conflict')));
    await expectLater(incoming(messageId, sentAt: 2), throwsA(isA<ChatStorageException>()));
    await repository.close();
    repository = await ChatRepository.open(path, localFingerprint: owner);
    final conversation = (await repository.listConversations()).single;
    final rows = await repository.listMessages(conversation.id);
    expect(rows.length, 1);
    expect(rows.single.key.messageId, messageId);
    expect(conversation.unreadCount, 1);
    expect((await incoming(messageId)).duplicate, isTrue);
  });

  test('storage failure rolls back message, conversation summary and notification', () async {
    await allow();
    final conversation = await repository.ensureConversation(peer);
    final events = <ChatChange>[];
    final subscription = repository.changes.listen(events.add);
    final external = sqlite3.open(path);
    external.execute("CREATE TRIGGER fail_summary BEFORE UPDATE ON conversations BEGIN SELECT RAISE(ABORT, 'storage failure'); END");
    external.close();
    await expectLater(incoming(id()), throwsA(isA<ChatStorageException>()));
    expect(await repository.listMessages(conversation.id), isEmpty);
    expect((await repository.listConversations()).single.unreadCount, 0);
    expect(events, isEmpty);
    await subscription.cancel();
  });

  test('revocation and writes are serialized, duplicate cannot bypass revocation', () async {
    await allow();
    final messageId = id();
    await incoming(messageId);
    final revoke = repository.revokePermission(peer, block: true);
    final rejected = incoming(id());
    await revoke;
    await expectLater(rejected, throwsA(isA<ChatStorageException>().having((e) => e.code, 'code', 'denied')));
    await expectLater(incoming(messageId), throwsA(isA<ChatStorageException>()));
    await repository.recordInvitation(peer, id());
    expect((await repository.getPeer(peer))!.localPermission, ChatPermission.blocked);
  });

  test('address change preserves identity, IP replacement never inherits permission', () async {
    await allow();
    final conversation = await repository.ensureConversation(peer);
    await repository.upsertPeer(const ChatPeer(fingerprint: peer, alias: '电脑', host: '192.168.1.2', port: 53317));
    await repository.setOwnDevice(peer, true);
    await repository.upsertPeer(const ChatPeer(fingerprint: peer, alias: '电脑', host: '192.168.1.3', port: 60000));
    await repository.upsertPeer(
      const ChatPeer(fingerprint: other, alias: '电脑', host: '192.168.1.3', port: 60000, localPermission: ChatPermission.allowed),
    );
    expect((await repository.ensureConversation(peer)).id, conversation.id);
    expect((await repository.getPeer(peer))!.localPermission, ChatPermission.allowed);
    expect((await repository.getPeer(peer))!.isOwnDevice, isTrue);
    expect((await repository.getPeer(other))!.localPermission, ChatPermission.unknown);
  });

  test('invitation acceptance is bound to direction, peer and original ID', () async {
    final invitation = id();
    await repository.beginInvitation(peer, invitation);
    expect((await repository.getPeer(peer))!.localPermission, ChatPermission.allowed);
    expect((await repository.getPeer(peer))!.remotePermission, ChatPermission.pending);
    await expectLater(repository.completeOutgoingInvitation(other, invitation, true), throwsA(isA<ChatStorageException>()));
    await expectLater(repository.completeOutgoingInvitation(peer, id(), true), throwsA(isA<ChatStorageException>()));
    await repository.completeOutgoingInvitation(peer, invitation, true);
    expect((await repository.getPeer(peer))!.remotePermission, ChatPermission.allowed);
    final rejected = id();
    await repository.recordInvitation(other, rejected);
    await repository.decideInvitation(other, rejected, false);
    await repository.recordInvitation(other, rejected);
    expect((await repository.readInvitation(other, rejected)).status, InvitationStatus.rejected);
    await expectLater(repository.readInvitation(peer, rejected), throwsA(isA<ChatStorageException>()));
  });

  test('sequence paging survives backwards clocks and identical timestamps', () async {
    await allow();
    final ids = List.generate(7, (_) => id());
    for (var i = 0; i < ids.length; i++) {
      await incoming(ids[i], sentAt: 10 - i ~/ 2);
    }
    final conversation = (await repository.listConversations()).single;
    final seen = <String>[];
    int? cursor;
    while (true) {
      final page = await repository.listMessages(conversation.id, beforeSequence: cursor, limit: 2);
      if (page.isEmpty) break;
      seen.addAll(page.map((m) => m.key.messageId));
      cursor = page.last.localSequence;
    }
    expect(seen, ids.reversed.toList());
    await repository.markConversationRead(conversation.id, 100000);
    expect((await repository.listConversations()).single.unreadCount, 0);
  });

  test('outbox budget and message ID survive crash recovery, manual retry is explicit', () async {
    await allow();
    var now = DateTime.fromMillisecondsSinceEpoch(1000);
    final message = await repository.enqueueText(peerFingerprint: peer, messageId: id(), text: 'queued', sentAtMs: 1000);
    expect(await repository.tryStartAttempt(message.key, now), isTrue);
    expect(await repository.tryStartAttempt(message.key, now), isFalse);
    await repository.close();
    repository = await ChatRepository.open(path, localFingerprint: owner);
    var recovered = (await repository.listMessages(message.conversationId)).single;
    expect(recovered.key, message.key);
    expect(recovered.deliveryState, DeliveryState.unconfirmed);
    expect(recovered.attemptCount, 1);
    for (var attempt = 2; attempt <= 4; attempt++) {
      now = now.add(const Duration(seconds: 10));
      expect(await repository.tryStartAttempt(message.key, now), isTrue);
      await repository.recordAttemptFailure(message.key, DeliveryFailure(retryable: true, code: 'timeout', occurredAt: now));
    }
    expect(await repository.loadDueOutbox(now.add(const Duration(days: 1))), isEmpty);
    expect(await repository.tryStartAttempt(message.key, now.add(const Duration(days: 1))), isFalse);
    await repository.scheduleManualRetry(message.key, now);
    recovered = (await repository.loadDueOutbox(now)).single;
    expect(recovered.key, message.key);
    expect(recovered.attemptCount, 0);
    await expectLater(repository.scheduleManualRetry(message.key, now), throwsA(isA<ChatStorageException>()));
  });

  test('retry delay is 1, 2, 4 seconds; wrong peer cannot acknowledge', () async {
    await allow();
    final now = DateTime.fromMillisecondsSinceEpoch(1000);
    final message = await repository.enqueueText(peerFingerprint: peer, messageId: id(), text: 'test', sentAtMs: 1000);
    var instant = now;
    for (final delay in [1, 2, 4]) {
      expect(await repository.tryStartAttempt(message.key, instant), isTrue);
      await repository.recordAttemptFailure(message.key, DeliveryFailure(retryable: true, code: 'timeout', occurredAt: instant));
      expect(await repository.loadDueOutbox(instant.add(Duration(milliseconds: delay * 1000 - 1))), isEmpty);
      instant = instant.add(Duration(seconds: delay));
      expect((await repository.loadDueOutbox(instant)).single.key, message.key);
    }
    expect(await repository.tryStartAttempt(message.key, instant), isTrue);
    await expectLater(repository.recordDelivery(message.key, verifiedPeerFingerprint: other), throwsA(isA<ChatStorageException>()));
    await repository.recordDelivery(message.key, verifiedPeerFingerprint: peer);
    expect((await repository.listMessages(message.conversationId)).single.deliveryState, DeliveryState.delivered);
    expect(await repository.loadDueOutbox(instant), isEmpty);
  });

  test('certificate reset preserves history and quarantines old outbox', () async {
    await allow();
    await incoming(id());
    final outgoing = await repository.enqueueText(peerFingerprint: peer, messageId: id(), text: 'old identity', sentAtMs: 1);
    await repository.close();
    repository = await ChatRepository.open(path, localFingerprint: other);
    final rows = await repository.listMessages(outgoing.conversationId);
    expect(rows.length, 2);
    expect(rows.first.lastError, 'identity_changed');
    expect(await repository.loadDueOutbox(DateTime.now()), isEmpty);
    expect((await repository.getPeer(peer))!.localPermission, ChatPermission.unknown);
    await expectLater(repository.scheduleManualRetry(outgoing.key, DateTime.now()), throwsA(isA<ChatStorageException>()));
  });

  test('pending invitations and command queue have explicit capacity', () async {
    for (var i = 0; i < 64; i++) {
      await repository.recordInvitation(peer, id());
    }
    await expectLater(repository.recordInvitation(peer, id()), throwsA(isA<ChatStorageException>().having((e) => e.code, 'code', 'overloaded')));
    final futures = List.generate(257, (_) => repository.listConversations().then<Object>((v) => v, onError: (Object e) => e));
    final results = await Future.wait(futures);
    expect(results.whereType<ChatStorageException>().any((e) => e.code == 'overloaded'), isTrue);
  });

  test('rejecting a peer resolves duplicate pending requests and releases capacity after restart', () async {
    final invitations = List.generate(64, (_) => id());
    for (final invitation in invitations) {
      await repository.recordInvitation(peer, invitation);
    }
    await repository.decideInvitation(peer, invitations.first, false);
    await repository.close();
    repository = await ChatRepository.open(path, localFingerprint: owner);
    for (final invitation in invitations) {
      expect((await repository.readInvitation(peer, invitation)).status, InvitationStatus.rejected);
      await repository.decideInvitation(peer, invitation, false); // idempotent UI action
    }
    final legitimate = id();
    await repository.recordInvitation(other, legitimate);
    await repository.decideInvitation(other, legitimate, true);
    expect((await repository.getPeer(other))!.localPermission, ChatPermission.allowed);
  });

  test('corrupt database is preserved and cannot produce a receipt', () async {
    await repository.close();
    final corrupt = File('${directory.path}/corrupt.sqlite3');
    await corrupt.writeAsString('not a database - preserve me');
    final before = await corrupt.readAsBytes();
    await expectLater(ChatRepository.open(corrupt.path, localFingerprint: owner), throwsA(isA<ChatStorageException>()));
    expect(await corrupt.readAsBytes(), before);
  });

  test('outbox capacity is enforced transactionally without losing history', () async {
    await allow();
    for (var i = 0; i < 1000; i++) {
      await repository.enqueueText(peerFingerprint: peer, messageId: id(), text: 'queued $i', sentAtMs: i);
    }
    await expectLater(
      repository.enqueueText(peerFingerprint: peer, messageId: id(), text: 'overflow', sentAtMs: 1001),
      throwsA(isA<ChatStorageException>().having((e) => e.code, 'code', 'overloaded')),
    );
    expect((await repository.loadDueOutbox(DateTime.now())).length, 1000);
  });

  test('a write lock failure cannot return a commit receipt', () async {
    await allow();
    final external = sqlite3.open(path);
    external.execute('BEGIN IMMEDIATE');
    try {
      await expectLater(incoming(id()), throwsA(isA<ChatStorageException>().having((e) => e.code, 'code', 'unavailable')));
    } finally {
      external.execute('ROLLBACK');
      external.close();
    }
    expect(await repository.listMessages((await repository.listConversations()).single.id), isEmpty);
  });

  test('read marker cannot pre-read future messages and live identity reset is atomic', () async {
    await allow();
    await incoming(id());
    final conversation = (await repository.listConversations()).single;
    await repository.markConversationRead(conversation.id, 100000);
    await incoming(id());
    expect((await repository.listConversations()).single.unreadCount, 1);
    await repository.changeLocalIdentity(other);
    await expectLater(incoming(id()), throwsA(isA<ChatStorageException>()));
    expect((await repository.listMessages(conversation.id)).length, 2);
  });
}
