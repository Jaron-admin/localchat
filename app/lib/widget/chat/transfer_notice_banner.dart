import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/chat/transfer_notice_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

class TransferNoticeBanner extends StatelessWidget {
  const TransferNoticeBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final service = context.read(transferNoticeProvider);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => service.sessionId == null
          ? const SizedBox.shrink()
          : Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.file_download_outlined),
                title: Text(t.chat.transferActive),
                trailing: TextButton(onPressed: service.routeOpen ? null : service.open, child: Text(t.chat.viewTransfer)),
              ),
            ),
    );
  }
}
