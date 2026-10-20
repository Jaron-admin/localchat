import 'dart:async';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/model/chat/chat_transfer_context.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/chat/chat_page_vm.dart';
import 'package:localsend_app/provider/chat/chat_capabilities_provider.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/chat/chat_composer.dart';
import 'package:localsend_app/widget/chat/chat_live_attachment.dart';
import 'package:localsend_app/widget/chat/chat_message_bubble.dart';
import 'package:localsend_app/widget/chat/peer_address_header.dart';
import 'package:localsend_app/widget/chat/transfer_notice_banner.dart';
import 'package:localsend_app/widget/dialogs/chat_invitation_dialog.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final bool embedded;
  final bool active;
  const ChatPage({required this.conversationId, this.embedded = false, this.active = true, super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with Refena {
  ChatViewService? _service;
  final _messages = <int, ChatMessage>{};
  final _attachments = <MessageKey, List<ChatAttachment>>{};
  Set<String> _features = {};
  bool _picking = false;
  ChatCapabilityKind _capability = ChatCapabilityKind.unknown;
  String? _probeKey;
  bool _loading = true, _failed = false, _hasOlder = true, _busy = false, _reload = false;
  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      _service = ref.read(chatViewProvider);
      _service!.addListener(_changed);
      _changed();
    });
  }

  void _changed() {
    if (mounted) {
      unawaited(_load());
      setState(() {});
    }
  }

  ChatPeer? get _peer {
    for (final c in _service?.conversations ?? []) {
      if (c.id == widget.conversationId) return _service!.peers[c.peerFingerprint];
    }
    return null;
  }

  Future<void> _load({bool older = false}) async {
    if (_service == null) return;
    if (_busy) {
      _reload = true;
      return;
    }
    _busy = true;
    try {
      final repository = _service!.repository;
      final knownNewest = _messages.isEmpty ? null : _messages.keys.reduce((a, b) => a > b ? a : b);
      int? before = older && _messages.isNotEmpty ? _messages.keys.reduce((a, b) => a < b ? a : b) : null;
      do {
        final rows = await repository.listMessages(widget.conversationId, beforeSequence: before);
        if (!mounted) return;
        for (final row in rows) {
          _messages[row.localSequence] = row;
        }
        if (older || knownNewest == null) _hasOlder = rows.length == 50;
        if (older || knownNewest == null || rows.length < 50 || rows.last.localSequence <= knownNewest) break;
        before = rows.last.localSequence;
      } while (true);
      // Pending messages already loaded may have changed state outside the most recent page.
      // Reload their pages so late ACKs never leave an old bubble stuck at 'sending'.
      final pending = _messages.values
          .where(
            (m) =>
                m.direction == MessageDirection.outgoing &&
                {DeliveryState.queued, DeliveryState.sending, DeliveryState.unconfirmed}.contains(m.deliveryState),
          )
          .toList();
      for (final m in pending) {
        if (knownNewest == null || m.localSequence >= knownNewest - 50) continue;
        final rows = await repository.listMessages(widget.conversationId, beforeSequence: m.localSequence + 1, limit: 1);
        if (rows.isNotEmpty) _messages[rows.single.localSequence] = rows.single;
      }
      if (!mounted) return;
      for (final message in _messages.values.where((m) => m.kind == MessageKind.attachment)) {
        _attachments[message.key] = await repository.listAttachments(message.key);
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = false;
      });
      final conversation = _service!.conversations.where((c) => c.id == widget.conversationId).firstOrNull;
      if (widget.active && (ModalRoute.of(context)?.isCurrent ?? true) && (conversation?.unreadCount ?? 0) > 0 && _messages.isNotEmpty) {
        await repository.markConversationRead(widget.conversationId, _messages.keys.reduce((a, b) => a > b ? a : b));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    } finally {
      _busy = false;
      if (_reload && mounted) {
        _reload = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _probe(String fingerprint, String key) async {
    final device = _service!.resolvePeer(fingerprint);
    if (device == null) return;
    final capability = await _service!.capabilities.probe(device);
    if (mounted && _probeKey == key) {
      setState(() {
        _capability = capability.kind;
        _features = capability.features;
      });
    }
  }

  Future<void> _attach(ChatPeer peer) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final files = <CrossFile>[];
      if (checkPlatform([TargetPlatform.android])) {
        for (final file in await android_channel.pickFilesAndroid() ?? []) {
          files.add(await CrossFileConverters.convertFileInfo(file));
        }
      } else {
        for (final file in await file_selector.openFiles()) {
          files.add(await CrossFileConverters.convertXFile(file));
        }
      }
      if (!mounted || files.isEmpty) return;
      final device = _service!.resolvePeer(peer.fingerprint);
      if (device == null) throw StateError('Peer is offline');
      // This future includes the full transfer; let the composer remain usable.
      unawaited(
        _action(
          () => ref
              .notifier(sendProvider)
              .startSession(
                target: device,
                files: files,
                background: true,
                chatContext: ChatTransferContext(conversationId: widget.conversationId, messageId: const Uuid().v4(), transferId: const Uuid().v4()),
              ),
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.chat.actionFailed)));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.chat.actionFailed)));
    }
  }

  Future<void> _review(ChatPeer peer, ChatInvitation invitation) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ChatInvitationDialog(peer: peer, invitation: invitation),
    );
    if (result != null && mounted) {
      await _action(() => _service!.repository.decideInvitation(invitation.peerFingerprint, invitation.invitationId, result));
    }
  }

  Future<void> _details(ChatPeer peer) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t.chat.details),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer.alias),
                Text(t.chat.fingerprint),
                SelectableText(peer.fingerprint),
              ],
            ),
          ),
          CheckboxListTile(title: Text(t.chat.ownDevice), value: peer.isOwnDevice, onChanged: (_) => Navigator.pop(context, 'own')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'revoke'), child: Text(t.chat.revoke)),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'block'), child: Text(t.chat.block)),
        ],
      ),
    );
    if (action == 'own') await _action(() => _service!.setOwnDevice(peer.fingerprint, !peer.isOwnDevice));
    if (action == 'revoke' || action == 'block') await _action(() => _service!.revoke(peer.fingerprint, block: action == 'block'));
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) unawaited(_load());
  }

  @override
  void dispose() {
    _service?.removeListener(_changed);
    _service?.invitations.setActivePeer(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peer = _peer;
    if (peer == null) {
      final content = Center(
        child: _service?.failed == true
            ? TextButton(onPressed: _service!.refresh, child: Text(t.chat.loadFailed))
            : const CircularProgressIndicator(),
      );
      return widget.embedded
          ? content
          : Scaffold(
              appBar: AppBar(title: Text(t.chat.title)),
              body: content,
            );
    }
    final device = ref.watch(nearbyDevicesProvider).devices[peer.fingerprint];
    final encryption = ref.watch(settingsProvider).https;
    final key = '${device?.ip}|${device?.port}|${device?.https}|$encryption';
    if (_probeKey != key) {
      _probeKey = key;
      _capability = ChatCapabilityKind.unknown;
      _features = {};
      if (encryption && device != null) unawaited(_probe(peer.fingerprint, key));
    }
    // Only an active conversation polls its durable invitation.
    final activeKey = widget.active ? peer.fingerprint : null;
    if (_activeInvitation != activeKey) {
      _activeInvitation = activeKey;
      _service!.invitations.setActivePeer(activeKey);
    }
    final invitation = _service!.requests
        .where((i) => i.peerFingerprint == peer.fingerprint && i.direction == MessageDirection.incoming && i.status == InvitationStatus.pending)
        .firstOrNull;
    final vm = ChatPageVm(
      peer: peer,
      online: device != null,
      encryptionEnabled: encryption,
      capability: _capability,
      messages: _messages.values.toList()..sort((a, b) => b.localSequence.compareTo(a.localSequence)),
      invitation: invitation,
      hasOlder: _hasOlder,
      loading: _loading,
      failed: _failed,
    );
    final content = ChatConversationView(
      vm: vm,
      onSend: (text) => _service!.sendText(widget.conversationId, text),
      onAttach: !_picking && vm.canSend && vm.online && _features.contains('file-ref') ? () => _attach(peer) : null,
      attachmentBuilder: (message) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final file in _attachments[message.key] ?? <ChatAttachment>[])
            ChatLiveAttachment(
              key: ValueKey(file.attachmentId),
              file: file,
              outgoing: message.direction == MessageDirection.outgoing,
              onReselect: !_picking && vm.canSend && vm.online && _features.contains('file-ref') ? () => _attach(peer) : null,
            ),
        ],
      ),
      onOlder: () => _load(older: true),
      onRefresh: () async {
        _service!.capabilities.clear();
        _probeKey = null;
        await _load();
        if (mounted) setState(() {});
      },
      onInvite: () => _action(() => _service!.invitations.begin(peer.fingerprint)),
      onReview: invitation == null ? null : () => _review(peer, invitation),
      onDetails: () => _details(peer),
      onRetry: (message) => _action(() => _service!.repository.scheduleManualRetry(message.key, DateTime.now())),
    );
    return widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(title: Text(t.chat.title)),
            body: Column(
              children: [
                const TransferNoticeBanner(),
                Expanded(child: content),
              ],
            ),
          );
  }

  String? _activeInvitation;
}

