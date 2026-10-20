import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/rust/api/model.dart' as wire;
import 'package:refena_flutter/refena_flutter.dart';

class ChatTransportException implements Exception {
  final String code;
  final bool retryable;
  final int? status;
  const ChatTransportException(this.code, {this.retryable = true, this.status});
  @override
  String toString() => 'ChatTransportException($code)';
}

class ChatDeliveryReceipt {
  final String messageId;
  final String verifiedPeerFingerprint;
  final bool duplicate;
  const ChatDeliveryReceipt({required this.messageId, required this.verifiedPeerFingerprint, required this.duplicate});
}

abstract class ChatTransport {
  Future<wire.ChatCapabilities> capabilities(Device device);
  Future<wire.ChatInviteStatus> invite(Device device, String invitationId);
  Future<wire.ChatInviteStatus> inviteStatus(Device device, String invitationId);
  Future<ChatDeliveryReceipt> deliver(Device device, ChatMessage message);
}

final chatTransportProvider = Provider<ChatTransport>((ref) => PinnedChatTransport(() => ref.read(httpProvider)));

class PinnedChatTransport implements ChatTransport {
  final HttpClientCollection Function() clients;
  PinnedChatTransport(this.clients);
  Future<T> _send<T>(Device device, Future<T> Function(RsHttpClient, String, int) action) async {
    if (!device.https || device.ip == null) throw const ChatTransportException('encrypted_lan_required', retryable: false);
    try {
      return await action(clients().pinnedTo(device.fingerprint), device.ip!, device.port);
    } on RsHttpClientError_StatusCode catch (e) {
      throw ChatTransportException(
        switch (e.status) {
          403 => 'denied',
          409 => 'conflict',
          404 => 'unsupported',
          429 => 'overloaded',
          _ => 'unavailable',
        },
        retryable: e.status == 429 || e.status >= 500,
        status: e.status,
      );
    } catch (e) {
      if (e is ChatTransportException) rethrow;
      // Transport errors may include request URLs or body data. Keep only a code.
      throw const ChatTransportException('network');
    }
  }

  @override
  Future<wire.ChatCapabilities> capabilities(Device device) => _send(device, (client, host, port) => client.chatCapabilities(ip: host, port: port));
  @override
  Future<wire.ChatInviteStatus> invite(Device device, String invitationId) => _send(
    device,
    (client, host, port) => client.chatInvite(
      ip: host,
      port: port,
      payload: wire.ChatInvite(version: 1, invitationId: invitationId),
    ),
  );
  @override
  Future<wire.ChatInviteStatus> inviteStatus(Device device, String invitationId) =>
      _send(device, (client, host, port) => client.chatInviteStatus(ip: host, port: port, invitationId: invitationId));
  @override
  Future<ChatDeliveryReceipt> deliver(Device device, ChatMessage message) async {
    final ack = await _send(
      device,
      (client, host, port) => client.chatDeliver(
        ip: host,
        port: port,
        payload: wire.ChatMessageDto(version: 1, messageId: message.key.messageId, sentAtMs: message.sentAtMs, text: message.text!),
      ),
    );
    return ChatDeliveryReceipt(messageId: ack.messageId, verifiedPeerFingerprint: device.fingerprint, duplicate: ack.duplicate);
  }
}
