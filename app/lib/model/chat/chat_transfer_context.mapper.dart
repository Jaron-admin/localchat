// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'chat_transfer_context.dart';

class ChatTransferContextMapper extends ClassMapperBase<ChatTransferContext> {
  ChatTransferContextMapper._();

  static ChatTransferContextMapper? _instance;
  static ChatTransferContextMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChatTransferContextMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ChatTransferContext';

  static String _$conversationId(ChatTransferContext v) => v.conversationId;
  static const Field<ChatTransferContext, String> _f$conversationId = Field(
    'conversationId',
    _$conversationId,
  );
  static String _$messageId(ChatTransferContext v) => v.messageId;
  static const Field<ChatTransferContext, String> _f$messageId = Field(
    'messageId',
    _$messageId,
  );
  static String _$transferId(ChatTransferContext v) => v.transferId;
  static const Field<ChatTransferContext, String> _f$transferId = Field(
    'transferId',
    _$transferId,
  );

  @override
  final MappableFields<ChatTransferContext> fields = const {
    #conversationId: _f$conversationId,
    #messageId: _f$messageId,
    #transferId: _f$transferId,
  };

  static ChatTransferContext _instantiate(DecodingData data) {
    return ChatTransferContext(
      conversationId: data.dec(_f$conversationId),
      messageId: data.dec(_f$messageId),
      transferId: data.dec(_f$transferId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChatTransferContext fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChatTransferContext>(map);
  }

  static ChatTransferContext deserialize(String json) {
    return ensureInitialized().decodeJson<ChatTransferContext>(json);
  }
}

mixin ChatTransferContextMappable {
  String serialize() {
    return ChatTransferContextMapper.ensureInitialized()
        .encodeJson<ChatTransferContext>(this as ChatTransferContext);
  }

  Map<String, dynamic> toJson() {
    return ChatTransferContextMapper.ensureInitialized()
        .encodeMap<ChatTransferContext>(this as ChatTransferContext);
  }

  ChatTransferContextCopyWith<
    ChatTransferContext,
    ChatTransferContext,
    ChatTransferContext
  >
  get copyWith =>
      _ChatTransferContextCopyWithImpl<
        ChatTransferContext,
        ChatTransferContext
      >(this as ChatTransferContext, $identity, $identity);
  @override
  String toString() {
    return ChatTransferContextMapper.ensureInitialized().stringifyValue(
      this as ChatTransferContext,
    );
  }

  @override
  bool operator ==(Object other) {
    return ChatTransferContextMapper.ensureInitialized().equalsValue(
      this as ChatTransferContext,
      other,
    );
  }

  @override
  int get hashCode {
    return ChatTransferContextMapper.ensureInitialized().hashValue(
      this as ChatTransferContext,
    );
  }
}

extension ChatTransferContextValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ChatTransferContext, $Out> {
  ChatTransferContextCopyWith<$R, ChatTransferContext, $Out>
  get $asChatTransferContext => $base.as(
    (v, t, t2) => _ChatTransferContextCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ChatTransferContextCopyWith<
  $R,
  $In extends ChatTransferContext,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? conversationId, String? messageId, String? transferId});
  ChatTransferContextCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ChatTransferContextCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ChatTransferContext, $Out>
    implements ChatTransferContextCopyWith<$R, ChatTransferContext, $Out> {
  _ChatTransferContextCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ChatTransferContext> $mapper =
      ChatTransferContextMapper.ensureInitialized();
  @override
  $R call({String? conversationId, String? messageId, String? transferId}) =>
      $apply(
        FieldCopyWithData({
          if (conversationId != null) #conversationId: conversationId,
          if (messageId != null) #messageId: messageId,
          if (transferId != null) #transferId: transferId,
        }),
      );
  @override
  ChatTransferContext $make(CopyWithData data) => ChatTransferContext(
    conversationId: data.get(#conversationId, or: $value.conversationId),
    messageId: data.get(#messageId, or: $value.messageId),
    transferId: data.get(#transferId, or: $value.transferId),
  );

  @override
  ChatTransferContextCopyWith<$R2, ChatTransferContext, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ChatTransferContextCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

