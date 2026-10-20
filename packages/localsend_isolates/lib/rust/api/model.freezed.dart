// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatOperation {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatOperation&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'ChatOperation(field0: $field0)';
}


}

/// @nodoc
class $ChatOperationCopyWith<$Res>  {
$ChatOperationCopyWith(ChatOperation _, $Res Function(ChatOperation) __);
}


/// Adds pattern-matching-related methods to [ChatOperation].
extension ChatOperationPatterns on ChatOperation {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ChatOperation_Invite value)?  invite,TResult Function( ChatOperation_InviteStatus value)?  inviteStatus,TResult Function( ChatOperation_Deliver value)?  deliver,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ChatOperation_Invite() when invite != null:
return invite(_that);case ChatOperation_InviteStatus() when inviteStatus != null:
return inviteStatus(_that);case ChatOperation_Deliver() when deliver != null:
return deliver(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ChatOperation_Invite value)  invite,required TResult Function( ChatOperation_InviteStatus value)  inviteStatus,required TResult Function( ChatOperation_Deliver value)  deliver,}){
final _that = this;
switch (_that) {
case ChatOperation_Invite():
return invite(_that);case ChatOperation_InviteStatus():
return inviteStatus(_that);case ChatOperation_Deliver():
return deliver(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ChatOperation_Invite value)?  invite,TResult? Function( ChatOperation_InviteStatus value)?  inviteStatus,TResult? Function( ChatOperation_Deliver value)?  deliver,}){
final _that = this;
switch (_that) {
case ChatOperation_Invite() when invite != null:
return invite(_that);case ChatOperation_InviteStatus() when inviteStatus != null:
return inviteStatus(_that);case ChatOperation_Deliver() when deliver != null:
return deliver(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ChatInvite field0)?  invite,TResult Function( String field0)?  inviteStatus,TResult Function( ChatMessageDto field0)?  deliver,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ChatOperation_Invite() when invite != null:
return invite(_that.field0);case ChatOperation_InviteStatus() when inviteStatus != null:
return inviteStatus(_that.field0);case ChatOperation_Deliver() when deliver != null:
return deliver(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ChatInvite field0)  invite,required TResult Function( String field0)  inviteStatus,required TResult Function( ChatMessageDto field0)  deliver,}) {final _that = this;
switch (_that) {
case ChatOperation_Invite():
return invite(_that.field0);case ChatOperation_InviteStatus():
return inviteStatus(_that.field0);case ChatOperation_Deliver():
return deliver(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ChatInvite field0)?  invite,TResult? Function( String field0)?  inviteStatus,TResult? Function( ChatMessageDto field0)?  deliver,}) {final _that = this;
switch (_that) {
case ChatOperation_Invite() when invite != null:
return invite(_that.field0);case ChatOperation_InviteStatus() when inviteStatus != null:
return inviteStatus(_that.field0);case ChatOperation_Deliver() when deliver != null:
return deliver(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class ChatOperation_Invite extends ChatOperation {
  const ChatOperation_Invite(this.field0): super._();
  

@override final  ChatInvite field0;

/// Create a copy of ChatOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatOperation_InviteCopyWith<ChatOperation_Invite> get copyWith => _$ChatOperation_InviteCopyWithImpl<ChatOperation_Invite>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatOperation_Invite&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ChatOperation.invite(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ChatOperation_InviteCopyWith<$Res> implements $ChatOperationCopyWith<$Res> {
  factory $ChatOperation_InviteCopyWith(ChatOperation_Invite value, $Res Function(ChatOperation_Invite) _then) = _$ChatOperation_InviteCopyWithImpl;
@useResult
$Res call({
 ChatInvite field0
});




}
/// @nodoc
class _$ChatOperation_InviteCopyWithImpl<$Res>
    implements $ChatOperation_InviteCopyWith<$Res> {
  _$ChatOperation_InviteCopyWithImpl(this._self, this._then);

  final ChatOperation_Invite _self;
  final $Res Function(ChatOperation_Invite) _then;

/// Create a copy of ChatOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ChatOperation_Invite(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ChatInvite,
  ));
}


}

/// @nodoc


