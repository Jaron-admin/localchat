import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native SQLite commits, deduplicates and recovers after reopen', (tester) async {
    final root = await getTemporaryDirectory();
    final directory = await Directory('${root.path}/localchat-smoke-${const Uuid().v4()}').create();
    final owner = 'A' * 64, peer = 'B' * 64;
    var repository = await ChatRepository.open('${directory.path}/chat.sqlite3', localFingerprint: owner);
    try {
      final invitation = const Uuid().v4();
      await repository.recordInvitation(peer, invitation);
      await repository.decideInvitation(peer, invitation, true);
      final incomingId = const Uuid().v4();
      await repository.commitIncoming(verifiedFingerprint: peer, messageId: incomingId, text: '原生 SQLite 你好', sentAtMs: 1, receivedAtMs: 2);
      final outgoing = await repository.enqueueText(peerFingerprint: peer, messageId: const Uuid().v4(), text: 'Restart me', sentAtMs: 3);
      expect(await repository.tryStartAttempt(outgoing.key, DateTime.now()), isTrue);
      await repository.close();
      repository = await ChatRepository.open('${directory.path}/chat.sqlite3', localFingerprint: owner);
      await repository.commitIncoming(verifiedFingerprint: peer, messageId: incomingId, text: '原生 SQLite 你好', sentAtMs: 1, receivedAtMs: 4);
      final messages = await repository.listMessages(outgoing.conversationId);
      expect(messages, hasLength(2));
      expect(messages.singleWhere((m) => m.key.messageId == incomingId).text, '原生 SQLite 你好');
      expect(messages.singleWhere((m) => m.key == outgoing.key).deliveryState, DeliveryState.unconfirmed);
      expect(messages.singleWhere((m) => m.key == outgoing.key).attemptCount, 1);
    } finally {
      await repository.close();
      await directory.delete(recursive: true);
    }
  });
}
