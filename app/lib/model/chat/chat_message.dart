enum DeliveryState { queued, sending, delivered, unconfirmed, failed, rejected }

enum MessageKind { text, attachment }

enum MessageDirection { incoming, outgoing }

class MessageKey {
  final String senderFingerprint;
  final String messageId;
  const MessageKey(this.senderFingerprint, this.messageId);
  @override
  bool operator ==(Object other) => other is MessageKey && other.senderFingerprint == senderFingerprint && other.messageId == messageId;
  @override
  int get hashCode => Object.hash(senderFingerprint, messageId);
}

class ChatMessage {
  final MessageKey key;
  final String conversationId;
  final String peerFingerprint;
  final int localSequence;
  final MessageKind kind;
  final MessageDirection direction;
  final String? text;
  final int sentAtMs;
  final int? receivedAtMs;
  final DeliveryState deliveryState;
  final int attemptCount;
  final int? nextAttemptAt;
  final String? lastError;
  const ChatMessage({
    required this.key,
    required this.conversationId,
    required this.peerFingerprint,
    required this.localSequence,
    required this.kind,
    required this.direction,
    this.text,
    required this.sentAtMs,
    this.receivedAtMs,
    required this.deliveryState,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastError,
  });
}
