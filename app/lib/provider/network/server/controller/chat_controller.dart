import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/rust/api/model.dart' as wire;

class ChatController {
  final ChatRepository repository;
  final Future<void> Function(String, wire.ChatReply) respond;
  ChatController(this.repository, {required this.respond});

  Future<void> onRequest(HttpServerChatRequestEvent event) async {
    wire.ChatReply reply;
    try {
      reply = await _process(event);
    } on ChatStorageException catch (e) {
      reply = wire.ChatReply.rejected(switch (e.code) {
        'denied' => wire.ChatErrorCode.denied,
        'conflict' => wire.ChatErrorCode.conflict,
        'overloaded' => wire.ChatErrorCode.overloaded,
        _ => wire.ChatErrorCode.unavailable,
      });
    } catch (_) {
      reply = const wire.ChatReply.rejected(wire.ChatErrorCode.unavailable);
    }
    // A disconnect or deadline may expire during COMMIT. The persisted message
    // remains valid and the sender can safely retry with the same ID.
    try {
      await respond(event.requestId, reply);
    } catch (_) {
      /* expired request */
    }
  }

  Future<wire.ChatReply> _process(HttpServerChatRequestEvent event) async {
    switch (event.operation) {
      case wire.ChatOperation_Invite(:final field0):
        await repository.recordInvitation(event.peerFingerprint, field0.invitationId);
        final invitation = await repository.readInvitation(event.peerFingerprint, field0.invitationId);
        return _invitationReply(invitation);
      case wire.ChatOperation_InviteStatus(:final field0):
        final invitation = await repository.readInvitation(event.peerFingerprint, field0);
        if (invitation.direction != MessageDirection.incoming) return const wire.ChatReply.rejected(wire.ChatErrorCode.denied);
        return _invitationReply(invitation);
      case wire.ChatOperation_Deliver(:final field0):
        final receipt = await repository.commitIncoming(
          verifiedFingerprint: event.peerFingerprint,
          messageId: field0.messageId,
          text: field0.text,
          sentAtMs: field0.sentAtMs.toInt(),
          receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (receipt.key.senderFingerprint != event.peerFingerprint || receipt.key.messageId != field0.messageId) {
          return const wire.ChatReply.rejected(wire.ChatErrorCode.unavailable);
        }
        return wire.ChatReply.stored(wire.ChatAck(messageId: receipt.key.messageId, duplicate: receipt.duplicate));
    }
  }

  wire.ChatReply _invitationReply(ChatInvitation invitation) => wire.ChatReply.invitation(
    wire.ChatInviteStatus(
      invitationId: invitation.invitationId,
      status: switch (invitation.status) {
        InvitationStatus.pending => wire.ChatInvitationStatus.pending,
        InvitationStatus.accepted => wire.ChatInvitationStatus.accepted,
        InvitationStatus.rejected => wire.ChatInvitationStatus.rejected,
      },
    ),
  );
}
