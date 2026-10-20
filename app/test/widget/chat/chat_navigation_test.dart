import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_conversation.dart';
import 'package:localsend_app/model/chat/chat_invitation.dart';
import 'package:localsend_app/model/chat/chat_peer.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/chat_tab.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/chat/transfer_notice_provider.dart';
import 'package:localsend_app/widget/chat/chat_composer.dart';
import 'package:localsend_app/widget/watcher/shortcut_watcher.dart';
import 'package:refena_flutter/refena_flutter.dart' hide ChangeNotifier;

class NavigationChat extends ChangeNotifier implements ChatViewService {
  @override
  List<ChatConversation> get conversations => [const ChatConversation(id: 'conversation', peerFingerprint: 'B', lastActivity: 0, unreadCount: 0)];
  @override
  Map<String, ChatPeer> get peers => {'B': const ChatPeer(fingerprint: 'B', alias: 'Test phone', host: '192.168.0.9', port: 53456)};
  @override
  List<ChatInvitation> get requests => [];
  @override
  bool get loading => false;
  @override
  bool get failed => false;
  @override
  String? selectedId;
  @override
  int selectionRevision = 0;
  @override
  void select(String id) {
    selectedId = id;
    selectionRevision++;
    notifyListeners();
  }

  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));
  testWidgets('narrow opens a route; widening returns to one embedded conversation', (tester) async {
    final service = NavigationChat();
    addTearDown(service.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RefenaScope(
        overrides: [chatViewProvider.overrideWithValue(service), homePageControllerProvider.overrideWithNotifier((ref) => HomePageController())],
        child: MaterialApp(
          home: Scaffold(
            body: ChatTab(
              pageBuilder: (id, embedded, active) => embedded
                  ? const Text('Embedded history')
                  : Scaffold(
                      appBar: AppBar(title: const Text('Conversation route')),
                      body: const Text('Mobile history'),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test phone'));
    await tester.pumpAndSettle();
    expect(find.text('Mobile history'), findsOneWidget);
    expect(find.text('Test phone'), findsNothing);
    tester.view.physicalSize = const Size(1100, 780);
    await tester.pumpAndSettle();
    expect(find.text('Mobile history'), findsNothing);
    expect(find.text('Embedded history'), findsOneWidget);
    expect(find.text('Test phone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('all external sharing returns to existing home and selects nearby send', () {
    var returned = 0;
    final container = RefenaContainer(
      overrides: [homePageControllerProvider.overrideWithNotifier((ref) => HomePageController(returnToHome: () => returned++))],
    );
    final controller = container.notifier(homePageControllerProvider);
    final page = controller.state.controller;
    container.redux(homePageControllerProvider).dispatch(OpenNearbyTransferAction(NearbySection.send));
    expect(controller.state.currentTab, HomeTab.nearby);
    expect(controller.state.nearbySection, NearbySection.send);
    expect(controller.state.controller, same(page));
    expect(returned, 1);
    container.disposeContainer();
    page.dispose();
  });
  test('file offers do not open a route; only the user activates the transfer', () async {
    final notice = TransferNoticeService();
    var opened = 0;
    final done = Completer<void>();
    notice.offer('one', () async {
      opened++;
      await done.future;
    });
    expect(opened, 0);
    final first = notice.open();
    await notice.open();
    expect(opened, 1);
    notice.offer('two', () async {});
    done.complete();
    await first;
    expect(notice.sessionId, 'two');
    notice.clear('one');
    expect(notice.sessionId, 'two');
    notice.dispose();
  });
  testWidgets('wide renders list and history, narrow renders only list', (tester) async {
    for (final wide in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatSplitLayout(wide: wide, list: const Text('conversations'), detail: const Text('history')),
          ),
        ),
      );
      expect(find.text('conversations'), findsOneWidget);
      expect(find.text('history'), wide ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('global paste shortcut leaves multiline Chinese paste in composer', (tester) async {
    final clipboard = <String, dynamic>{'text': '第一行\n第二行🙂'};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return clipboard;
      if (call.method == 'Clipboard.hasStrings') return {'value': true};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      MaterialApp(
        home: ShortcutWatcher(
          child: Scaffold(body: ChatComposer(enabled: true, onSend: (_) async {})),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('第一行\n第二行🙂'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
