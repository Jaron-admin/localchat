import 'package:localsend_app/model/chat/chat_message.dart';

class ChatStorageException implements Exception {
  final String code;
  const ChatStorageException(this.code);
  @override
  String toString() => 'ChatStorageException($code)';
}

class IncomingCommit {
  final MessageKey key;
  final bool duplicate;
  const IncomingCommit({required this.key, required this.duplicate});
}

class DeliveryFailure {
  final bool retryable;
  final String code;
  final DateTime occurredAt;
  const DeliveryFailure({required this.retryable, required this.code, required this.occurredAt});
}

class ChatChange {
  final Set<String> conversationIds;
  const ChatChange(this.conversationIds);
}
