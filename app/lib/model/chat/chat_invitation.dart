import 'package:localsend_app/model/chat/chat_message.dart';

enum InvitationStatus { pending, accepted, rejected }

class ChatInvitation {
  final String invitationId;
  final String peerFingerprint;
  final MessageDirection direction;
  final InvitationStatus status;
  const ChatInvitation({required this.invitationId, required this.peerFingerprint, required this.direction, required this.status});
}
