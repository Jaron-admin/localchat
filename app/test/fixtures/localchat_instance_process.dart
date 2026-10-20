import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/util/native/localchat_instance.dart';

Future<void> main(List<String> args) async {
  final instance = await LocalChatInstance.acquire(Directory(args[0]));
  try {
    if (instance.isOwner) {
      if (args[1] != 'unready') {
        await instance.publishEndpoint(port: 54321);
      }
      stdout.writeln('owner');
      await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
    } else {
      stdout.writeln('follower');
      final port = await instance.waitForEndpoint(timeout: const Duration(milliseconds: 250));
      stdout.writeln('port:$port');
    }
  } finally {
    await instance.close();
  }
}
