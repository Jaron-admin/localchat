// Run against disposable, independently launched app configurations only.
// dart run tool/localchat_runtime_probe.dart exercise|verify <dataA> <dataB>
import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:uuid/uuid.dart';

class Peer {
  final String data;
  final Map<String, dynamic> identity;
  final int port;
  Peer(this.data, this.identity, this.port);
  String get fingerprint => identity['certificateHash'] as String;
  static Peer load(String data) {
    final settings = jsonDecode(File('$data/settings.json').readAsStringSync()) as Map;
    final identity = jsonDecode(settings['flutter.ls_security_context'] as String) as Map<String, dynamic>;
    final endpoint = jsonDecode(File('$data/instance.json').readAsStringSync()) as Map;
    return Peer(data, identity, endpoint['port'] as int);
  }

  Future<(int, Map)> request(Peer receiver, String route, {Map? body}) async {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity['certificate'] as String))
      ..usePrivateKeyBytes(utf8.encode(identity['privateKey'] as String));
    final expected = base64Decode((receiver.identity['certificate'] as String).replaceAll(RegExp(r'-----[^-]+-----|\s'), ''));
    final client = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = (_) => 'DIRECT';
    client.badCertificateCallback = (certificate, host, port) {
      if (host != '127.0.0.1' || port != receiver.port || certificate.der.length != expected.length) return false;
      var difference = 0;
      for (var i = 0; i < expected.length; i++) {
        difference |= certificate.der[i] ^ expected[i];
      }
      return difference == 0;
    };
    try {
      final request = await client.openUrl(body == null ? 'GET' : 'POST', Uri.parse('https://127.0.0.1:${receiver.port}$route'));
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 10));
      return (response.statusCode, jsonDecode(await utf8.decodeStream(response)) as Map);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> registerAt(Peer receiver) async {
    final response = await request(
      receiver,
      '/api/localsend/v2/register',
      body: {
        'alias': 'LocalChat runtime probe',
        'version': '2.2',
        'fingerprint': fingerprint,
        'port': port,
        'protocol': 'https',
        'deviceType': 'desktop',
        'download': false,
      },
    );
    if (response.$1 != 200) throw StateError('Registration failed ${response.$1}');
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 3) throw ArgumentError('exercise|verify dataA dataB');
  final a = Peer.load(args[1]), b = Peer.load(args[2]);
  if (a.fingerprint == b.fingerprint) throw StateError('Fixtures must have distinct identities');
  final repoA = await ChatRepository.open('${a.data}/chat.sqlite3', localFingerprint: a.fingerprint);
  final repoB = await ChatRepository.open('${b.data}/chat.sqlite3', localFingerprint: b.fingerprint);
  final manifest = File('${a.data}/runtime-probe.json');
  try {
    if (args[0] == 'exercise') {
      for (final (repo, peer) in [(repoA, b), (repoB, a)]) {
        final invitation = const Uuid().v4();
        await repo.recordInvitation(peer.fingerprint, invitation);
        await repo.decideInvitation(peer.fingerprint, invitation, true);
      }
      // Real certificate-authenticated registration populates each application's
      // discovery store. It also makes loopback testing independent of router multicast policy.
      await a.registerAt(b);
      await b.registerAt(a);
      final now = DateTime.now().millisecondsSinceEpoch;
      final messageA = await repoA.enqueueText(peerFingerprint: b.fingerprint, messageId: const Uuid().v4(), text: 'A → B 你好 👋', sentAtMs: now);
      final messageB = await repoB.enqueueText(peerFingerprint: a.fingerprint, messageId: const Uuid().v4(), text: 'B → A 持久化', sentAtMs: now);
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (true) {
        final rowsA = await repoA.listMessages(messageA.conversationId);
        final rowsB = await repoB.listMessages(messageB.conversationId);
        if (rowsA.length == 2 &&
            rowsB.length == 2 &&
            rowsA.every((m) => m.deliveryState == DeliveryState.delivered) &&
            rowsB.every((m) => m.deliveryState == DeliveryState.delivered)) {
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw StateError(
            'Real app delivery did not complete: A=${rowsA.map((m) => '${m.deliveryState}/${m.attemptCount}/${m.lastError}').join(',')}; B=${rowsB.map((m) => '${m.deliveryState}/${m.attemptCount}/${m.lastError}').join(',')}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final duplicate = await a.request(
        b,
        '/api/localchat/v1/messages',
        body: {'version': 1, 'messageId': messageA.key.messageId, 'sentAtMs': now, 'text': messageA.text},
      );
      if (duplicate.$1 != 200 || duplicate.$2['duplicate'] != true) throw StateError('Retry did not return duplicate receipt');
      await manifest.writeAsString(jsonEncode({'a': messageA.key.messageId, 'b': messageB.key.messageId}));
      stdout.writeln('PASS: two real app processes delivered text in both directions through their outboxes and SQLite controllers.');
      stdout.writeln('PASS: repeated HTTPS message returned duplicate=true; original content was not duplicated.');
    } else if (args[0] == 'verify') {
      final ids = jsonDecode(await manifest.readAsString()) as Map;
      final rowsA = await repoA.listMessages((await repoA.ensureConversation(b.fingerprint)).id);
      final rowsB = await repoB.listMessages((await repoB.ensureConversation(a.fingerprint)).id);
      for (final rows in [rowsA, rowsB]) {
        if (rows.length != 2 ||
            rows.any((m) => m.deliveryState != DeliveryState.delivered) ||
            !rows.map((m) => m.key.messageId).toSet().containsAll([ids['a'], ids['b']])) {
          throw StateError('Restart lost or duplicated persisted history');
        }
      }
      final caps = await a.request(b, '/api/localchat/v1/capabilities');
      if (caps.$1 != 200) throw StateError('Restarted server is not responding');
      stdout.writeln('PASS: after terminating and restarting both app processes, both histories contain exactly the two delivered messages.');
    } else {
      throw ArgumentError('Unknown mode');
    }
  } finally {
    await repoA.close();
    await repoB.close();
  }
}
