import 'package:localsend_app/provider/chat/chat_transport.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum ChatCapabilityKind { unknown, chat, filesOnly, encryptionRequired }

class ChatCapability {
  final ChatCapabilityKind kind;
  final Set<String> features;
  const ChatCapability(this.kind, [this.features = const {}]);
}

final chatCapabilitiesProvider = Provider((ref) => ChatCapabilitiesService(ref.read(chatTransportProvider)));

class ChatCapabilitiesService {
  final ChatTransport transport;
  final _cache = <String, (DateTime, ChatCapability)>{};
  final _pending = <String, Future<ChatCapability>>{};
  int _generation = 0;
  ChatCapabilitiesService(this.transport);
  String _key(Device d) => '${d.fingerprint}|${d.ip}|${d.port}|${d.https}';
  void clear() {
    _generation++;
    _cache.clear();
    _pending.clear();
  }

  Future<ChatCapability> probe(Device device) {
    if (!device.https) return Future.value(const ChatCapability(ChatCapabilityKind.encryptionRequired));
    final key = _key(device);
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) return Future.value(cached.$2);
    if (_pending.containsKey(key)) return _pending[key]!;
    if (_pending.length >= 64) return Future.value(const ChatCapability(ChatCapabilityKind.unknown));
    final generation = _generation;
    final future = _probe(device)
        .then((value) {
          if (_generation == generation && value.kind != ChatCapabilityKind.unknown) {
            if (_cache.length >= 200) _cache.remove(_cache.keys.first);
            _cache[key] = (DateTime.now(), value);
          }
          return value;
        })
        .whenComplete(() {
          if (_generation == generation) {
            // Evicting the cached Future does not create a new operation.
            // ignore: discarded_futures
            _pending.remove(key);
          }
        });
    _pending[key] = future;
    return future;
  }

  Future<ChatCapability> _probe(Device device) async {
    try {
      final response = await transport.capabilities(device);
      return response.version == 1 && response.features.contains('text') && response.maxTextBytes >= 32768
          ? ChatCapability(ChatCapabilityKind.chat, response.features.toSet())
          : const ChatCapability(ChatCapabilityKind.filesOnly);
    } on ChatTransportException catch (e) {
      return ChatCapability(e.status == 404 ? ChatCapabilityKind.filesOnly : ChatCapabilityKind.unknown);
    } catch (_) {
      return const ChatCapability(ChatCapabilityKind.unknown);
    }
  }
}
