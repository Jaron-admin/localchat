import 'package:localsend_app/util/lan_endpoint.dart';
import 'package:test/test.dart';

void main() {
  test('manual address preserves explicit port, IPv6 scope and default port', () {
    for (final example in [
      ('192.168.1.8:58723', '192.168.1.8', 58723),
      ('192.168.1.8', '192.168.1.8', 53317),
      ('[fe80::1%7]:58723', 'fe80::1%7', 58723),
      ('fe80::1%7', 'fe80::1%7', 53317),
      ('[::1]', '::1', 53317),
      (' desktop.local:50123 ', 'desktop.local', 50123),
    ]) {
      final endpoint = LanEndpoint.parse(example.$1, defaultPort: 53317);
      expect(endpoint.host, example.$2);
      expect(endpoint.port, example.$3);
      final roundtrip = LanEndpoint.parse(endpoint.address, defaultPort: 1234);
      expect(roundtrip.host, endpoint.host);
      expect(roundtrip.port, endpoint.port);
    }
  });
  test('malformed endpoints cannot silently use a different port', () {
    for (final input in ['', 'host:0', 'host:65536', 'host:no', 'host:', '[::1', '[]:42', 'http://host:42', 'a/b', 'a@b', 'a b']) {
      expect(() => LanEndpoint.parse(input, defaultPort: 53317), throwsFormatException, reason: input);
    }
  });
}
