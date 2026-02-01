import 'dart:ui' show PlatformDispatcher;

import 'device_context_web.dart' if (dart.library.io) 'device_context_io.dart' as platform_impl;

/// Anonymous device/context for session creation. No PII.
class DeviceContext {
  DeviceContext._();

  static String get platform => platform_impl.platform;

  /// Locale string, e.g. "en_US" or "sv", max 20 chars.
  static String get locale {
    try {
      final loc = PlatformDispatcher.instance.locale;
      final country = loc.countryCode;
      final s = '${loc.languageCode}${(country != null && country.isNotEmpty) ? '_$country' : ''}';
      return s.length > 20 ? s.substring(0, 20) : s;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Screen size bucket: small (<600), medium (<900), large (>=900). Null if unknown.
  static String? get screenBucket {
    try {
      final views = PlatformDispatcher.instance.views;
      if (views.isEmpty) return null;
      final view = views.first;
      final physical = view.physicalSize;
      final ratio = view.devicePixelRatio;
      if (ratio <= 0) return null;
      final logicalWidth = physical.width / ratio;
      if (logicalWidth < 600) return 'small';
      if (logicalWidth < 900) return 'medium';
      return 'large';
    } catch (_) {
      return null;
    }
  }

  /// Timezone offset in minutes (e.g. 60 for UTC+1).
  static int get timezoneOffsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  /// Map suitable for POST /api/session body (only non-null values).
  static Map<String, dynamic> toSessionBody() {
    final map = <String, dynamic>{
      'locale': locale,
      'platform': platform,
      'timezoneOffsetMinutes': timezoneOffsetMinutes,
    };
    final bucket = screenBucket;
    if (bucket != null) map['screenBucket'] = bucket;
    return map;
  }
}
