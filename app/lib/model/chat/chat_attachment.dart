import 'package:localsend_app/model/chat/chat_message.dart';

enum AttachmentState { offered, waiting, transferring, complete, rejected, cancelled, failed }

class ChatAttachment {
  final String attachmentId;
  final MessageKey messageKey;
  final String transferId;
  final String? sessionId;
  final String? remoteSessionId;
  final String fileId;
  final String name;
  final int size;
  final String? localPath;
  final AttachmentState state;
  const ChatAttachment({
    required this.attachmentId,
    required this.messageKey,
    required this.transferId,
    this.sessionId,
    this.remoteSessionId,
    required this.fileId,
    required this.name,
    required this.size,
    this.localPath,
    required this.state,
  });
}

class AttachmentResult {
  final String peerFingerprint;
  final MessageKey messageKey;
  final String transferId;
  final String sessionId;
  final String fileId;
  final AttachmentState state;
  final String? localPath;
  final String? remoteSessionId;
  const AttachmentResult({
    required this.peerFingerprint,
    required this.messageKey,
    required this.transferId,
    required this.sessionId,
    required this.fileId,
    required this.state,
    this.localPath,
    this.remoteSessionId,
  });
}
