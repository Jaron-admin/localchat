import 'dart:io';

import 'package:localsend_app/util/native/app_data_directory.dart';
import 'package:localsend_app/util/shared_preferences/shared_preferences_file.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('localchat-isolation-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('installed settings and certificate cannot migrate from or overwrite LocalSend', () async {
    final originalDirectory = await Directory(path.join(temporary.path, 'LocalSend')).create();
    final originalSettings = File(path.join(originalDirectory.path, 'settings.json'));
    final originalCertificate = File(path.join(originalDirectory.path, 'certificate.pem'));
    await originalSettings.writeAsString('{"flutter.ls_security_context":"original-device-identity"}');
    await originalCertificate.writeAsString('original certificate bytes');
    final settingsBefore = await originalSettings.readAsBytes();
    final certificateBefore = await originalCertificate.readAsBytes();

    final directory = await resolveLocalChatDataDirectory(portable: false, applicationSupportDirectory: temporary);
    final settings = SharedPreferencesFile(filePath: path.join(directory.path, 'settings.json'));
    expect(await settings.getAll(), isEmpty);
    await settings.setValue('String', 'flutter.ls_security_context', 'new-chat-device-identity');

    expect(directory.path, isNot(originalDirectory.path));
    expect(await originalSettings.readAsBytes(), settingsBefore);
    expect(await originalCertificate.readAsBytes(), certificateBefore);
    final reopened = SharedPreferencesFile(filePath: settings.getPath());
    expect((await reopened.getAll())['flutter.ls_security_context'], 'new-chat-device-identity');
  });

  test('portable data stays beside the executable without reading old portable settings', () async {
    final originalSettings = File(path.join(temporary.path, 'settings.json'));
    await originalSettings.writeAsString('{"flutter.ls_security_context":"original-portable-identity"}');
    final originalBytes = await originalSettings.readAsBytes();

    final directory = await resolveLocalChatDataDirectory(
      portable: true,
      executablePath: path.join(temporary.path, 'localchat.exe'),
    );
    final settings = SharedPreferencesFile(filePath: path.join(directory.path, 'settings.json'));
    await settings.setValue('String', 'flutter.ls_security_context', 'new-portable-identity');

    expect(directory.path, path.join(temporary.path, 'localchat-data'));
    expect(await originalSettings.readAsBytes(), originalBytes);
    expect(await directory.exists(), isTrue);
  });

  test('corrupted settings are reported without silently replacing the device identity', () async {
    final directory = await resolveLocalChatDataDirectory(portable: false, applicationSupportDirectory: temporary);
    final file = File(path.join(directory.path, 'settings.json'));
    await file.writeAsString('{"flutter.ls_security_context": "interrupted');
    final before = await file.readAsBytes();
    final settings = SharedPreferencesFile(filePath: file.path);

    await expectLater(settings.getAll(), throwsFormatException);
    expect(await file.readAsBytes(), before);
  });
}
