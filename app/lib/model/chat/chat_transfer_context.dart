import 'package:dart_mappable/dart_mappable.dart';

part 'chat_transfer_context.mapper.dart';

@MappableClass()
class ChatTransferContext with ChatTransferContextMappable {
  final String conversationId;
  final String messageId;
  final String transferId;
  const ChatTransferContext({required this.conversationId, required this.messageId, required this.transferId});
}
