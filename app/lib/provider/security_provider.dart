import 'dart:async';

import 'package:localsend_app/provider/chat/chat_outbox_provider.dart';
import 'package:localsend_app/provider/chat/chat_repository_provider.dart';
import 'package:localsend_app/provider/chat/chat_runtime_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/util/security_helper.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/stored_security_context.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// This provider manages the [StoredSecurityContext].
/// It contains all the security related data for HTTPS communication.
final ReduxProvider<SecurityService, StoredSecurityContext> securityProvider = ReduxProvider<SecurityService, StoredSecurityContext>(
  (ref) {
    return SecurityService(
      ref.read(persistenceProvider),
      prepareIdentity: (fingerprint) async {
        ref.read(chatRuntimeProvider).pause();
        await ref.read(chatOutboxProvider).waitForIdle();
        await ref.notifier(serverProvider).stopServer();
        await ref.read(chatRepositoryProvider).changeLocalIdentity(fingerprint);
      },
    );
  },
  onChanged: (_, next, ref) {
    ref.redux(parentIsolateProvider).dispatch(IsolateSyncSecurityContextAction(securityContext: next));
    ref.read(chatRuntimeProvider).clearCapabilityCache();
    unawaited(ref.notifier(serverProvider).startServerFromSettings().then((_) => ref.read(chatRuntimeProvider).resume()).catchError((Object _) {}));
  },
);

class SecurityService extends ReduxNotifier<StoredSecurityContext> {
  final PersistenceService _persistence;
  final Future<void> Function(String)? _prepareIdentity;

  SecurityService(this._persistence, {Future<void> Function(String)? prepareIdentity}) : _prepareIdentity = prepareIdentity;

  @override
  StoredSecurityContext init() {
    return _persistence.getSecurityContext();
  }
}

/// Generates a new [StoredSecurityContext] and persists it.
class ResetSecurityContextAction extends AsyncReduxAction<SecurityService, StoredSecurityContext> {
  @override
  Future<StoredSecurityContext> reduce() async {
    final securityContext = await generateSecurityContext();
    await notifier._prepareIdentity?.call(securityContext.certificateHash);
    await notifier._persistence.setSecurityContext(securityContext);
    return securityContext;
  }
}
