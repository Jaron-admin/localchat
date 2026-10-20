import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/model/chat/chat_message.dart';
import 'package:localsend_app/widget/chat/chat_attachment_card.dart';

void main() {
  ChatAttachment file(AttachmentState state) => ChatAttachment(
    attachmentId: 'attachment',
    messageKey: const MessageKey('peer', 'message'),
    transferId: 'transfer',
    sessionId: 'session',
    fileId: 'file',
    name: '局域网.txt',
    size: 4096,
    state: state,
  );
  testWidgets('only actual file completion displays sent or saved', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatAttachmentCard(attachment: file(AttachmentState.waiting), outgoing: true)),
      ),
    );
    expect(find.text('Waiting for transfer'), findsOneWidget);
    expect(find.text('File sent'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatAttachmentCard(attachment: file(AttachmentState.complete), outgoing: false)),
      ),
    );
    expect(find.text('File saved'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('in-flight file shows progress and explicit whole-transfer cancellation', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAttachmentCard(attachment: file(AttachmentState.transferring), outgoing: true, progress: .25, onCancel: () => cancelled++),
        ),
      ),
    );
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .25);
    await tester.tap(find.byTooltip('Cancel transfer'));
    expect(cancelled, 1);
  });
  testWidgets('failed and rejected history never shows completed progress', (tester) async {
    for (final state in [AttachmentState.failed, AttachmentState.rejected, AttachmentState.cancelled]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 260, child: ChatAttachmentCard(attachment: file(state), outgoing: true, progress: 1)),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('File sent'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('failed outgoing file offers explicit selection for a new message', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAttachmentCard(
            attachment: file(AttachmentState.failed),
            outgoing: true,
            onReselect: () => selected++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose file again'));
    expect(selected, 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
