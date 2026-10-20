import 'dart:io';

import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/model/chat/chat_transfer_context.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory directory;
  late ChatRepository repository;
  late ChatTransferContext context;
  late List<ChatAttachment> files;
  final owner = 'A' * 64, peer = 'B' * 64;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-attachments-');
    repository = await ChatRepository.open('${directory.path}/chat.sqlite3', localFingerprint: owner);
    final invitation = const Uuid().v4();
    await repository.recordInvitation(peer, invitation);
    await repository.decideInvitation(peer, invitation, true);
    context = ChatTransferContext(
      conversationId: (await repository.ensureConversation(peer)).id,
      messageId: const Uuid().v4(),
      transferId: const Uuid().v4(),
    );
    files = List.generate(
      3,
      (i) => ChatAttachment(
        attachmentId: const Uuid().v4(),
        messageKey: MessageKey(owner, context.messageId),
        transferId: context.transferId,
        sessionId: 'local-session',
        fileId: 'file-$i',
        name: 'fixture-$i.txt',
        size: 4,
        state: AttachmentState.offered,
      ),
    );
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });
  Future<void> offer() => repository.recordFileOffer(peerFingerprint: peer, context: context, files: files, incoming: false);
  AttachmentResult result(int i, AttachmentState state, {String? fingerprint, String session = 'local-session'}) => AttachmentResult(
    peerFingerprint: fingerprint ?? peer,
    messageKey: files[i].messageKey,
    transferId: context.transferId,
    sessionId: session,
    fileId: files[i].fileId,
    state: state,
    remoteSessionId: 'remote-session',
  );
  test('stable mapping is idempotent and rejects cross-peer/session ownership', () async {
    await offer();
    await offer();
    expect(await repository.listMessages(context.conversationId), hasLength(1));
    expect(await repository.listAttachments(files.first.messageKey), hasLength(3));
    await expectLater(
      repository.applyAttachmentResult(result(0, AttachmentState.complete, fingerprint: 'C' * 64)),
      throwsA(isA<ChatStorageException>()),
    );
    await expectLater(
      repository.applyAttachmentResult(result(0, AttachmentState.complete, session: 'wrong-session')),
      throwsA(isA<ChatStorageException>()),
    );
    expect((await repository.listAttachments(files.first.messageKey)).every((a) => a.state == AttachmentState.offered), isTrue);
    await expectLater(repository.recordDelivery(files.first.messageKey, verifiedPeerFingerprint: peer), throwsA(isA<ChatStorageException>()));
    expect((await repository.listAttachments(files.first.messageKey)).first.state, AttachmentState.offered);
    await repository.applyAttachmentResult(result(0, AttachmentState.transferring));
    await expectLater(repository.recordDelivery(files.first.messageKey, verifiedPeerFingerprint: peer), throwsA(isA<ChatStorageException>()));
  });
  test('version one database migrates without replacing text history or permissions', () async {
    await repository.enqueueText(peerFingerprint: peer, messageId: const Uuid().v4(), text: 'Keep my history', sentAtMs: 1);
    await repository.close();
    final db = sqlite3.open('${directory.path}/chat.sqlite3');
    db.execute('ALTER TABLE attachments DROP COLUMN remote_session_id');
    db.execute('PRAGMA user_version=1');
    db.close();
    repository = await ChatRepository.open('${directory.path}/chat.sqlite3', localFingerprint: owner);
    await offer();
    expect((await repository.listMessages(context.conversationId)).any((m) => m.text == 'Keep my history'), isTrue);
    expect(await repository.listAttachments(files.first.messageKey), hasLength(3));
  });
  test('partial rejection, failed save and cancellation persist per file; completed files stay complete', () async {
    await offer();
    await repository.applyAttachmentResult(result(0, AttachmentState.complete));
    await repository.applyAttachmentResult(result(1, AttachmentState.rejected));
    await repository.applyAttachmentResult(result(2, AttachmentState.failed));
    await repository.applyAttachmentResult(result(0, AttachmentState.cancelled));
    final rows = await repository.listAttachments(files.first.messageKey);
    expect(
      {for (final a in rows) a.fileId: a.state},
      {'file-0': AttachmentState.complete, 'file-1': AttachmentState.rejected, 'file-2': AttachmentState.failed},
    );
    expect(rows.first.remoteSessionId, 'remote-session');
    await repository.close();
    repository = await ChatRepository.open('${directory.path}/chat.sqlite3', localFingerprint: owner);
    expect((await repository.listAttachments(files.first.messageKey)).where((a) => a.state == AttachmentState.complete), hasLength(1));
  });
  test('restarting an unfinished transfer keeps its card but marks it interrupted', () async {
    await offer();
    await repository.applyAttachmentResult(result(1, AttachmentState.cancelled));
    await repository.close();
    repository = await ChatRepository.open('${directory.path}/chat.sqlite3', localFingerprint: owner);
    final rows = await repository.listAttachments(files.first.messageKey);
    expect(rows.where((a) => a.state == AttachmentState.failed), hasLength(2));
    expect(rows.where((a) => a.state == AttachmentState.cancelled), hasLength(1));
    expect(await repository.loadDueOutbox(DateTime.now()), isEmpty);
  });
  test('incoming offers require actual permitted sender and matching conversation and immutable mapping', () async {
    final incoming = files
        .map(
          (a) => ChatAttachment(
            attachmentId: a.attachmentId,
            messageKey: MessageKey(peer, context.messageId),
            transferId: context.transferId,
            sessionId: a.sessionId,
            fileId: a.fileId,
            name: a.name,
            size: a.size,
            state: AttachmentState.offered,
          ),
        )
        .toList();
    await repository.recordFileOffer(peerFingerprint: peer, context: context, files: incoming, incoming: true);
    final bad = ChatTransferContext(conversationId: 'c_${'C' * 64}', messageId: context.messageId, transferId: context.transferId);
    await expectLater(
      repository.recordFileOffer(peerFingerprint: peer, context: bad, files: incoming, incoming: true),
      throwsA(isA<ChatStorageException>()),
    );
    await expectLater(
      repository.recordFileOffer(peerFingerprint: peer, context: context, files: incoming.take(1).toList(), incoming: true),
      throwsA(isA<ChatStorageException>()),
    );
    expect(await repository.listMessages(context.conversationId), hasLength(1));
  });
}
