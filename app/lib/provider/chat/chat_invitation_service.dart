import 'dart:async';

import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/provider/chat/chat_outbox_provider.dart';
import 'package:localsend_app/provider/chat/chat_repository_provider.dart';
import 'package:localsend_app/provider/chat/chat_transport.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as wire;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final chatInvitationProvider = Provider(
  (ref) => ChatInvitationService(
    repository: ref.read(chatRepositoryProvider),
    transport: ref.read(chatTransportProvider),
    outbox: ref.read(chatOutboxProvider),
    resolvePeer: (fp) => ref.read(settingsProvider).https ? ref.read(nearbyDevicesProvider).devices[fp] : null,
  ),
);

class ChatInvitationService {
  final ChatRepository repository;
  final ChatTransport transport;
  final ChatOutboxService outbox;
  final Device? Function(String) resolvePeer;
  String? _activePeer;
  bool _foreground = true;
  bool _disposed = false;
  bool _polling = false;
  int _generation = 0;
  int _step = 0;
  Timer? _timer;
  final _posted = <String>{};
  ChatInvitationService({required this.repository, required this.transport, required this.outbox, required this.resolvePeer});
  Future<void> begin(String fingerprint) async {
    final pending = (await repository.listInvitations(
      peerFingerprint: fingerprint,
    )).where((i) => i.direction == MessageDirection.outgoing && i.status == InvitationStatus.pending);
    final id = pending.isEmpty ? const Uuid().v4() : pending.first.invitationId;
    await repository.beginInvitation(fingerprint, id);
    setActivePeer(fingerprint);
    await pollNow();
  }

  void setActivePeer(String? fingerprint) {
    _activePeer = fingerprint;
    _generation++;
    _step = 0;
    _timer?.cancel();
    _schedule(Duration.zero);
  }

  void setForeground(bool value) {
    _foreground = value;
    _generation++;
    _timer?.cancel();
    if (value) _schedule(Duration.zero);
  }

  void _schedule(Duration delay) {
    if (!_disposed && _foreground && _activePeer != null) {
      _timer = Timer(delay, () {
        unawaited(pollNow());
      });
    }
  }

  Future<void> pollNow() async {
    if (_polling || _disposed || !_foreground || _activePeer == null) return;
    _timer?.cancel();
    _polling = true;
    final fingerprint = _activePeer!;
    final generation = _generation;
    try {
      final device = resolvePeer(fingerprint);
      if (device == null || !device.https || device.fingerprint != fingerprint) return;
      final pending = (await repository.listInvitations(
        peerFingerprint: fingerprint,
      )).where((i) => i.direction == MessageDirection.outgoing && i.status == InvitationStatus.pending);
      for (final invitation in pending.take(1)) {
        final response = _posted.contains(invitation.invitationId)
            ? await transport.inviteStatus(device, invitation.invitationId)
            : await transport.invite(device, invitation.invitationId);
        if (response.invitationId != invitation.invitationId) throw const ChatTransportException('invalid_invitation_ack', retryable: false);
        if (generation != _generation) return;
        _posted.add(invitation.invitationId);
        if (_posted.length > 64) _posted.remove(_posted.first);
        if (response.status != wire.ChatInvitationStatus.pending) {
          await repository.completeOutgoingInvitation(fingerprint, invitation.invitationId, response.status == wire.ChatInvitationStatus.accepted);
          await outbox.wake(peerFingerprint: fingerprint);
        }
      }
    } on ChatTransportException catch (e) {
      if (e.status == 403 && generation == _generation) {
        final pending = (await repository.listInvitations(
          peerFingerprint: fingerprint,
        )).where((i) => i.direction == MessageDirection.outgoing && i.status == InvitationStatus.pending);
        for (final i in pending) {
          await repository.completeOutgoingInvitation(fingerprint, i.invitationId, false);
        }
      }
    } catch (_) {
      /* keep durable pending invitation for later foreground retry */
    } finally {
      _polling = false;
      if (generation == _generation) {
        const delays = [2, 5, 15, 30];
        _schedule(Duration(seconds: delays[_step.clamp(0, 3)]));
        if (_step < 3) _step++;
      } else {
        _schedule(Duration.zero);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
  }
}
