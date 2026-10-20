import 'dart:io';

/// A manually entered LAN host with an optional port. Brackets disambiguate
/// IPv6 + port; an unbracketed IPv6 address always uses the default port.
class LanEndpoint {
  final String host;
  final int port;
  const LanEndpoint(this.host, this.port);

  String get address => '${host.contains(':') ? '[$host]' : host}:$port';

  factory LanEndpoint.parse(String input, {required int defaultPort}) {
    var host = input.trim();
    var port = defaultPort;
    String? explicitPort;
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      if (end < 0) throw const FormatException('Invalid bracketed IP address');
      final suffix = host.substring(end + 1);
      if (suffix.isNotEmpty) {
        if (!suffix.startsWith(':')) throw const FormatException('Invalid address suffix');
        explicitPort = suffix.substring(1);
      }
      host = host.substring(1, end);
      if (!host.contains(':')) throw const FormatException('Brackets require IPv6');
    } else if (':'.allMatches(host).length == 1) {
      final separator = host.indexOf(':');
      explicitPort = host.substring(separator + 1);
      host = host.substring(0, separator);
    }
    if (explicitPort != null) {
      if (!RegExp(r'^\d+$').hasMatch(explicitPort)) throw const FormatException('Invalid port');
      port = int.tryParse(explicitPort) ?? 0;
    }
    if (port < 1 || port > 65535) throw const FormatException('Port must be 1–65535');
    if (host.contains(':')) {
      final scoped = host.split('%');
      if (scoped.length > 2 ||
          (scoped.length == 2 && !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(scoped[1])) ||
          InternetAddress.tryParse(scoped.first)?.type != InternetAddressType.IPv6) {
        throw const FormatException('Invalid IPv6 address');
      }
    } else if (!RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$').hasMatch(host)) {
      throw const FormatException('Invalid LAN host');
    }
    return LanEndpoint(host, port);
  }
}
