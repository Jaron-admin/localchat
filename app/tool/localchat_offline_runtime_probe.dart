import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:uuid/uuid.dart';
import 'localchat_runtime_probe.dart' show Peer;

Future<void> main(List<String> args) async {
  final a = Peer.load(args[1]), b = Peer.load(args[2]);
  if (args[0] == 'prime') {
    await b.registerAt(a);
    stdout.writeln('PASS: live peer confirmed before stopping it.');
    return;
  }
  final repository = await ChatRepository.open('${a.data}/chat.sqlite3', localFingerprint: a.fingerprint);
  final manifest = File('${a.data}/offline-probe.json');
  try {
    if (args[0] == 'queue') {
      final message = await repository.enqueueText(
        peerFingerprint: b.fingerprint,
        messageId: const Uuid().v4(),
        text: 'Offline queue keeps its identity',
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await manifest.writeAsString(jsonEncode({'conversation': message.conversationId, 'id': message.key.messageId}));
      // A failed connect should remove stale presence after one committed attempt,
      // rather than exhaust all four attempts at 1/2/4-second retry delays.
      await Future<void>.delayed(const Duration(seconds: 16));
      final current = (await repository.listMessages(message.conversationId)).singleWhere((m) => m.key == message.key);
      if (current.attemptCount != 1 || current.deliveryState != DeliveryState.unconfirmed) {
        throw StateError('Expected one retained attempt while peer is down: ${current.attemptCount}/${current.deliveryState}');
      }
      stdout.writeln('PASS: peer stopped; one failed attempt retained after 16 seconds, budget not exhausted.');
    } else if (args[0] == 'recover') {
      final saved = jsonDecode(await manifest.readAsString()) as Map;
      await b.registerAt(a);
      await a.registerAt(b);
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (true) {
        final message = (await repository.listMessages(saved['conversation'] as String)).singleWhere((m) => m.key.messageId == saved['id']);
        if (message.deliveryState == DeliveryState.delivered) {
          if (message.attemptCount != 2) throw StateError('Expected one attempt after rediscovery');
          break;
        }
        if (DateTime.now().isAfter(deadline)) throw StateError('Queued message did not recover');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final receiver = await ChatRepository.open('${b.data}/chat.sqlite3', localFingerprint: b.fingerprint);
      try {
        final conversation = await receiver.ensureConversation(a.fingerprint);
        final received = (await receiver.listMessages(conversation.id)).where((m) => m.key.messageId == saved['id']);
        if (received.length != 1) throw StateError('Expected one deduplicated received message');
      } finally {
        await receiver.close();
      }
      stdout.writeln('PASS: restarted peer rediscovered at actual port ${b.port}; original message delivered once on attempt two.');
    } else {
      throw ArgumentError('queue|recover');
    }
  } finally {
    await repository.close();
  }
}
