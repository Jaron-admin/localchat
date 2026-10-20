import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_attachment.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';

class ChatAttachmentCard extends StatelessWidget {
  final ChatAttachment attachment;
  final bool outgoing;
  final double? progress;
  final VoidCallback? onOpen, onCancel, onReselect;
  const ChatAttachmentCard({required this.attachment, required this.outgoing, this.progress, this.onOpen, this.onCancel, this.onReselect, super.key});

  @override
  Widget build(BuildContext context) {
    final label = switch (attachment.state) {
      AttachmentState.offered => t.chat.fileOffered,
      AttachmentState.waiting => t.chat.fileWaiting,
      AttachmentState.transferring => t.chat.fileTransferring,
      AttachmentState.complete => outgoing ? t.chat.fileSent : t.chat.fileSaved,
      AttachmentState.rejected => t.chat.fileRejected,
      AttachmentState.cancelled => t.chat.fileCancelled,
      AttachmentState.failed => t.chat.fileFailed,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(attachment.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
                if (onCancel != null) IconButton(tooltip: t.chat.cancelTransfer, onPressed: onCancel, icon: const Icon(Icons.close)),
              ],
            ),
            Text(attachment.size.asReadableFileSize),
            Text(label),
            if (attachment.state == AttachmentState.transferring)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: progress?.clamp(0, 1)),
              ),
            if (onOpen != null)
              TextButton(onPressed: onOpen, child: Text(attachment.state == AttachmentState.complete ? t.chat.openFile : t.chat.viewTransfer)),
            if (outgoing &&
                onReselect != null &&
                {AttachmentState.failed, AttachmentState.cancelled, AttachmentState.rejected}.contains(attachment.state))
              TextButton(onPressed: onReselect, child: Text(t.chat.chooseFileAgain)),
          ],
        ),
      ),
    );
  }
}
