import 'dart:async';

import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/provider/chat/chat_repository_provider.dart';
import 'package:localsend_app/provider/chat/chat_transport.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

final chatOutboxProvider = Provider(
  (ref) => ChatOutboxService(
    repository: ref.read(chatRepositoryProvider),
    transport: ref.read(chatTransportProvider),
    resolvePeer: (fingerprint) => ref.read(settingsProvider).https ? ref.read(nearbyDevicesProvider).devices[fingerprint] : null,
    onUnavailable: (device) => ref.redux(nearbyDevicesProvider).dispatch(MarkDeviceUnavailableAction(device)),
  ),
);

class ChatOutboxService {
  final ChatRepository repository;
  final ChatTransport transport;
  final Device? Function(String) resolvePeer;
  final void Function(Device)? onUnavailable;
  final DateTime Function() now;
  final bool automatic;
  final _jobs = <String, Future<void>>{};
  Timer? _timer;
  StreamSubscription<ChatChange>? _subscription;
  bool _foreground = true;
  bool _disposed = false;
  Future<void>? _pumping;
  ChatOutboxService({
    required this.repository,
    required this.transport,
    required this.resolvePeer,
    this.onUnavailable,
    DateTime Function()? now,
    this.automatic = true,
  }) : now = now ?? DateTime.now {
    if (automatic) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        unawaited(wake());
      });
      _subscription = repository.changes.listen((_) {
        unawaited(wake());
      });
    }
  }
  void setForeground(bool value) {
    _foreground = value;
    if (value && automatic) unawaited(wake());
  }

  Future<void> wake({String? peerFingerprint}) {
    if (_disposed || !_foreground) return Future.value();
    return _pumping ??= _pump().whenComplete(() {
      _pumping = null;
    });
  }

  Future<void> _pump() async {
    try {
      final due = await repository.loadDueOutbox(now());
      for (final message in due) {
        if (_disposed || !_foreground || _jobs.length >= 4) break;
        if (_jobs.containsKey(message.peerFingerprint)) continue;
        final device = resolvePeer(message.peerFingerprint);
        if (device == null || device.fingerprint != message.peerFingerprint || !device.https || device.ip == null) continue;
        final job = _deliver(device, message).whenComplete(() {
          // ignore: discarded_futures
          _jobs.remove(message.peerFingerprint);
          if (automatic) unawaited(wake());
        });
        _jobs[message.peerFingerprint] = job;
      }
    } catch (_) {
      /* unavailable storage: keep queue durable, never invent delivery */
    }
  }

  Future<void> _deliver(Device device, ChatMessage message) async {
    try {
      if (!await repository.tryStartAttempt(message.key, now())) return;
      if (!_foreground || _disposed) throw const ChatTransportException('interrupted');
      final receipt = await transport.deliver(device, message);
      if (receipt.messageId != message.key.messageId || receipt.verifiedPeerFingerprint != message.peerFingerprint) {
        throw const ChatTransportException('invalid_ack', retryable: false);
      }
      await repository.recordDelivery(message.key, verifiedPeerFingerprint: receipt.verifiedPeerFingerprint);
    } catch (error) {
      final failure = error is ChatTransportException ? error : const ChatTransportException('unavailable');
      if (failure.code == 'network' || failure.code == 'timeout') onUnavailable?.call(device);
      try {
        await repository.recordAttemptFailure(message.key, DeliveryFailure(retryable: failure.retryable, code: failure.code, occurredAt: now()));
      } catch (_) {
        /* COMMIT failed: recovery retains the persisted attempt budget */
      }
    }
  }

  Future<void> retry(MessageKey key) async {
    await repository.scheduleManualRetry(key, now());
    await wake();
  }

  Future<void> waitForIdle() async {
    while (true) {
      await _pumping;
      if (_jobs.isEmpty) return;
      await Future.wait(_jobs.values.toList());
      await wake();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _foreground = false;
    _timer?.cancel();
    await _subscription?.cancel();
    // Network requests have their own 12s deadline. Shutdown callers may impose
    // a shorter outer bound; each attempt was committed before transmission.
    await waitForIdle();
  }
}
