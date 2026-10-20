import 'package:localsend_app/provider/chat/chat_capabilities_provider.dart';
import 'package:localsend_app/provider/chat/chat_transport.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart' as wire;
import 'package:test/test.dart';

class CapabilityTransport implements ChatTransport {
  int calls = 0;
  ChatTransportException? failure;
  @override
  Future<wire.ChatCapabilities> capabilities(Device device) async {
    calls++;
    if (failure != null) throw failure!;
    return const wire.ChatCapabilities(version: 1, features: ['text', 'file-ref'], maxTextBytes: 32768);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('network/TLS failure remains unknown, only explicit 404 caches legacy', () async {
    final transport = CapabilityTransport();
    final cache = ChatCapabilitiesService(transport);
    final device = Device.empty.copyWith(fingerprint: 'peer', ip: '127.0.0.1', port: 53317, https: true);
    transport.failure = const ChatTransportException('network');
    expect((await cache.probe(device)).kind, ChatCapabilityKind.unknown);
    transport.failure = null;
    expect((await cache.probe(device)).kind, ChatCapabilityKind.chat);
    cache.clear();
    transport.failure = const ChatTransportException('unsupported', retryable: false, status: 404);
    expect((await cache.probe(device)).kind, ChatCapabilityKind.filesOnly);
    final calls = transport.calls;
    await cache.probe(device);
    expect(transport.calls, calls);
  });
}
