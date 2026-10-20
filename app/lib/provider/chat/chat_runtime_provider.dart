import 'dart:async';

import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/provider/chat/chat_capabilities_provider.dart';
import 'package:localsend_app/provider/chat/chat_invitation_service.dart';
import 'package:localsend_app/provider/chat/chat_outbox_provider.dart';
import 'package:localsend_app/provider/chat/chat_repository_provider.dart';
import 'package:localsend_app/provider/localchat_instance_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

final chatRuntimeProvider = Provider((ref) => ChatRuntime(ref));

class ChatRuntime {
  final Ref ref;
  StreamSubscription<dynamic>? _discovery;
  final _seen = <String, Device>{};
  final _pendingPeers = <String, Device>{};
  final _knownDevices = <String, Device>{};
  Timer? _presenceTimer;
  bool _refreshingPresence = false;
  bool _savingPeers = false;
  bool _closed = false;
  int _lifecycle = 0;
  Future<void>? _closeFuture;
  ChatRuntime(this.ref);
  void start() {
    if (_discovery != null || _closed) return;
    ref.read(chatOutboxProvider);
    _discovery = ref.stream(nearbyDevicesProvider).listen((event) {
      final devices = ref.read(nearbyDevicesProvider).devices;
      for (final d in devices.values) {
        if (identical(_seen[d.fingerprint], d)) continue;
        _seen[d.fingerprint] = d;
        _knownDevices.remove(d.fingerprint);
        _knownDevices[d.fingerprint] = d;
        if (_knownDevices.length > 64) _knownDevices.remove(_knownDevices.keys.first);
        if (RegExp(r'^[0-9A-F]{64}$').hasMatch(d.fingerprint)) {
          if (_pendingPeers.length >= 256) _pendingPeers.remove(_pendingPeers.keys.first);
          _pendingPeers[d.fingerprint] = d;
        }
      }
      _seen.removeWhere((key, _) => !devices.containsKey(key));
      unawaited(_savePeers());
      unawaited(ref.read(chatOutboxProvider).wake());
    });
    _startPresenceRefresh();
  }

  void _startPresenceRefresh() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_refreshPresence()));
  }

  Future<void> _refreshPresence() async {
    if (_closed || _refreshingPresence) return;
    ref.redux(nearbyDevicesProvider).dispatch(ExpireNearbyDevicesAction());
    _refreshingPresence = true;
    try {
      final settings = ref.read(settingsProvider);
      // Directly recheck known endpoints as well as multicast, so a manually
      // connected peer stays reachable on networks that suppress multicast.
      await ref
          .redux(parentIsolateProvider)
          .dispatchTakeResult(
            IsolateDiscoveryStagedScanAction(
              favorites: [
                for (final d in _knownDevices.values)
                  if (d.ip != null && d.https == settings.https) (d.ip!, d.port),
              ],
              networkInterfaces: const [],
              port: settings.port,
              https: settings.https,
              grace: Duration.zero,
            ),
          )
          .drain<void>();
    } catch (_) {
      // Failed probes cannot renew presence; the next expiry hides stale peers.
    } finally {
      _refreshingPresence = false;
    }
  }

  Future<void> _savePeers() async {
    if (_savingPeers || _closed) return;
    _savingPeers = true;
    try {
      while (_pendingPeers.isNotEmpty && !_closed) {
        final d = _pendingPeers.remove(_pendingPeers.keys.first)!;
        await ref
            .read(chatRepositoryProvider)
            .upsertPeer(
              ChatPeer(
                fingerprint: d.fingerprint,
                alias: d.alias,
                platform: d.deviceModel ?? d.deviceType.name,
                host: d.ip,
                port: d.port,
                lastSeen: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      }
    } catch (_) {
      /* database remains intact; later discovery retries */
    } finally {
      _savingPeers = false;
    }
  }

  void pause() {
    _lifecycle++;
    _presenceTimer?.cancel();
    ref.read(chatOutboxProvider).setForeground(false);
    ref.read(chatInvitationProvider).setForeground(false);
  }

  Future<void> resume() async {
    if (_closed) return;
    final generation = ++_lifecycle;
    ref.read(chatOutboxProvider).setForeground(false);
    try {
      ref.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
      if (!checkPlatformIsDesktop()) {
        await ref.notifier(serverProvider).ensureRunning();
        ref.redux(parentIsolateProvider).dispatch(IsolateDiscoveryRestartAction());
      }
      if (generation != _lifecycle || _closed) return;
      ref.read(chatOutboxProvider).setForeground(true);
      ref.read(chatInvitationProvider).setForeground(true);
      _startPresenceRefresh();
      unawaited(_refreshPresence());
    } catch (_) {
      /* a failed resume must not send with stale network state */
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closed = true;
    pause();
    await _discovery?.cancel();
    ref.read(chatInvitationProvider).dispose();
    try {
      await ref.read(chatOutboxProvider).dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await ref.notifier(serverProvider).stopServer().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await ref.read(chatRepositoryProvider).close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    await ref.read(localChatInstanceProvider)?.close();
    ref.redux(parentIsolateProvider).dispatch(IsolateDisposeAction());
  }

  void clearCapabilityCache() => ref.read(chatCapabilitiesProvider).clear();
}
