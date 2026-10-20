import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/model/stored_security_context.dart';
import 'package:localsend_isolates/util/show_instance.dart';

// These are public, throwaway test identities; never use them in an application.
StoredSecurityContext loadIdentity(String name) => StoredSecurityContext(
  certificate: File('test/fixtures/$name-cert.pem').readAsStringSync(),
  privateKey: File('test/fixtures/$name-key.pem').readAsStringSync(),
  publicKey: '',
  certificateHash: '',
);

void main() {
  for (final matching in [true, false]) {
    test(matching ? 'hands args only to the exact local certificate' : 'impostor receives neither token nor file arguments', () async {
      final localIdentity = loadIdentity('instance');
      final serverIdentity = loadIdentity(matching ? 'instance' : 'impostor');
      final context = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(serverIdentity.certificate))
        ..usePrivateKeyBytes(utf8.encode(serverIdentity.privateKey));
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
      addTearDown(() => server.close(force: true));
      final requests = <String>[];
      server.listen((request) async {
        requests.add('${request.uri} ${await utf8.decodeStream(request)}');
        request.response.statusCode = 200;
        await request.response.close();
      }, onError: (Object _) {});
      final accepted = await notifyRunningInstance(
        securityContext: localIdentity,
        port: server.port,
        https: true,
        showToken: 'private-show-token',
        args: const ['private-file.txt'],
        connectionTimeout: const Duration(seconds: 5),
        responseTimeout: const Duration(seconds: 5),
      );
      expect(accepted, matching);
      if (matching) {
        expect(requests.single, contains('private-file.txt'));
      } else {
        expect(requests, isEmpty);
      }
    });
  }
}
