enum ChatPermission { unknown, pending, allowed, denied, blocked }

class ChatPeer {
  final String fingerprint;
  final String alias;
  final String? platform;
  final String? host;
  final int? port;
  final int? lastSeen;
  final bool isOwnDevice;
  final ChatPermission localPermission;
  final ChatPermission remotePermission;
  const ChatPeer({
    required this.fingerprint,
    required this.alias,
    this.platform,
    this.host,
    this.port,
    this.lastSeen,
    this.isOwnDevice = false,
    this.localPermission = ChatPermission.unknown,
    this.remotePermission = ChatPermission.unknown,
  });
}
