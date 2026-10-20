import 'dart:io';

import 'package:localsend_app/config/app_identity.dart';
import 'package:localsend_app/util/shared_preferences/shared_preferences_portable.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// All durable LocalChat state lives here; no LocalSend migration paths are consulted.
/// Optional locations allow callers/tests to initialize an isolated application container.
Future<Directory> resolveLocalChatDataDirectory({
  required bool portable,
  Directory? applicationSupportDirectory,
  String? executablePath,
}) async {
  final Directory directory;
  if (portable) {
    directory = executablePath == null
        ? File(SharedPreferencesPortable().getPath()).parent
        : Directory(path.join(File(executablePath).parent.path, 'localchat-data'));
  } else {
    final Directory root;
    if (applicationSupportDirectory != null) {
      root = applicationSupportDirectory;
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw StateError('APPDATA is unavailable; cannot determine the LocalChat data directory.');
      }
      root = Directory(appData);
    } else {
      root = await getApplicationSupportDirectory();
    }
    directory = Directory(path.join(root.path, AppIdentity.displayName));
  }
  return directory.create(recursive: true);
}
