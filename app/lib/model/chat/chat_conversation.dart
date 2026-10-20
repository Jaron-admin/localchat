class ChatConversation {
  final String id;
  final String peerFingerprint;
  final int lastActivity;
  final int unreadCount;
  const ChatConversation({required this.id, required this.peerFingerprint, required this.lastActivity, required this.unreadCount});
}
