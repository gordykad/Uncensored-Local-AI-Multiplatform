import 'dart:async';

import 'package:get/get.dart';

import '../routes/app_routes.dart';

/// One narrated admin action (ticket 24).
class AdminActivityEvent {
  final DateTime at;
  final String label;
  const AdminActivityEvent(this.at, this.label);
}

/// See-Astro-drive (ticket 24): every admin action Astro takes through
/// the ticket-21 API is narrated on screen — a session pulls Kai to
/// the chat page once, and every action (reads included: no silent
/// reads) raises a small toast there and lands in the Remote Activity
/// list on the API screen. The token value never appears in a label.
class AdminActivityService extends GetxService {
  static const _sessionGap = Duration(minutes: 10);
  static const _toastLife = Duration(seconds: 4);

  final events = <AdminActivityEvent>[].obs;
  final toasts = <AdminActivityEvent>[].obs;
  final lastEventAt = Rx<DateTime?>(null);

  final _toastTimers = <AdminActivityEvent, Timer>{};

  bool get sessionWarm {
    final last = lastEventAt.value;
    return last != null && DateTime.now().difference(last) < _sessionGap;
  }

  /// Record an admin action. The first action after an idle gap opens
  /// a session: Kai is taken to the chat page and told Astro connected.
  void note(String label) {
    final now = DateTime.now();
    if (!sessionWarm) {
      _record(AdminActivityEvent(now, 'Astro connected'));
      _goToChat();
    }
    lastEventAt.value = now;
    _record(AdminActivityEvent(now, label));
  }

  /// Session bookkeeping for an action whose label is recorded later
  /// (e.g. a load, which is narrated when it lands).
  void touchSession() {
    final now = DateTime.now();
    if (!sessionWarm) {
      _record(AdminActivityEvent(now, 'Astro connected'));
      _goToChat();
    }
    lastEventAt.value = now;
  }

  /// Token regeneration invalidates the session along with the token.
  void endSession() {
    lastEventAt.value = null;
  }

  void _record(AdminActivityEvent event) {
    events.add(event);
    while (events.length > 60) {
      events.removeAt(0);
    }
    // Toasts: at most two on screen; the oldest yields.
    while (toasts.length >= 2) {
      final dropped = toasts.removeAt(0);
      _toastTimers.remove(dropped)?.cancel();
    }
    toasts.add(event);
    _toastTimers[event] = Timer(_toastLife, () {
      toasts.remove(event);
      _toastTimers.remove(event);
    });
  }

  void _goToChat() {
    try {
      if (Get.currentRoute != AppRoutes.home) {
        Get.toNamed(AppRoutes.home);
      }
    } catch (_) {
      // Navigation is best-effort — narration never breaks the API.
    }
  }

  @override
  void onClose() {
    for (final t in _toastTimers.values) {
      t.cancel();
    }
    super.onClose();
  }
}
