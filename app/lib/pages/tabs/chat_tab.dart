import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/pages/chat/chat_page.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/widget/chat/peer_address_header.dart';
import 'package:refena_flutter/refena_flutter.dart';

class ChatTab extends StatefulWidget {
  final Widget Function(String id, bool embedded, bool active) pageBuilder;
  const ChatTab({this.pageBuilder = _chatPage, super.key});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  bool _ownOnly = false;
  int _handledSelection = -1;
  MaterialPageRoute<void>? _route;
  Future<void> _open(BuildContext context, ChatViewService service, bool wide) async {
    final id = service.selectedId;
    if (id == null || wide || _route != null) return;
    final route = MaterialPageRoute<void>(
      settings: RouteSettings(name: '/chat/$id'),
      builder: (routeContext) {
        // The homepage is offstage while this route is visible, so its LayoutBuilder
        // does not run on resize. Observe the visible route's window width instead.
        final width = MediaQuery.sizeOf(routeContext).width;
        if (width - HomePage.navigationWidth(width) >= 700) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _route?.isCurrent == true) Navigator.of(routeContext).pop();
          });
        }
        return widget.pageBuilder(id, false, true);
      },
    );
    setState(() => _route = route);
    await Navigator.of(context).push(route);
    await route.completed;
    if (mounted) setState(() => _route = null);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read(chatViewProvider);
    final active = context.watch(homePageControllerProvider).currentTab == HomeTab.chat;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 700;
          if (active && service.selectedId != null && _handledSelection != service.selectionRevision) {
            _handledSelection = service.selectionRevision;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_open(context, service, wide));
            });
          }
          if (wide && _route?.isCurrent == true) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _route?.isCurrent == true) Navigator.of(context).pop();
            });
          }
          final conversations = service.conversations.where((c) => !_ownOnly || (service.peers[c.peerFingerprint]?.isOwnDevice ?? false)).toList();
          final list = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                child: Row(
                  children: [
                    Expanded(child: Text(t.chat.title, style: Theme.of(context).textTheme.headlineMedium)),
                    IconButton(
                      tooltip: t.chat.newChat,
                      icon: const Icon(Icons.edit_square),
                      onPressed: () => context.redux(homePageControllerProvider).dispatch(OpenNearbyTransferAction(NearbySection.devices)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(label: Text(t.chat.allDevices), selected: !_ownOnly, onSelected: (_) => setState(() => _ownOnly = false)),
                    ChoiceChip(label: Text(t.chat.ownDevice), selected: _ownOnly, onSelected: (_) => setState(() => _ownOnly = true)),
                  ],
                ),
              ),
              if (service.failed) TextButton(onPressed: service.refresh, child: Text(t.chat.loadFailed)),
              Expanded(
                child: service.loading
                    ? const Center(child: CircularProgressIndicator())
                    : conversations.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(t.chat.empty)),
                      )
                    : ListView.builder(
                        itemCount: conversations.length,
                        itemBuilder: (context, index) {
                          final conversation = conversations[index];
                          final peer = service.peers[conversation.peerFingerprint];
                          if (peer == null) return const SizedBox.shrink();
                          final pending = service.requests.any(
                            (i) =>
                                i.peerFingerprint == peer.fingerprint &&
                                i.direction == MessageDirection.incoming &&
                                i.status == InvitationStatus.pending,
                          );
                          return ListTile(
                            selected: wide && service.selectedId == conversation.id,
                            leading: Icon(peer.isOwnDevice ? Icons.devices : Icons.person_outline),
                            title: Text(peer.alias, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${formatChatAddress(peer.host, peer.port)}\n${pending ? t.chat.requestIncoming : peer.platform ?? '—'}'),
                            isThreeLine: true,
                            trailing: conversation.unreadCount > 0
                                ? Badge(label: Text('${conversation.unreadCount}'))
                                : pending
                                ? const Icon(Icons.mail_outline)
                                : null,
                            onTap: () => service.select(conversation.id),
                          );
                        },
                      ),
              ),
            ],
          );
          return ChatSplitLayout(
            wide: wide,
            list: list,
            detail: service.selectedId != null && _route == null
                ? KeyedSubtree(key: ValueKey(service.selectedId), child: widget.pageBuilder(service.selectedId!, true, active))
                : Center(child: Text(t.chat.choose)),
          );
        },
      ),
    );
  }
}

Widget _chatPage(String id, bool embedded, bool active) => ChatPage(conversationId: id, embedded: embedded, active: active);

class ChatSplitLayout extends StatelessWidget {
  final bool wide;
  final Widget list, detail;
  const ChatSplitLayout({required this.wide, required this.list, required this.detail, super.key});
  @override
  Widget build(BuildContext context) => wide
      ? Row(
          children: [
            SizedBox(width: 300, child: list),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        )
      : list;
}
