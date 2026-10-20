import 'dart:async';
import 'package:flutter/material.dart';
import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_app/pages/progress_page.dart';
import 'package:localsend_app/provider/chat/transfer_notice_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/widget/chat/chat_attachment_card.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/file_path_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Progress is sampled at most ten times per second and never written to SQLite.
class ChatLiveAttachment extends StatefulWidget {
  final ChatAttachment file;
  final bool outgoing;
  final VoidCallback? onReselect;
  const ChatLiveAttachment({required this.file, required this.outgoing, this.onReselect, super.key});
  @override
  State<ChatLiveAttachment> createState() => _ChatLiveAttachmentState();
}

class _ChatLiveAttachmentState extends State<ChatLiveAttachment> with Refena {
  Timer? _timer;
  double? _progress;
  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(covariant ChatLiveAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTimer();
  }

  void _updateTimer() {
    _timer?.cancel();
    if (widget.file.state != AttachmentState.transferring) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || widget.file.sessionId == null) return;
      final value = ref.read(fileTransferProvider).getProgress(sessionId: widget.file.sessionId!, fileId: widget.file.fileId);
      if (value != _progress) setState(() => _progress = value);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final send = ref.watch(sendProvider)[file.sessionId];
    final candidate = ref.watch(serverProvider)?.session;
    final receive = candidate?.sessionId == file.sessionId ? candidate : null;
    final active = {AttachmentState.offered, AttachmentState.waiting, AttachmentState.transferring}.contains(file.state);
    VoidCallback? open;
    if (file.state == AttachmentState.complete && file.localPath != null) {
      open = () => openFile(context, file.name.guessFileType(), file.localPath!);
    } else if (receive != null && ref.read(transferNoticeProvider).sessionId == file.sessionId) {
      open = () => ref.read(transferNoticeProvider).open();
    } else if (send != null && send.status != SessionStatus.waiting) {
      open = () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProgressPage(showAppBar: true, closeSessionOnClose: false, returnToPrevious: true, sessionId: send.sessionId),
        ),
      );
    }
    return ChatAttachmentCard(
      attachment: file,
      outgoing: widget.outgoing,
      progress: _progress,
      onOpen: open,
      onReselect: widget.onReselect,
      onCancel: !active || (send == null && receive == null)
          ? null
          : () {
              if (send != null) {
                ref.notifier(sendProvider).cancelSession(send.sessionId);
              } else if (ref.read(serverProvider)?.session?.sessionId == file.sessionId) {
                if (receive!.status == SessionStatus.waiting) {
                  ref.notifier(serverProvider).declineFileRequest();
                } else {
                  ref.notifier(serverProvider).cancelSession();
                }
              }
            },
    );
  }
}
