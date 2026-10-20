import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../../mocks.mocks.dart';

class _UnusedIsolate implements IsolateController {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('No network in this clock test');
}

void main() {
  test('only fresh confirmations keep a peer online; late failures cannot hide a new endpoint', () async {
    var now = DateTime.fromMillisecondsSinceEpoch(0);
    final container = RefenaContainer(
      overrides: [
        persistenceProvider.overrideWithValue(MockPersistenceService()),
        nearbyDevicesProvider.overrideWithNotifier(
          (ref) => NearbyDevicesService(
            isolateController: _UnusedIsolate(),
            favoriteService: ref.notifier(favoritesProvider),
            discoveryLogs: DiscoveryLogger(),
            now: () => now,
          ),
        ),
      ],
    );
    addTearDown(container.disposeContainer);
    final reducer = container.redux(nearbyDevicesProvider);
    final first = Device.empty.copyWith(fingerprint: 'B' * 64, ip: '192.168.1.9', port: 58723, https: true);
    await reducer.dispatchAsync(RegisterDeviceAction(first));
    now = now.add(const Duration(seconds: 89));
    reducer.dispatch(ExpireNearbyDevicesAction());
    expect(container.read(nearbyDevicesProvider).devices[first.fingerprint], first);
    now = now.add(const Duration(seconds: 2));
    reducer.dispatch(ExpireNearbyDevicesAction());
    expect(container.read(nearbyDevicesProvider).devices, isEmpty);

    await reducer.dispatchAsync(RegisterDeviceAction(first));
    now = now.add(const Duration(seconds: 60));
    final refreshed = first.copyWith(port: 60000);
    await reducer.dispatchAsync(RegisterDeviceAction(refreshed));
    reducer.dispatch(MarkDeviceUnavailableAction(first));
    now = now.add(const Duration(seconds: 60));
    reducer.dispatch(ExpireNearbyDevicesAction());
    expect(container.read(nearbyDevicesProvider).devices[first.fingerprint], refreshed);
    reducer.dispatch(MarkDeviceUnavailableAction(refreshed));
    expect(container.read(nearbyDevicesProvider).devices, isEmpty);
  });
}
