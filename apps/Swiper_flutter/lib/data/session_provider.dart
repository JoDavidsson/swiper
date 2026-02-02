import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'api_client.dart';
import 'device_context.dart';

/// Session ID stored locally after POST /api/session.
final sessionIdProvider = StateProvider<String?>((ref) => null);

/// Admin auth: True when user has passed admin login (Google or legacy password).
final adminAuthProvider = StateProvider<bool>((ref) => false);

/// Admin Firebase ID token; sent on admin API requests. Null when using password only.
final adminIdTokenProvider = StateProvider<String?>((ref) => null);

/// Admin password; sent as X-Admin-Password on admin API requests when no token (password-only login).
final adminPasswordProvider = StateProvider<String?>((ref) => null);

/// Keys for local storage.
const String kSessionIdKey = 'swiper_session_id';
const String kAdminAuthKey = 'swiper_admin_auth';
const String kAnalyticsOptOutKey = 'swiper_analytics_opt_out';
const String kSwipeHintSeenKey = 'swiper_swipe_hint_seen';

/// Current surface (route context) for event tracking. Set by each screen so events carry surface.name when not explicitly provided.
final currentSurfaceProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

/// Analytics opt-out: when true, skip non-essential event logging (open_detail, filter_change, etc.).
final analyticsOptOutProvider = StateNotifierProvider<AnalyticsOptOutNotifier, bool>((ref) => AnalyticsOptOutNotifier());
final swipeHintSeenProvider = StateNotifierProvider<SwipeHintSeenNotifier, bool>((ref) => SwipeHintSeenNotifier());

class AnalyticsOptOutNotifier extends StateNotifier<bool> {
  AnalyticsOptOutNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      final value = box.get(kAnalyticsOptOutKey);
      state = value == true;
    } catch (_) {
      state = false;
    }
  }

  Future<void> setOptOut(bool value) async {
    if (state == value) return;
    try {
      final box = await Hive.openBox('swiper_prefs');
      await box.put(kAnalyticsOptOutKey, value);
      state = value;
    } catch (_) {}
  }
}

class SwipeHintSeenNotifier extends StateNotifier<bool> {
  SwipeHintSeenNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      final value = box.get(kSwipeHintSeenKey);
      state = value == true;
    } catch (_) {
      state = false;
    }
  }

  Future<void> markSeen() async {
    if (state) return;
    try {
      final box = await Hive.openBox('swiper_prefs');
      await box.put(kSwipeHintSeenKey, true);
      state = true;
    } catch (_) {}
  }
}

/// Load session ID from Hive on startup (call from app init).
Future<String?> loadStoredSessionId() async {
  try {
    final box = await Hive.openBox('swiper_prefs');
    return box.get(kSessionIdKey) as String?;
  } catch (_) {
    return null;
  }
}

/// Persist session ID.
Future<void> saveSessionId(String sessionId) async {
  final box = await Hive.openBox('swiper_prefs');
  await box.put(kSessionIdKey, sessionId);
}

/// Clear session (e.g. logout).
Future<void> clearSessionId() async {
  final box = await Hive.openBox('swiper_prefs');
  await box.delete(kSessionIdKey);
}

/// Ensure a session exists (e.g. before onboarding so completion can be logged). Idempotent.
Future<void> ensureSession(dynamic ref, ApiClient client) async {
  var sid = await loadStoredSessionId();
  if (sid != null && sid.isNotEmpty) {
    ref.read(sessionIdProvider.notifier).state = sid;
    return;
  }
  final body = DeviceContext.toSessionBody();
  final res = await client.createSession(body: body);
  sid = res['sessionId'] as String?;
  if (sid != null) {
    await saveSessionId(sid);
    ref.read(sessionIdProvider.notifier).state = sid;
  }
}
