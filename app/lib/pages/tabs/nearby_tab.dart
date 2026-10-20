import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/device_details_page.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/provider/chat/chat_capabilities_provider.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/widget/chat/peer_address_header.dart';
import 'package:localsend_app/widget/dialogs/address_input_dialog.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class NearbyTab extends StatefulWidget {
  const NearbyTab({super.key});
  @override
  State<NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<NearbyTab> with Refena {
  @override
  void initState() {
    super.initState();
    ensureRef((ref) => unawaited(ref.global.dispatchAsync(StartSmartScan())));
  }

  Future<void> _open(Device device) async {
    try {
      final capability = await ref.read(chatCapabilitiesProvider).probe(device);
      if (!mounted) return;
      if (capability.kind != ChatCapabilityKind.chat) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              capability.kind == ChatCapabilityKind.filesOnly
                  ? t.chat.filesOnly
                  : capability.kind == ChatCapabilityKind.encryptionRequired
                  ? t.chat.peerEncryptionRequired
                  : t.chat.unknownCapability,
            ),
          ),
        );
        return;
      }
      await ref.read(chatViewProvider).openPeer(device.fingerprint);
      if (mounted) ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.chat));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.chat.actionFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(homePageControllerProvider);
    final devices = ref.watch(nearbyDevicesProvider).devices.values.toList();
    final ips = ref.watch(localIpProvider).localIps;
    final port = ref.watch(serverProvider)?.port;
    final settings = ref.watch(settingsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(t.chat.nearby, style: Theme.of(context).textTheme.headlineMedium),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<NearbySection>(
            segments: [
              ButtonSegment(value: NearbySection.devices, label: Text(t.chat.devices)),
              ButtonSegment(value: NearbySection.send, label: Text(t.chat.sendFiles)),
              ButtonSegment(value: NearbySection.receive, label: Text(t.chat.receiveFiles)),
            ],
            selected: {vm.nearbySection},
            onSelectionChanged: (s) => ref.redux(homePageControllerProvider).dispatch(OpenNearbyTransferAction(s.single)),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (vm.nearbySection) {
            NearbySection.send => const SendTab(),
            NearbySection.receive => const ReceiveTab(),
            NearbySection.devices => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ExpansionTile(
                  title: Text(settings.alias),
                  subtitle: Text(ips.isEmpty ? t.chat.unknownAddress : formatChatAddress(ips.first, port)),
                  leading: const Icon(Icons.devices),
                  children: [
                    ListTile(title: Text(t.chat.localAddresses), subtitle: SelectableText(ips.map((ip) => formatChatAddress(ip, port)).join('\n'))),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => ref.global.dispatchAsync(StartSmartScan()),
                      icon: const Icon(Icons.refresh),
                      label: Text(t.chat.refresh),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final device = await showDialog<Device>(context: context, builder: (_) => const AddressInputDialog());
                        if (device != null && mounted) {
                          await ref.redux(nearbyDevicesProvider).dispatchAsync(RegisterDeviceAction(device));
                          if (mounted) await _open(device);
                        }
                      },
                      icon: const Icon(Icons.add_link),
                      label: Text(t.chat.connect),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (devices.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t.chat.noDevices)),
                for (final device in devices) NearbyDeviceTile(device: device, onOpen: () => _open(device)),
              ],
            ),
          },
        ),
      ],
    );
  }
}

class NearbyDeviceTile extends StatelessWidget {
  final Device device;
  final VoidCallback onOpen;
  const NearbyDeviceTile({required this.device, required this.onOpen, super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<ChatCapability>(
    future: context.read(chatCapabilitiesProvider).probe(device),
    builder: (context, snapshot) => DeviceListTile(
      device: device,
      info: snapshot.data?.kind == ChatCapabilityKind.filesOnly ? t.chat.filesOnly : null,
      onTap: onOpen,
      onDetailsTap: () => context.push(() => DeviceDetailsPage(device: device)),
    ),
  );
}
