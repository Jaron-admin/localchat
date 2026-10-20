import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/pages/chat/chat_page.dart';
import 'package:localsend_app/pages/chat/chat_page_vm.dart';
import 'package:localsend_app/provider/chat/chat_capabilities_provider.dart';
import 'package:localsend_app/widget/chat/chat_composer.dart';
import 'package:localsend_app/widget/chat/chat_message_bubble.dart';
import 'package:localsend_app/widget/chat/peer_address_header.dart';
import 'package:localsend_app/widget/dialogs/chat_invitation_dialog.dart';

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));
  testWidgets('persisted peer timestamps outside DateTime range cannot break history', (tester) async {
    for (final timestamp in [9223372036854775807, -9223372036854775808, 8640000000000001, -8640000000000001]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: ChatMessage(
                key: const MessageKey('peer', 'id'),
                conversationId: 'c',
                peerFingerprint: 'peer',
                localSequence: 1,
                kind: MessageKind.text,
                direction: MessageDirection.incoming,
                text: 'History remains readable',
                sentAtMs: timestamp,
                deliveryState: DeliveryState.delivered,
                attemptCount: 0,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('History remains readable'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    }
  });
  testWidgets('invitation exposes the exact certificate fingerprint being accepted', (tester) async {
    bool? decision;
    final invitation = ChatInvitation(
      invitationId: 'invitation-B',
      peerFingerprint: 'B' * 64,
      direction: MessageDirection.incoming,
      status: InvitationStatus.pending,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                decision = await showDialog<bool>(
                  context: context,
                  builder: (_) => ChatInvitationDialog(
                    peer: ChatPeer(fingerprint: 'B' * 64, alias: 'Same alias'),
                    invitation: invitation,
                  ),
                );
              },
              child: const Text('Open request'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open request'));
    await tester.pumpAndSettle();
    expect(find.text('B' * 64), findsOneWidget);
    expect(find.text('C' * 64), findsNothing);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(decision, isTrue);
  });
  testWidgets('offline history stays visible; plaintext disables composer; legacy hides it', (tester) async {
    const peer = ChatPeer(
      fingerprint: 'A',
      alias: 'Offline phone',
      host: '192.168.2.8',
      port: 50123,
      localPermission: ChatPermission.allowed,
      remotePermission: ChatPermission.allowed,
    );
    const message = ChatMessage(
      key: MessageKey('A', 'id'),
      conversationId: 'c',
      peerFingerprint: 'B',
      localSequence: 1,
      kind: MessageKind.text,
      direction: MessageDirection.incoming,
      text: 'Saved history',
      sentAtMs: 0,
      deliveryState: DeliveryState.delivered,
      attemptCount: 0,
    );
    Future<void> render(ChatCapabilityKind capability, bool https) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatConversationView(
              vm: ChatPageVm(peer: peer, online: false, encryptionEnabled: https, capability: capability, messages: const [message]),
              onSend: (_) async {},
              onOlder: () {},
              onRefresh: () {},
              onInvite: () {},
              onDetails: () {},
              onRetry: (_) {},
            ),
          ),
        ),
      );
    }

    await render(ChatCapabilityKind.unknown, true);
    expect(find.text('Saved history'), findsOneWidget);
    expect(tester.widget<ChatComposer>(find.byType(ChatComposer)).enabled, isTrue);
    await render(ChatCapabilityKind.chat, false);
    expect(tester.widget<ChatComposer>(find.byType(ChatComposer)).enabled, isFalse);
    expect(find.textContaining('Enable HTTPS'), findsOneWidget);
    await render(ChatCapabilityKind.filesOnly, true);
    expect(find.byType(ChatComposer), findsNothing);
    expect(find.text('Saved history'), findsOneWidget);
  });
  testWidgets('address includes scoped IPv6, actual port and platform when offline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PeerAddressHeader(
            peer: ChatPeer(fingerprint: 'test', alias: 'Phone', host: 'fe80::1%7', port: 58723, platform: 'Android'),
            online: false,
          ),
        ),
      ),
    );
    expect(find.textContaining('[fe80::1%7]:58723'), findsOneWidget);
    expect(find.textContaining('Android'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
  });
  testWidgets('delivered bubble never claims read and preserves multiline text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            message: ChatMessage(
              key: MessageKey('A', 'id'),
              conversationId: 'c',
              peerFingerprint: 'B',
              localSequence: 1,
              kind: MessageKind.text,
              direction: MessageDirection.outgoing,
              text: '你好\n🙂',
              sentAtMs: 0,
              deliveryState: DeliveryState.delivered,
              attemptCount: 1,
            ),
          ),
        ),
      ),
    );
    expect(find.text('你好\n🙂'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('Read'), findsNothing);
  });
  testWidgets('composer enforces UTF-8 bytes and keeps draft when storage fails', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            enabled: true,
            onSend: (text) async {
              calls++;
              throw StateError('storage unavailable');
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '中' * 10923);
    await tester.pump();
    expect(find.textContaining('32 KiB'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    expect(calls, 0);
    await tester.enterText(find.byType(TextField), '你好\n🙂');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('你好\n🙂'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });
}
