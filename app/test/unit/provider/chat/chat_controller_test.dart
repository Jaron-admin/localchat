import 'dart:async';

import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/provider/network/server/controller/chat_controller.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/rust/api/model.dart' as wire;
import 'package:test/test.dart';

class DeferredRepository implements ChatRepository {
  final commit = Completer<IncomingCommit>();
  @override
  Future<IncomingCommit> commitIncoming({
    required String verifiedFingerprint,
    required String messageId,
    required String text,
    required int sentAtMs,
    required int receivedAtMs,
  }) => commit.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  HttpServerChatRequestEvent request() => HttpServerChatRequestEvent(
    requestId: 'request',
    ip: '127.0.0.1',
    peerFingerprint: 'verified',
    operation: wire.ChatOperation.deliver(const wire.ChatMessageDto(version: 1, messageId: 'message', sentAtMs: 1, text: 'hello')),
  );
  test('no ACK until commit returns; a durable receipt is bound to the request ID', () async {
    final repository = DeferredRepository();
    final replies = <(String, wire.ChatReply)>[];
    final controller = ChatController(
      repository,
      respond: (id, reply) async {
        replies.add((id, reply));
      },
    );
    final pending = controller.onRequest(request());
    await Future<void>.delayed(Duration.zero);
    expect(replies, isEmpty);
    repository.commit.complete(const IncomingCommit(key: MessageKey('verified', 'message'), duplicate: false));
    await pending;
    expect(replies.single.$1, 'request');
    expect(replies.single.$2, isA<wire.ChatReply_Stored>());
  });
  test('storage failure returns unavailable and never Stored', () async {
    final repository = DeferredRepository();
    final replies = <wire.ChatReply>[];
    final controller = ChatController(
      repository,
      respond: (_, reply) async {
        replies.add(reply);
      },
    );
    final pending = controller.onRequest(request());
    repository.commit.completeError(const ChatStorageException('unavailable'));
    await pending;
    expect(replies.single, wire.ChatReply.rejected(wire.ChatErrorCode.unavailable));
  });
}
