import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/model/chat/chat_conversation.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/provider/chat/chat_capabilities_provider.dart';
import 'package:localsend_app/provider/chat/chat_invitation_service.dart';
import 'package:localsend_app/provider/chat/chat_outbox_provider.dart';
import 'package:localsend_app/provider/chat/chat_repository_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart' hide ChangeNotifier;
import 'package:uuid/uuid.dart';

final chatViewProvider = Provider(
  (ref) => ChatViewService(
    repository: ref.read(chatRepositoryProvider),
    outbox: ref.read(chatOutboxProvider),
    invitations: ref.read(chatInvitationProvider),
    capabilities: ref.read(chatCapabilitiesProvider),
    resolvePeer: (fp) => ref.read(nearbyDevicesProvider).devices[fp],
    encryptionEnabled: () => ref.read(settingsProvider).https,
  )..start(),
);

/// Contains presentation snapshots only; SQLite remains the authority for every permission and message.
class ChatViewService extends ChangeNotifier {
  final ChatRepository repository;
  final ChatOutboxService outbox;
  final ChatInvitationService invitations;
  final ChatCapabilitiesService capabilities;
  final Device? Function(String) resolvePeer;
  final bool Function() encryptionEnabled;
  List<ChatConversation> conversations = [];
  Map<String, ChatPeer> peers = {};
  List<ChatInvitation> requests = [];
  String? selectedId;
  int selectionRevision = 0;
  bool loading = true;
  bool failed = false;
  bool _disposed = false;
  bool _again = false;
  Future<void>? _refreshing;
  StreamSubscription<ChatChange>? _subscription;
  ChatViewService({
    required this.repository,
    required this.outbox,
    required this.invitations,
    required this.capabilities,
    required this.resolvePeer,
    required this.encryptionEnabled,
  });

  void start() {
    _subscription ??= repository.changes.listen((_) => unawaited(refresh()));
    unawaited(refresh());
  }

  Future<void> refresh() {
    _again = true;
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    while (_again && !_disposed) {
      _again = false;
      try {
        final rows = await repository.listConversations();
        final snapshot = <String, ChatPeer>{};
        // Bounded batches avoid flooding the repository's 256-command mailbox.
        for (final row in rows) {
          final peer = await repository.getPeer(row.peerFingerprint);
          if (peer != null) snapshot[peer.fingerprint] = peer;
        }
        final invites = await repository.listInvitations();
        if (_disposed) return;
        conversations = rows;
        peers = snapshot;
        requests = invites;
        failed = false;
      } catch (_) {
        failed = true;
      }
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void select(String id) {
    selectedId = id;
    selectionRevision++;
    notifyListeners();
  }

  Future<String> openPeer(String fingerprint) async {
    final device = resolvePeer(fingerprint);
    if (device != null) {
      await repository.upsertPeer(
        ChatPeer(
          fingerprint: fingerprint,
          alias: device.alias,
          host: device.ip,
          port: device.port,
          platform: device.deviceModel ?? device.deviceType.name,
          lastSeen: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    final conversation = await repository.ensureConversation(fingerprint);
    await refresh();
    select(conversation.id);
    return conversation.id;
  }

  Future<void> sendText(String conversationId, String text) async {
    if (!encryptionEnabled()) throw const ChatStorageException('encryption_required');
    if (text.trim().isEmpty || utf8.encode(text).length > 32768) throw const ChatStorageException('invalid_text');
    final conversation = conversations.firstWhere((c) => c.id == conversationId);
    await repository.enqueueText(
      peerFingerprint: conversation.peerFingerprint,
      messageId: const Uuid().v4(),
      text: text,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    unawaited(outbox.wake(peerFingerprint: conversation.peerFingerprint));
  }

  Future<void> setOwnDevice(String fingerprint, bool value) => repository.setOwnDevice(fingerprint, value);
  Future<void> revoke(String fingerprint, {required bool block}) => repository.revokePermission(fingerprint, block: block);
  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
