import 'dart:async';
import 'dart:isolate';

import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_conversation.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/model/chat/chat_result.dart';
import 'package:localsend_app/model/chat/chat_transfer_context.dart';
import 'package:localsend_app/repository/chat/chat_database_worker.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';

class SqliteChatRepository implements ChatRepository {
  final _responses = ReceivePort();
  final _errors = ReceivePort();
  final _ready = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  final _changes = StreamController<ChatChange>.broadcast();
  SendPort? _worker;
  Isolate? _isolate;
  int _sequence = 0;
  bool _closing = false;
  bool _dead = false;
  Future<void>? _closeFuture;

  static Future<SqliteChatRepository> open(String databasePath, {required String localFingerprint}) async {
    final result = SqliteChatRepository._();
    result._responses.listen(result._onResponse);
    result._errors.listen((_) => result._failed());
    try {
      result._isolate = await Isolate.spawn(
        chatDatabaseWorker,
        (databasePath, localFingerprint, result._responses.sendPort),
        onError: result._errors.sendPort,
        onExit: result._responses.sendPort,
        errorsAreFatal: true,
        debugName: 'localchat-database',
      );
      await result._ready.future;
      return result;
    } catch (_) {
      result._disposePorts();
      result._isolate?.kill(priority: Isolate.immediate);
      await result._changes.close();
      throw const ChatStorageException('unavailable');
    }
  }

  SqliteChatRepository._();

  void _onResponse(dynamic response) {
    if (response == null) {
      if (_pending.isNotEmpty || !_closing) _failed();
      return;
    }
    if (response is SendPort) {
      _worker = response;
      _ready.complete();
      return;
    }
    if (response is ChatStorageException) {
      if (!_ready.isCompleted) _ready.completeError(response);
      _failed();
      return;
    }
    final (int id, Object? value, ChatStorageException? error, Set<String> changed) = response as (int, Object?, ChatStorageException?, Set<String>);
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (error != null) {
      completer.completeError(error);
    } else {
      if (changed.isNotEmpty) _changes.add(ChatChange(Set.unmodifiable(changed)));
      completer.complete(value);
    }
  }

  void _failed() {
    _dead = true;
    if (!_ready.isCompleted) _ready.completeError(const ChatStorageException('unavailable'));
    for (final c in _pending.values) {
      c.completeError(const ChatStorageException('unavailable'));
    }
    _pending.clear();
  }

  Future<T> _call<T>(String method, List<Object?> arguments, {bool shutdown = false}) {
    if (_dead || (_closing && !shutdown)) return Future.error(const ChatStorageException('unavailable'));
    if (!shutdown && _pending.length >= 256) return Future.error(const ChatStorageException('overloaded'));
    final id = ++_sequence;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _worker!.send((id, method, arguments));
    return completer.future.then((value) => value as T);
  }

  @override
  Stream<ChatChange> get changes => _changes.stream;
  @override
  Future<void> upsertPeer(ChatPeer peer) => _call('upsertPeer', [peer]);
  @override
  Future<ChatPeer?> getPeer(String fingerprint) => _call('getPeer', [fingerprint]);
  @override
  Future<void> setOwnDevice(String fingerprint, bool value) => _call('setOwnDevice', [fingerprint, value]);
  @override
  Future<void> beginInvitation(String fingerprint, String invitationId) => _call('beginInvitation', [fingerprint, invitationId]);
  @override
  Future<void> recordInvitation(String verifiedFingerprint, String invitationId) => _call('recordInvitation', [verifiedFingerprint, invitationId]);
  @override
  Future<void> decideInvitation(String fingerprint, String invitationId, bool accept) =>
      _call('decideInvitation', [fingerprint, invitationId, accept]);
  @override
  Future<void> completeOutgoingInvitation(String verifiedFingerprint, String invitationId, bool accepted) =>
      _call('completeInvitation', [verifiedFingerprint, invitationId, accepted]);
  @override
  Future<ChatInvitation> readInvitation(String verifiedFingerprint, String invitationId) =>
      _call('readInvitation', [verifiedFingerprint, invitationId]);
  @override
  Future<List<ChatInvitation>> listInvitations({String? peerFingerprint}) => _call('listInvitations', [peerFingerprint]);
  @override
  Future<void> revokePermission(String fingerprint, {required bool block}) => _call('revokePermission', [fingerprint, block]);
  @override
  Future<ChatConversation> ensureConversation(String peerFingerprint) => _call('ensureConversation', [peerFingerprint]);
  @override
  Future<List<ChatConversation>> listConversations() => _call('listConversations', []);
  @override
  Future<List<ChatMessage>> listMessages(String conversationId, {int? beforeSequence, int limit = 50}) =>
      _call('listMessages', [conversationId, beforeSequence, limit]);
  @override
  Future<void> recordFileOffer({
    required String peerFingerprint,
    required ChatTransferContext context,
    required List<ChatAttachment> files,
    required bool incoming,
  }) => _call('recordFileOffer', [peerFingerprint, context, files, incoming]);
  @override
  Future<List<ChatAttachment>> listAttachments(MessageKey key) => _call('listAttachments', [key]);
  @override
  Future<void> applyAttachmentResult(AttachmentResult result) => _call('attachmentResult', [result]);
  @override
  Future<void> applySessionAttachmentResult({
    required String sessionId,
    String? fileId,
    required AttachmentState state,
    String? localPath,
    String? remoteSessionId,
  }) => _call('sessionAttachmentResult', [sessionId, fileId, state, localPath, remoteSessionId]);
  @override
  Future<ChatMessage> enqueueText({required String peerFingerprint, required String messageId, required String text, required int sentAtMs}) =>
      _call('enqueueText', [peerFingerprint, messageId, text, sentAtMs]);
  @override
  Future<IncomingCommit> commitIncoming({
    required String verifiedFingerprint,
    required String messageId,
    required String text,
    required int sentAtMs,
    required int receivedAtMs,
  }) => _call('commitIncoming', [verifiedFingerprint, messageId, text, sentAtMs, receivedAtMs]);
  @override
  Future<List<ChatMessage>> loadDueOutbox(DateTime now, {String? peerFingerprint}) =>
      _call('loadDueOutbox', [now.millisecondsSinceEpoch, peerFingerprint]);
  @override
  Future<bool> tryStartAttempt(MessageKey key, DateTime now) => _call('tryStartAttempt', [key, now.millisecondsSinceEpoch]);
  @override
  Future<void> recordDelivery(MessageKey key, {required String verifiedPeerFingerprint}) => _call('recordDelivery', [key, verifiedPeerFingerprint]);
  @override
  Future<void> recordAttemptFailure(MessageKey key, DeliveryFailure failure) => _call('recordAttemptFailure', [key, failure]);
  @override
  Future<void> scheduleManualRetry(MessageKey key, DateTime now) => _call('scheduleManualRetry', [key, now.millisecondsSinceEpoch]);
  @override
  Future<void> recoverInterruptedAttempts() => _call('recover', []);
  @override
  Future<void> changeLocalIdentity(String fingerprint) => _call('changeIdentity', [fingerprint]);
  @override
  Future<void> markConversationRead(String id, int throughSequence) => _call('markRead', [id, throughSequence]);
  @override
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closing = true;
    try {
      if (!_dead && _worker != null) await _call<void>('close', [], shutdown: true);
    } finally {
      _disposePorts();
      await _changes.close();
    }
  }

  void _disposePorts() {
    _responses.close();
    _errors.close();
  }
}
