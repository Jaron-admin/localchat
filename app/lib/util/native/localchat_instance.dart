import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A desktop process holds the OS lock for its entire lifetime. The lock file
/// is never removed: unlinking it would let two processes lock different files.
class LocalChatInstance {
  final Directory dataDirectory;
  final RandomAccessFile? _lock;
  bool _closed = false;
  int _publication = 0;

  LocalChatInstance._(this.dataDirectory, this._lock);

  bool get isOwner => _lock != null && !_closed;
  File get _endpoint => File('${dataDirectory.path}/instance.json');

  static Future<LocalChatInstance> acquire(Directory dataDirectory) async {
    await dataDirectory.create(recursive: true);
    final lock = await File('${dataDirectory.path}/instance.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive, 0, 1);
    } on FileSystemException catch (error) {
      await lock.close();
      // Lock contention: Windows ERROR_LOCK_VIOLATION, POSIX EAGAIN/EACCES.
      // File-open/permission failures above must propagate as startup errors.
      if (!const [33, 11, 35, 13].contains(error.osError?.errorCode)) rethrow;
      return LocalChatInstance._(dataDirectory, null);
    }
    final instance = LocalChatInstance._(dataDirectory, lock);
    try {
      await instance.clearEndpoint();
      return instance;
    } catch (_) {
      await lock.close();
      rethrow;
    }
  }

  Future<void> publishEndpoint({required int port}) async {
    if (!isOwner) throw StateError('Only the owning LocalChat process can publish its endpoint.');
    if (port < 1 || port > 65535) throw ArgumentError.value(port, 'port');
    final temporary = File('${_endpoint.path}.$pid.${_publication++}.tmp');
    try {
      await temporary.writeAsString(jsonEncode({'version': 1, 'port': port}), flush: true);
      await temporary.rename(_endpoint.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<int> waitForEndpoint({Duration timeout = const Duration(seconds: 2)}) async {
    final watch = Stopwatch()..start();
    while (!_closed) {
      try {
        final value = jsonDecode(await _endpoint.readAsString());
        if (value is Map && value['version'] == 1 && value['port'] is int) {
          final port = value['port'] as int;
          if (port > 0 && port <= 65535) return port;
        }
      } on FileSystemException {
        // The owner has not yet bound the server or is replacing the record.
      } on FormatException {
        // A record from an interrupted old startup is not a usable endpoint.
      }
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(remaining < const Duration(milliseconds: 25) ? remaining : const Duration(milliseconds: 25));
    }
    throw TimeoutException('The existing LocalChat instance is not ready.', timeout);
  }

  Future<void> clearEndpoint() async {
    if (!isOwner) throw StateError('Only the owning LocalChat process can clear its endpoint.');
    if (await _endpoint.exists()) await _endpoint.delete();
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      if (isOwner) await clearEndpoint();
    } finally {
      _closed = true;
      final lock = _lock;
      if (lock != null) {
        try {
          await lock.unlock(0, 1);
        } finally {
          await lock.close();
        }
      }
    }
  }
}
