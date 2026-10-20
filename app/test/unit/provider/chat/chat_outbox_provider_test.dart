import 'dart:io';

import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/provider/chat/chat_outbox_provider.dart';
import 'package:localsend_app/provider/chat/chat_transport.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const owner = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const peer = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

class RecordingTransport implements ChatTransport {
  final ChatRepository repository;
  final sent = <ChatMessage>[];
  bool wrongAck = false;
  String failureCode = 'timeout';
  RecordingTransport(this.repository);
  @override
  Future<ChatDeliveryReceipt> deliver(Device device, ChatMessage message) async {
    final stored = (await repository.listMessages(message.conversationId)).single;
    expect(stored.key, message.key);
    expect(stored.deliveryState, DeliveryState.sending);
    sent.add(message);
    if (wrongAck) return ChatDeliveryReceipt(messageId: 'wrong', verifiedPeerFingerprint: peer, duplicate: false);
    throw ChatTransportException(failureCode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory temp;
  late ChatRepository repository;
  late RecordingTransport transport;
  late ChatOutboxService outbox;
  late DateTime now;
  late ChatMessage message;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('chat-outbox-');
    repository = await ChatRepository.open('${temp.path}/chat.sqlite3', localFingerprint: owner);
    final invitation = const Uuid().v4();
    await repository.recordInvitation(peer, invitation);
    await repository.decideInvitation(peer, invitation, true);
    now = DateTime.fromMillisecondsSinceEpoch(1000);
    message = await repository.enqueueText(peerFingerprint: peer, messageId: const Uuid().v4(), text: 'persist first', sentAtMs: 1000);
    transport = RecordingTransport(repository);
    outbox = ChatOutboxService(
      repository: repository,
      transport: transport,
      resolvePeer: (_) => Device.empty.copyWith(ip: '127.0.0.1', port: 53317, https: true, fingerprint: peer),
      now: () => now,
      automatic: false,
    );
  });
  tearDown(() async {
    await outbox.dispose();
    await repository.close();
    await temp.delete(recursive: true);
  });
  Future<void> tick() async {
    await outbox.wake();
    await outbox.waitForIdle();
  }

  test('four attempts keep ID and persisted budget; paused app does not send', () async {
    outbox.setForeground(false);
    await tick();
    expect(transport.sent, isEmpty);
    outbox.setForeground(true);
    await tick();
    expect(transport.sent.length, 1);
    for (final seconds in [1, 2, 4]) {
      now = now.add(Duration(seconds: seconds));
      await tick();
    }
    expect(transport.sent.length, 4);
    expect(transport.sent.map((m) => m.key).toSet(), {message.key});
    now = now.add(const Duration(days: 1));
    await tick();
    expect(transport.sent.length, 4);
    expect((await repository.listMessages(message.conversationId)).single.deliveryState, DeliveryState.unconfirmed);
  });
  test('wrong acknowledgment never marks delivered', () async {
    transport.wrongAck = true;
    await tick();
    expect((await repository.listMessages(message.conversationId)).single.deliveryState, isNot(DeliveryState.delivered));
  });
  test('a failed connection invalidates presence and preserves retries until rediscovery', () async {
    await outbox.dispose();
    var online = true;
    final device = Device.empty.copyWith(ip: '127.0.0.1', port: 58723, https: true, fingerprint: peer);
    transport.failureCode = 'network';
    outbox = ChatOutboxService(
      repository: repository,
      transport: transport,
      resolvePeer: (_) => online ? device : null,
      onUnavailable: (failedDevice) {
        expect(failedDevice, same(device));
        online = false;
      },
      now: () => now,
      automatic: false,
    );
    await tick();
    expect(online, isFalse);
    now = now.add(const Duration(days: 1));
    await tick();
    expect(transport.sent, hasLength(1));
    expect((await repository.listMessages(message.conversationId)).single.attemptCount, 1);
    online = true;
    await tick();
    expect(transport.sent, hasLength(2));
    expect(transport.sent.last.key, message.key);
  });
}
