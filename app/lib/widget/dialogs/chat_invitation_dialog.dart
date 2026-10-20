import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';

class ChatInvitationDialog extends StatelessWidget {
  final ChatPeer peer;
  final ChatInvitation invitation;
  const ChatInvitationDialog({required this.peer, required this.invitation, super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t.chat.inviteTitle),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(peer.alias, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(t.chat.inviteHint),
          const SizedBox(height: 12),
          Text(t.chat.fingerprint),
          SelectableText(invitation.peerFingerprint, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.chat.decline)),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.chat.accept)),
    ],
  );
}
