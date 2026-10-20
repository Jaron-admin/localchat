import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';

String formatChatAddress(String? host, int? port) {
  if (host == null || host.isEmpty) return t.chat.unknownAddress;
  final formatted = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
  return port == null ? formatted : '$formatted:$port';
}

class PeerAddressHeader extends StatelessWidget {
  final ChatPeer peer;
  final bool online;
  const PeerAddressHeader({required this.peer, this.online = false, super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(peer.alias, style: Theme.of(context).textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        SelectableText('${formatChatAddress(peer.host, peer.port)} · ${peer.platform ?? '—'}'),
        Text(online ? t.chat.online : t.chat.offline, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
