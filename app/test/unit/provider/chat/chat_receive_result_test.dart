import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_transfer_context.dart';
import 'package:localsend_app/provider/chat/chat_repository_provider.dart';
import 'package:localsend_app/provider/network/server/controller/receive_controller.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('actual receive results persist after the UI session has closed, including failed saves', () async {
    final dir = await Directory.systemTemp.createTemp('chat-late-file-');
    final owner = 'A' * 64, peer = 'B' * 64;
    final repository = await ChatRepository.open('${dir.path}/chat.sqlite3', localFingerprint: owner);
    final container = RefenaContainer(overrides: [chatRepositoryProvider.overrideWithValue(repository)]);
    try {
      final invitation = const Uuid().v4();
      await repository.recordInvitation(peer, invitation);
      await repository.decideInvitation(peer, invitation, true);
      final context = ChatTransferContext(
        conversationId: (await repository.ensureConversation(peer)).id,
        messageId: const Uuid().v4(),
        transferId: const Uuid().v4(),
      );
      final key = MessageKey(peer, context.messageId);
      await repository.recordFileOffer(
        peerFingerprint: peer,
        context: context,
        incoming: true,
        files: [
          for (final id in ['good', 'failed'])
            ChatAttachment(
              attachmentId: const Uuid().v4(),
              messageKey: key,
              transferId: context.transferId,
              sessionId: 'old-session',
              fileId: id,
              name: '$id.bin',
              size: 4,
              state: AttachmentState.offered,
            ),
        ],
      );
      await repository.applySessionAttachmentResult(sessionId: 'old-session', state: AttachmentState.cancelled);
      final controller = ReceiveController(
        ServerUtils(
          refFunc: () => container,
          getState: () => throw StateError('No UI session'),
          getStateOrNull: () => null,
          setState: (_) => fail('Closed UI must not be changed'),
        ),
      );
      await controller.onFileUploadResult(
        HttpServerFileUploadResultEvent(sessionId: 'old-session', fileId: 'good', path: '/saved/good.bin', savedToGallery: false, error: null),
      );
      await controller.onFileUploadResult(
        HttpServerFileUploadResultEvent(sessionId: 'old-session', fileId: 'failed', path: null, savedToGallery: false, error: 'Disk full'),
      );
      final files = {for (final f in await repository.listAttachments(key)) f.fileId: f};
      expect(files['good']!.state, AttachmentState.complete);
      expect(files['good']!.localPath, '/saved/good.bin');
      expect(files['failed']!.state, AttachmentState.failed);
      await controller.onFileUploadResult(
        HttpServerFileUploadResultEvent(sessionId: 'unrelated-session', fileId: 'good', path: '/wrong', savedToGallery: false, error: null),
      );
      expect((await repository.listAttachments(key)).firstWhere((f) => f.fileId == 'good').localPath, '/saved/good.bin');
    } finally {
      container.disposeContainer();
      await repository.close();
      await dir.delete(recursive: true);
    }
  });
}
