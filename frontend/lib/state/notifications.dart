import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api.dart';

/// Unread notification badge. Polls in the background without keeping an
/// idle session alive (the X-Background header).
class NotificationsState extends ChangeNotifier {
  int unread = 0;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unread = 0;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (api.token == null) return;
    try {
      final r = await api.get('/notifications/unread-count', background: true);
      final n = (r['unread'] as num?)?.toInt() ?? 0;
      if (n != unread) {
        unread = n;
        notifyListeners();
      }
    } catch (_) {}
  }

  void setUnread(int n) {
    unread = n;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
