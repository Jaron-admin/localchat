// Disposable Windows runtime fixture only. No production debug endpoint.
// dart run tool/localchat_file_runtime_probe.dart exercise|verify dataA dataB
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:uuid/uuid.dart';

import 'localchat_runtime_probe.dart' show Peer;

Future<HttpClient> pinnedClient(Peer sender, Peer receiver) async {
  final context = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(sender.identity['certificate'] as String))
    ..usePrivateKeyBytes(utf8.encode(sender.identity['privateKey'] as String));
  final expected = base64Decode((receiver.identity['certificate'] as String).replaceAll(RegExp(r'-----[^-]+-----|\s'), ''));
  return HttpClient(context: context)
    ..findProxy = ((_) => 'DIRECT')
    ..badCertificateCallback = (cert, host, port) =>
        host == '127.0.0.1' && port == receiver.port && sha256.convert(cert.der) == sha256.convert(expected);
}

Future<void> main(List<String> args) async {
  final a = Peer.load(args[1]), b = Peer.load(args[2]);
  final ra = await ChatRepository.open('${a.data}/chat.sqlite3', localFingerprint: a.fingerprint);
  final rb = await ChatRepository.open('${b.data}/chat.sqlite3', localFingerprint: b.fingerprint);
  final manifest = File('${a.data}/file-probe.json');
  try {
    if (args[0] == 'verify') {
      final ids = jsonDecode(await manifest.readAsString()) as Map;
      final files = await rb.listAttachments(MessageKey(a.fingerprint, ids['message'] as String));
      if (files.length != 1 || files.single.state != AttachmentState.complete || !await File(files.single.localPath!).exists()) {
        throw StateError('Attachment history or saved file lost after restart');
      }
      stdout.writeln('PASS: restarted app retained the completed file card and saved file.');
      return;
    }
    await a.registerAt(b);
    await b.registerAt(a);
    final messageId = const Uuid().v4(), transferId = const Uuid().v4(), fileId = const Uuid().v4();
    const chunkCount = 128;
    final chunk = Uint8List.fromList(List.generate(1024 * 1024, (i) => i % 251));
    final prepare = await a.request(
      b,
      '/api/localsend/v2/prepare-upload',
      body: {
        'info': {'alias': 'LocalChat file fixture', 'version': '2.2', 'fingerprint': a.fingerprint, 'port': a.port, 'protocol': 'https'},
        'files': {
          fileId: {'id': fileId, 'fileName': 'localchat-128MiB.bin', 'size': chunk.length * chunkCount, 'fileType': 'application/octet-stream'},
        },
        'localchat': {
          'messageId': messageId,
          'transferId': transferId,
          'attachments': {fileId: const Uuid().v4()},
        },
      },
    );
    if (prepare.$1 != 200) throw StateError('Prepare failed: ${prepare.$1}');
    final client = await pinnedClient(a, b);
    var finished = false;
    final upload = () async {
      try {
        final uri = Uri(
          scheme: 'https',
          host: '127.0.0.1',
          port: b.port,
          path: '/api/localsend/v2/upload',
          queryParameters: {
            'sessionId': prepare.$2['sessionId'] as String,
            'fileId': fileId,
            'token': (prepare.$2['files'] as Map)[fileId] as String,
          },
        );
        final request = await client.postUrl(uri);
        request.contentLength = chunk.length * chunkCount;
        request.bufferOutput = false;
        for (var i = 0; i < chunkCount; i++) {
          request.add(chunk);
          await request.flush();
          await Future<void>.delayed(const Duration(milliseconds: 35));
        }
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode != 200) throw StateError('Upload failed: ${response.statusCode}');
      } finally {
        finished = true;
        client.close(force: true);
      }
    }();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final messages = [
      await ra.enqueueText(
        peerFingerprint: b.fingerprint,
        messageId: const Uuid().v4(),
        text: 'A during 128 MiB transfer',
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      await rb.enqueueText(
        peerFingerprint: a.fingerprint,
        messageId: const Uuid().v4(),
        text: 'B during 128 MiB transfer',
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (true) {
      final aa = await ra.listMessages(messages[0].conversationId), bb = await rb.listMessages(messages[1].conversationId);
      final delivered = aa.where((m) => messages.any((sent) => sent.key == m.key)).toList();
      final deliveredB = bb.where((m) => messages.any((sent) => sent.key == m.key)).toList();
      if (delivered.length == 2 && deliveredB.length == 2 && [...delivered, ...deliveredB].every((m) => m.deliveryState == DeliveryState.delivered)) {
        break;
      }
      if (DateTime.now().isAfter(deadline)) throw StateError('Chat stalled during file transfer');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (finished) throw StateError('Transfer ended before concurrency could be demonstrated');
    stdout.writeln('PASS: both real app outboxes delivered text while the 128 MiB upload was still in flight.');
    await upload;
    List<ChatAttachment> saved;
    do {
      saved = await rb.listAttachments(MessageKey(a.fingerprint, messageId));
      if (saved.length == 1 && saved.single.state == AttachmentState.complete) break;
      if (DateTime.now().isAfter(deadline)) throw StateError('File card never reached saved');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    } while (true);
    final actual = await sha256.bind(File(saved.single.localPath!).openRead()).first;
    final expected = await sha256.bind(Stream.fromIterable(List.filled(chunkCount, chunk))).first;
    if (actual != expected || await File(saved.single.localPath!).length() != chunk.length * chunkCount) throw StateError('File content mismatch');
    await manifest.writeAsString(jsonEncode({'message': messageId}));
    stdout.writeln('PASS: actual receive engine saved 128 MiB byte-for-byte and persisted its completed attachment card.');
  } finally {
    await ra.close();
    await rb.close();
  }
}
