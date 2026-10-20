import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/provider/chat/chat_capabilities_provider.dart';

class ChatPageVm {
  final ChatPeer peer;
  final bool online;
  final bool encryptionEnabled;
  final ChatCapabilityKind capability;
  final List<ChatMessage> messages;
  final ChatInvitation? invitation;
  final bool hasOlder;
  final bool loading;
  final bool failed;
  const ChatPageVm({
    required this.peer,
    required this.online,
    required this.encryptionEnabled,
    required this.capability,
    required this.messages,
    this.invitation,
    this.hasOlder = false,
    this.loading = false,
    this.failed = false,
  });
  bool get allowed => peer.localPermission == ChatPermission.allowed && peer.remotePermission == ChatPermission.allowed;
  bool get canSend =>
      allowed && encryptionEnabled && capability != ChatCapabilityKind.filesOnly && capability != ChatCapabilityKind.encryptionRequired;
}
