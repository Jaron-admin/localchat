import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/rust/api/crypto.dart' as crypto;
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/rust/api/server.dart';
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:uuid/uuid.dart';

void main() {
  late RsHttpServer server;
  late RsHttpClient client;
  late StreamIterator<RsServerEvent> events;
  late int port;
  setUpAll(() async {
    final name = Platform.isWindows
        ? 'rust_lib_localsend_app.dll'
        : Platform.isMacOS
        ? 'librust_lib_localsend_app.dylib'
        : 'librust_lib_localsend_app.so';
    final path = '${Directory.current.path}/../../target/debug/$name';
    await RustLib.init(externalLibrary: ExternalLibrary.open(path));
  });
  setUp(() async {
    final receiver = await crypto.generateSecurityContext();
    final sender = await crypto.generateSecurityContext();
    server = await startServer(
      port: 0,
      tls: TlsConfig(cert: receiver.certificate, privateKey: receiver.privateKey),
      alias: 'test',
      version: '2.2',
      fingerprint: receiver.certificateHash,
      verifyChecksums: true,
    );
    port = await server.port();
    events = StreamIterator(server.listen());
    client = createClient(
      privateKey: sender.privateKey,
      cert: sender.certificate,
      version: LsHttpClientVersion.v2,
      expectedFingerprint: receiver.certificateHash,
    );
  });
  tearDown(() async {
    await server.stop();
    await events.cancel();
  });
  test('real FRB request and reply retain IDs and a late response cannot answer another request', () async {
    final id = const Uuid().v4();
    final request = client.chatDeliver(
      ip: '127.0.0.1',
      port: port,
      payload: ChatMessageDto(version: 1, messageId: id, sentAtMs: 123, text: '真实桥接'),
    );
    expect(await events.moveNext(), true);
    final event = events.current as RsServerEvent_ChatRequest;
    expect((event.operation as ChatOperation_Deliver).field0.messageId, id);
    await expectLater(
      server.respondChatRequest(
        requestId: 'unknown',
        reply: ChatReply.stored(ChatAck(messageId: id, duplicate: false)),
      ),
      throwsA(anything),
    );
    await server.respondChatRequest(
      requestId: event.requestId,
      reply: ChatReply.stored(ChatAck(messageId: id, duplicate: false)),
    );
    expect((await request).messageId, id);
    await expectLater(
      server.respondChatRequest(
        requestId: event.requestId,
        reply: ChatReply.stored(ChatAck(messageId: id, duplicate: false)),
      ),
      throwsA(anything),
    );
  });
  test('core deadline clears the native responder before a late Dart reply', () async {
    final id = const Uuid().v4();
    final request = client.chatDeliver(
      ip: '127.0.0.1',
      port: port,
      payload: ChatMessageDto(version: 1, messageId: id, sentAtMs: 1, text: 'timeout'),
    );
    final result = expectLater(request, throwsA(isA<RsHttpClientError_StatusCode>().having((e) => e.status, 'status', 504)));
    expect(await events.moveNext(), true);
    final event = events.current as RsServerEvent_ChatRequest;
    await result;
    await expectLater(
      server.respondChatRequest(
        requestId: event.requestId,
        reply: ChatReply.stored(ChatAck(messageId: id, duplicate: false)),
      ),
      throwsA(anything),
    );
  });
}