class ChatOperation_InviteStatus extends ChatOperation {
  const ChatOperation_InviteStatus(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ChatOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatOperation_InviteStatusCopyWith<ChatOperation_InviteStatus> get copyWith => _$ChatOperation_InviteStatusCopyWithImpl<ChatOperation_InviteStatus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatOperation_InviteStatus&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ChatOperation.inviteStatus(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ChatOperation_InviteStatusCopyWith<$Res> implements $ChatOperationCopyWith<$Res> {
  factory $ChatOperation_InviteStatusCopyWith(ChatOperation_InviteStatus value, $Res Function(ChatOperation_InviteStatus) _then) = _$ChatOperation_InviteStatusCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ChatOperation_InviteStatusCopyWithImpl<$Res>
    implements $ChatOperation_InviteStatusCopyWith<$Res> {
  _$ChatOperation_InviteStatusCopyWithImpl(this._self, this._then);

  final ChatOperation_InviteStatus _self;
  final $Res Function(ChatOperation_InviteStatus) _then;

/// Create a copy of ChatOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ChatOperation_InviteStatus(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ChatOperation_Deliver extends ChatOperation {
  const ChatOperation_Deliver(this.field0): super._();
  

@override final  ChatMessageDto field0;

/// Create a copy of ChatOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatOperation_DeliverCopyWith<ChatOperation_Deliver> get copyWith => _$ChatOperation_DeliverCopyWithImpl<ChatOperation_Deliver>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatOperation_Deliver&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ChatOperation.deliver(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ChatOperation_DeliverCopyWith<$Res> implements $ChatOperationCopyWith<$Res> {
  factory $ChatOperation_DeliverCopyWith(ChatOperation_Deliver value, $Res Function(ChatOperation_Deliver) _then) = _$ChatOperation_DeliverCopyWithImpl;
@useResult
$Res call({
 ChatMessageDto field0
});




}
/// @nodoc
class _$ChatOperation_DeliverCopyWithImpl<$Res>
    implements $ChatOperation_DeliverCopyWith<$Res> {
  _$ChatOperation_DeliverCopyWithImpl(this._self, this._then);

  final ChatOperation_Deliver _self;
  final $Res Function(ChatOperation_Deliver) _then;

/// Create a copy of ChatOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ChatOperation_Deliver(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ChatMessageDto,
  ));
}


}

/// @nodoc
mixin _$ChatReply {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatReply&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'ChatReply(field0: $field0)';
}


}

/// @nodoc
class $ChatReplyCopyWith<$Res>  {
$ChatReplyCopyWith(ChatReply _, $Res Function(ChatReply) __);
}


