import 'dart:io';

import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/provider/chat/chat_invitation_service.dart';
import 'package:localsend_app/provider/chat/chat_outbox_provider.dart';
import 'package:localsend_app/provider/chat/chat_transport.dart';
import 'package:localsend_app/repository/chat/chat_repository.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as wire;
import 'package:test/test.dart';

class InvitationTransport implements ChatTransport {
  int posts = 0;
  int polls = 0;
  bool wrongId = false;
  @override
  Future<wire.ChatInviteStatus> invite(Device device, String invitationId) async {
    posts++;
    return wire.ChatInviteStatus(invitationId: invitationId, status: wire.ChatInvitationStatus.pending);
  }

  @override
  Future<wire.ChatInviteStatus> inviteStatus(Device device, String invitationId) async {
    polls++;
    return wire.ChatInviteStatus(invitationId: wrongId ? 'wrong' : invitationId, status: wire.ChatInvitationStatus.accepted);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('only a matching outgoing invitation grants permission; background stops polling', () async {
    final dir = await Directory.systemTemp.createTemp('chat-invite-');
    final repository = await ChatRepository.open('${dir.path}/db.sqlite3', localFingerprint: 'A' * 64);
    final transport = InvitationTransport();
    final device = Device.empty.copyWith(fingerprint: 'B' * 64, ip: '127.0.0.1', port: 53317, https: true);
    final outbox = ChatOutboxService(repository: repository, transport: transport, resolvePeer: (_) => device, automatic: false);
    final service = ChatInvitationService(repository: repository, transport: transport, outbox: outbox, resolvePeer: (_) => device);
    try {
      await service.begin(device.fingerprint);
      expect(transport.posts, 1);
      expect((await repository.getPeer(device.fingerprint))!.remotePermission, ChatPermission.pending);
      service.setForeground(false);
      await service.pollNow();
      expect(transport.polls, 0);
      service.setForeground(true);
      transport.wrongId = true;
      await service.pollNow();
      expect((await repository.getPeer(device.fingerprint))!.remotePermission, ChatPermission.pending);
      transport.wrongId = false;
      await service.pollNow();
      expect((await repository.getPeer(device.fingerprint))!.remotePermission, ChatPermission.allowed);
    } finally {
      service.dispose();
      await outbox.dispose();
      await repository.close();
      await dir.delete(recursive: true);
    }
  });
}
