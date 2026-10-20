import 'package:flutter/foundation.dart';
import 'package:refena_flutter/refena_flutter.dart' hide ChangeNotifier;

final transferNoticeProvider = Provider((ref) => TransferNoticeService());

/// A pending file request remains in the existing file engine; this is only its non-disruptive UI entry.
class TransferNoticeService extends ChangeNotifier {
  String? sessionId;
  Future<void> Function()? _open;
  bool routeOpen = false;
  void offer(String id, Future<void> Function() open) {
    sessionId = id;
    _open = open;
    routeOpen = false;
    notifyListeners();
  }

  Future<void> open() async {
    if (routeOpen || _open == null) return;
    final id = sessionId;
    routeOpen = true;
    notifyListeners();
    try {
      await _open!();
    } finally {
      if (sessionId == id) {
        routeOpen = false;
        notifyListeners();
      }
    }
  }

  void clear(String id) {
    if (sessionId != id) return;
    sessionId = null;
    _open = null;
    routeOpen = false;
    notifyListeners();
  }
}
