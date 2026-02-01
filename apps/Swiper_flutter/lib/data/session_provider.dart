import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Session ID stored locally after POST /api/session.
final sessionIdProvider = StateProvider<String?>((ref) => null);

/// Admin auth: MVP password gate. True when user has passed admin login.
final adminAuthProvider = StateProvider<bool>((ref) => false);

/// Keys for local storage.
const String kSessionIdKey = 'swiper_session_id';
const String kAdminAuthKey = 'swiper_admin_auth';

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
