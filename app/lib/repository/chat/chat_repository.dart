import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_conversation.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/model/chat/chat_transfer_context.dart';
import 'package:localsend_app/repository/chat/sqlite_chat_repository.dart';

abstract class ChatRepository {
  static Future<ChatRepository> open(String databasePath, {required String localFingerprint}) =>
      SqliteChatRepository.open(databasePath, localFingerprint: localFingerprint);
  Stream<ChatChange> get changes;
  Future<void> upsertPeer(ChatPeer peer);
  Future<ChatPeer?> getPeer(String fingerprint);
  Future<void> setOwnDevice(String fingerprint, bool value);
  Future<void> beginInvitation(String fingerprint, String invitationId);
  Future<void> recordInvitation(String verifiedFingerprint, String invitationId);
  Future<void> decideInvitation(String fingerprint, String invitationId, bool accept);
  Future<void> completeOutgoingInvitation(String verifiedFingerprint, String invitationId, bool accepted);
  Future<ChatInvitation> readInvitation(String verifiedFingerprint, String invitationId);
  Future<List<ChatInvitation>> listInvitations({String? peerFingerprint});
  Future<void> revokePermission(String fingerprint, {required bool block});
  Future<ChatConversation> ensureConversation(String peerFingerprint);
  Future<List<ChatConversation>> listConversations();
  Future<List<ChatMessage>> listMessages(String conversationId, {int? beforeSequence, int limit = 50});
  Future<void> recordFileOffer({
    required String peerFingerprint,
    required ChatTransferContext context,
    required List<ChatAttachment> files,
    required bool incoming,
  });
  Future<List<ChatAttachment>> listAttachments(MessageKey key);
  Future<void> applyAttachmentResult(AttachmentResult result);

  /// Internal file-engine events carry only opaque session/file IDs. Resolve their
  /// persisted ownership before applying the same checked AttachmentResult path.
  Future<void> applySessionAttachmentResult({
    required String sessionId,
    String? fileId,
    required AttachmentState state,
    String? localPath,
    String? remoteSessionId,
  });
  Future<ChatMessage> enqueueText({required String peerFingerprint, required String messageId, required String text, required int sentAtMs});
  Future<IncomingCommit> commitIncoming({
    required String verifiedFingerprint,
    required String messageId,
    required String text,
    required int sentAtMs,
    required int receivedAtMs,
  });
  Future<List<ChatMessage>> loadDueOutbox(DateTime now, {String? peerFingerprint});
  Future<bool> tryStartAttempt(MessageKey key, DateTime now);
  Future<void> recordDelivery(MessageKey key, {required String verifiedPeerFingerprint});
  Future<void> recordAttemptFailure(MessageKey key, DeliveryFailure failure);
  Future<void> scheduleManualRetry(MessageKey key, DateTime now);
  Future<void> recoverInterruptedAttempts();
  Future<void> changeLocalIdentity(String fingerprint);
  Future<void> markConversationRead(String id, int throughSequence);
  Future<void> close();
}