/// Pure rendering surface used by native widget tests as well as both layouts.
class ChatConversationView extends StatelessWidget {
  final ChatPageVm vm;
  final Future<void> Function(String) onSend;
  final VoidCallback onOlder, onRefresh, onInvite, onDetails;
  final VoidCallback? onReview, onAttach;
  final void Function(ChatMessage) onRetry;
  final Widget Function(ChatMessage)? attachmentBuilder;
  const ChatConversationView({
    required this.vm,
    required this.onSend,
    required this.onOlder,
    required this.onRefresh,
    required this.onInvite,
    required this.onDetails,
    required this.onRetry,
    this.onReview,
    this.onAttach,
    this.attachmentBuilder,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final peer = vm.peer;
    String? notice;
    if (!vm.encryptionEnabled) {
      notice = t.chat.encryptionRequired;
    } else if (vm.capability == ChatCapabilityKind.encryptionRequired) {
      notice = t.chat.peerEncryptionRequired;
    } else if (vm.capability == ChatCapabilityKind.filesOnly) {
      notice = t.chat.filesOnly;
    } else if (peer.localPermission == ChatPermission.blocked) {
      notice = t.chat.blocked;
    } else if (peer.localPermission == ChatPermission.denied || peer.remotePermission == ChatPermission.denied) {
      notice = t.chat.permissionDenied;
    } else if (peer.remotePermission == ChatPermission.pending) {
      notice = t.chat.pending;
    } else if (!vm.allowed) {
      notice = vm.capability == ChatCapabilityKind.unknown ? t.chat.unknownCapability : t.chat.permissionNeeded;
    } else if (!vm.online) {
      notice = t.chat.offlineHint;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PeerAddressHeader(peer: peer, online: vm.online),
            ),
            IconButton(tooltip: t.chat.refresh, onPressed: onRefresh, icon: const Icon(Icons.refresh)),
            IconButton(tooltip: t.chat.details, onPressed: onDetails, icon: const Icon(Icons.more_vert)),
          ],
        ),
        const Divider(height: 1),
        if (notice != null || vm.invitation != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (notice != null) Text(notice),
                if (vm.invitation != null && vm.encryptionEnabled) FilledButton(onPressed: onReview, child: Text(t.chat.reviewInvite)),
                if (vm.invitation == null &&
                    !vm.allowed &&
                    peer.localPermission != ChatPermission.blocked &&
                    peer.remotePermission != ChatPermission.pending &&
                    vm.encryptionEnabled &&
                    vm.capability == ChatCapabilityKind.chat)
                  OutlinedButton(onPressed: onInvite, child: Text(t.chat.invite)),
              ],
            ),
          ),
        if (vm.failed) TextButton(onPressed: onRefresh, child: Text(t.chat.loadFailed)),
        Expanded(
          child: vm.loading
              ? const Center(child: CircularProgressIndicator())
              : vm.messages.isEmpty
              ? Center(child: Text(t.chat.historyEmpty))
              : ListView.builder(
                  reverse: true,
                  key: ValueKey(peer.fingerprint),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: vm.messages.length + (vm.hasOlder ? 1 : 0),
                  itemBuilder: (context, index) => index == vm.messages.length
                      ? TextButton(onPressed: onOlder, child: Text(t.chat.older))
                      : ChatMessageBubble(
                          key: ValueKey(vm.messages[index].key),
                          message: vm.messages[index],
                          attachment: vm.messages[index].kind == MessageKind.attachment ? attachmentBuilder?.call(vm.messages[index]) : null,
                          onRetry: () => onRetry(vm.messages[index]),
                        ),
                ),
        ),
        if (vm.capability != ChatCapabilityKind.filesOnly)
          ChatComposer(key: ValueKey(peer.fingerprint), enabled: vm.canSend, onSend: onSend, onAttach: onAttach),
      ],
    );
  }
}
