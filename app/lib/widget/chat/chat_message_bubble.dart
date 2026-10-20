import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_message.dart';

String deliveryLabel(DeliveryState state) => switch (state) {
  DeliveryState.queued => t.chat.queued,
  DeliveryState.sending => t.chat.sending,
  DeliveryState.delivered => t.chat.delivered,
  DeliveryState.unconfirmed => t.chat.unconfirmed,
  DeliveryState.failed => t.chat.failed,
  DeliveryState.rejected => t.chat.rejected,
};

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;
  final Widget? attachment;
  const ChatMessageBubble({required this.message, this.onRetry, this.attachment, super.key});
  @override
  Widget build(BuildContext context) {
    final outgoing = message.direction == MessageDirection.outgoing;
    final colors = Theme.of(context).colorScheme;
    // Wire timestamps are signed i64; DateTime supports a smaller range. Keep
    // even previously saved hostile timestamps readable without altering order.
    final time = message.sentAtMs >= -8640000000000000 && message.sentAtMs <= 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(message.sentAtMs).toLocal()
        : null;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: outgoing ? colors.primaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment != null) attachment! else SelectableText(message.text ?? t.chat.transferActive),
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  time == null ? '—' : '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (outgoing && message.kind == MessageKind.text)
                  Tooltip(
                    message: message.deliveryState == DeliveryState.delivered ? t.chat.receiptHint : deliveryLabel(message.deliveryState),
                    child: Text(deliveryLabel(message.deliveryState), style: Theme.of(context).textTheme.labelSmall),
                  ),
                if (onRetry != null && message.deliveryState == DeliveryState.unconfirmed && message.attemptCount >= 4)
                  TextButton(onPressed: onRetry, child: Text(t.chat.retry)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