/// Adds pattern-matching-related methods to [ChatReply].
extension ChatReplyPatterns on ChatReply {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ChatReply_Invitation value)?  invitation,TResult Function( ChatReply_Stored value)?  stored,TResult Function( ChatReply_Rejected value)?  rejected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ChatReply_Invitation() when invitation != null:
return invitation(_that);case ChatReply_Stored() when stored != null:
return stored(_that);case ChatReply_Rejected() when rejected != null:
return rejected(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ChatReply_Invitation value)  invitation,required TResult Function( ChatReply_Stored value)  stored,required TResult Function( ChatReply_Rejected value)  rejected,}){
final _that = this;
switch (_that) {
case ChatReply_Invitation():
return invitation(_that);case ChatReply_Stored():
return stored(_that);case ChatReply_Rejected():
return rejected(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ChatReply_Invitation value)?  invitation,TResult? Function( ChatReply_Stored value)?  stored,TResult? Function( ChatReply_Rejected value)?  rejected,}){
final _that = this;
switch (_that) {
case ChatReply_Invitation() when invitation != null:
return invitation(_that);case ChatReply_Stored() when stored != null:
return stored(_that);case ChatReply_Rejected() when rejected != null:
return rejected(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ChatInviteStatus field0)?  invitation,TResult Function( ChatAck field0)?  stored,TResult Function( ChatErrorCode field0)?  rejected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ChatReply_Invitation() when invitation != null:
return invitation(_that.field0);case ChatReply_Stored() when stored != null:
return stored(_that.field0);case ChatReply_Rejected() when rejected != null:
return rejected(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ChatInviteStatus field0)  invitation,required TResult Function( ChatAck field0)  stored,required TResult Function( ChatErrorCode field0)  rejected,}) {final _that = this;
switch (_that) {
case ChatReply_Invitation():
return invitation(_that.field0);case ChatReply_Stored():
return stored(_that.field0);case ChatReply_Rejected():
return rejected(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ChatInviteStatus field0)?  invitation,TResult? Function( ChatAck field0)?  stored,TResult? Function( ChatErrorCode field0)?  rejected,}) {final _that = this;
switch (_that) {
case ChatReply_Invitation() when invitation != null:
return invitation(_that.field0);case ChatReply_Stored() when stored != null:
return stored(_that.field0);case ChatReply_Rejected() when rejected != null:
return rejected(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class ChatReply_Invitation extends ChatReply {
  const ChatReply_Invitation(this.field0): super._();
  

@override final  ChatInviteStatus field0;

/// Create a copy of ChatReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatReply_InvitationCopyWith<ChatReply_Invitation> get copyWith => _$ChatReply_InvitationCopyWithImpl<ChatReply_Invitation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatReply_Invitation&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ChatReply.invitation(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ChatReply_InvitationCopyWith<$Res> implements $ChatReplyCopyWith<$Res> {
  factory $ChatReply_InvitationCopyWith(ChatReply_Invitation value, $Res Function(ChatReply_Invitation) _then) = _$ChatReply_InvitationCopyWithImpl;
@useResult
$Res call({
 ChatInviteStatus field0
});




}
/// @nodoc
class _$ChatReply_InvitationCopyWithImpl<$Res>
    implements $ChatReply_InvitationCopyWith<$Res> {
  _$ChatReply_InvitationCopyWithImpl(this._self, this._then);

  final ChatReply_Invitation _self;
  final $Res Function(ChatReply_Invitation) _then;

/// Create a copy of ChatReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ChatReply_Invitation(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ChatInviteStatus,
  ));
}


}

/// @nodoc


class ChatReply_Stored extends ChatReply {
  const ChatReply_Stored(this.field0): super._();
  

@override final  ChatAck field0;

/// Create a copy of ChatReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatReply_StoredCopyWith<ChatReply_Stored> get copyWith => _$ChatReply_StoredCopyWithImpl<ChatReply_Stored>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatReply_Stored&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ChatReply.stored(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ChatReply_StoredCopyWith<$Res> implements $ChatReplyCopyWith<$Res> {
  factory $ChatReply_StoredCopyWith(ChatReply_Stored value, $Res Function(ChatReply_Stored) _then) = _$ChatReply_StoredCopyWithImpl;
@useResult
$Res call({
 ChatAck field0
});




}
/// @nodoc
class _$ChatReply_StoredCopyWithImpl<$Res>
    implements $ChatReply_StoredCopyWith<$Res> {
  _$ChatReply_StoredCopyWithImpl(this._self, this._then);

  final ChatReply_Stored _self;
  final $Res Function(ChatReply_Stored) _then;

/// Create a copy of ChatReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ChatReply_Stored(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ChatAck,
  ));
}


}

/// @nodoc


class ChatReply_Rejected extends ChatReply {
  const ChatReply_Rejected(this.field0): super._();
  

@override final  ChatErrorCode field0;

/// Create a copy of ChatReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatReply_RejectedCopyWith<ChatReply_Rejected> get copyWith => _$ChatReply_RejectedCopyWithImpl<ChatReply_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatReply_Rejected&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ChatReply.rejected(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ChatReply_RejectedCopyWith<$Res> implements $ChatReplyCopyWith<$Res> {
  factory $ChatReply_RejectedCopyWith(ChatReply_Rejected value, $Res Function(ChatReply_Rejected) _then) = _$ChatReply_RejectedCopyWithImpl;
@useResult
$Res call({
 ChatErrorCode field0
});




}
/// @nodoc
class _$ChatReply_RejectedCopyWithImpl<$Res>
    implements $ChatReply_RejectedCopyWith<$Res> {
  _$ChatReply_RejectedCopyWithImpl(this._self, this._then);

  final ChatReply_Rejected _self;
  final $Res Function(ChatReply_Rejected) _then;

/// Create a copy of ChatReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ChatReply_Rejected(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ChatErrorCode,
  ));
}


}

// dart format on
