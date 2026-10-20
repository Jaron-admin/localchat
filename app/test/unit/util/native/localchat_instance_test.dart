import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/util/native/localchat_instance.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() async => directory = await Directory.systemTemp.createTemp('localchat-instance-'));
  tearDown(() async => directory.delete(recursive: true));

  Future<(Process, StreamIterator<String>)> start(String mode) async {
    final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
    var sdkParent = File(Platform.resolvedExecutable).parent;
    // flutter_tester lives below bin/cache/artifacts/engine; the real Dart VM
    // lives below the same cache, and can launch a separate OS process.
    while (!File('${sdkParent.path}/dart-sdk/bin/$executableName').existsSync()) {
      if (sdkParent.parent.path == sdkParent.path) throw StateError('Cannot locate the test SDK Dart VM.');
      sdkParent = sdkParent.parent;
    }
    final process = await Process.start(
      '${sdkParent.path}/dart-sdk/bin/$executableName',
      ['--disable-dart-dev', 'test/fixtures/localchat_instance_process.dart', directory.path, mode],
    );
    final errors = <String>[];
    process.stderr.transform(utf8.decoder).listen(errors.add);
    final lines = StreamIterator(process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    addTearDown(() async {
      process.kill();
      await process.exitCode;
      await lines.cancel();
    });
    expect(await lines.moveNext().timeout(const Duration(seconds: 30)), isTrue, reason: errors.join());
    return (process, lines);
  }

  test('separate processes share one owner and may restart after release', () async {
    final (owner, ownerLines) = await start('hold');
    expect(ownerLines.current, 'owner');
    final (follower, followerLines) = await start('follow');
    expect(followerLines.current, 'follower');
    expect(await followerLines.moveNext(), isTrue);
    expect(followerLines.current, 'port:54321');
    expect(await follower.exitCode, 0);
    owner.stdin.writeln('release');
    expect(await owner.exitCode, 0);

    final (restarted, restartLines) = await start('hold');
    expect(restartLines.current, 'owner');
    restarted.stdin.writeln('release');
    expect(await restarted.exitCode, 0);
  });

  test('held lock without endpoint times out without becoming a second owner', () async {
    final (owner, lines) = await start('unready');
    expect(lines.current, 'owner');
    final follower = await LocalChatInstance.acquire(directory);
    expect(follower.isOwner, isFalse);
    await expectLater(follower.waitForEndpoint(timeout: const Duration(milliseconds: 100)), throwsA(isA<TimeoutException>()));
    await follower.close();
    owner.stdin.writeln('release');
    expect(await owner.exitCode, 0);
  });

  test('new owner discards stale endpoint and validates published port', () async {
    await File('${directory.path}/instance.json').writeAsString('{"port":12345}');
    final owner = await LocalChatInstance.acquire(directory);
    addTearDown(owner.close);
    expect(owner.isOwner, isTrue);
    expect(File('${directory.path}/instance.json').existsSync(), isFalse);
    await expectLater(owner.publishEndpoint(port: 0), throwsArgumentError);
    await owner.publishEndpoint(port: 65535);
    expect(await owner.waitForEndpoint(), 65535);
    await owner.clearEndpoint();
    expect(File('${directory.path}/instance.json').existsSync(), isFalse);
  });
}
