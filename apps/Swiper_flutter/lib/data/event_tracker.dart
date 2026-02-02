import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'api_providers.dart';
import 'device_context.dart';
import 'session_provider.dart';

// #region agent log
void _agentLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
  if (!kDebugMode) return;
  try {
    final payload = {
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sessionId': 'debug-session',
      'hypothesisId': hypothesisId,
    };
    Dio().post(
      'http://127.0.0.1:7245/ingest/ddc9e3c2-ad47-4244-9d77-ce2efa8256ba',
      data: payload,
      options: Options(sendTimeout: const Duration(milliseconds: 500), receiveTimeout: const Duration(milliseconds: 500)),
    ).catchError((_) => Future.value(Response(requestOptions: RequestOptions(path: 'agent_ingest'))));
  } catch (_) {}
}
// #endregion

const String _kClientSeqPrefix = 'swiper_client_seq_';
const int _kBufferFlushSize = 20;
const Duration _kBufferFlushInterval = Duration(seconds: 5);
const String _kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

/// Event names that are always sent even when analytics opt-out is enabled (minimal ML).
const Set<String> _essentialEventNames = {
  'app_open',
  'session_start',
  'session_resume',
  'session_end',
  'deck_request',
  'deck_response',
  'deck_refresh',
  'swipe_left',
  'swipe_right',
  'like_add',
  'like_remove',
  'likes_open',
  'outbound_click',
  'card_impression_start',
  'card_impression_end',
  'empty_deck',
  'consent_updated',
};

/// Canonical event tracker (v1). Buffers events and flushes to POST /api/events/batch.
class EventTracker {
  EventTracker(this._ref);

  final Ref _ref;
  final List<Map<String, dynamic>> _buffer = [];
  Timer? _flushTimer;
  static const _uuid = Uuid();
  bool _didEmitAppOpen = false;

  /// Enqueue a v1 event. Auto-fills schemaVersion, eventId, createdAtClient, sessionId, clientSeq, app.
  /// On first successful track() per app run, emits app_open before the requested event.
  /// [partial] can contain item, rank, impression, interaction, filters, onboarding, compare, share, outbound, perf, error, ext, surface.
  Future<void> track(String eventName, [Map<String, dynamic> partial = const {}]) async {
    final sessionId = _ref.read(sessionIdProvider);
    final optOut = _ref.read(analyticsOptOutProvider);
    // #region agent log
    _agentLog('event_tracker.dart:track', 'track_entry', {'eventName': eventName, 'sessionIdLen': sessionId?.length ?? 0, 'optOut': optOut}, 'H1');
    // #endregion
    if (sessionId == null || sessionId.length < 8) {
      // #region agent log
      _agentLog('event_tracker.dart:track', 'track_early_return', {'reason': 'sessionId', 'eventName': eventName}, 'H1');
      // #endregion
      return;
    }

    if (optOut && !_essentialEventNames.contains(eventName)) {
      // #region agent log
      _agentLog('event_tracker.dart:track', 'track_early_return_optout', {'eventName': eventName}, 'H2');
      // #endregion
      return;
    }

    // Emit app_open once per app run on first event that has a session.
    if (!_didEmitAppOpen) {
      _didEmitAppOpen = true;
      final appOpenSeq = await _nextClientSeq(sessionId);
      if (appOpenSeq != null) {
        final app = _buildApp();
        _buffer.add(<String, dynamic>{
          'schemaVersion': '1.0',
          'eventId': _uuid.v4(),
          'eventName': 'app_open',
          'sessionId': sessionId,
          'clientSeq': appOpenSeq,
          'createdAtClient': DateTime.now().toUtc().toIso8601String(),
          'app': app,
        });
        // #region agent log
        _agentLog('event_tracker.dart:track', 'app_open_emitted', {'clientSeq': appOpenSeq}, 'H3');
        // #endregion
      }
    }

    final seq = await _nextClientSeq(sessionId);
    if (seq == null) return;

    final app = _buildApp();
    final merged = Map<String, dynamic>.from(partial);
    if (!merged.containsKey('surface')) {
      final surface = _ref.read(currentSurfaceProvider);
      if (surface != null) merged['surface'] = surface;
    }
    // #region agent log
    _agentLog('event_tracker.dart:track', 'event_queued', {'eventName': eventName, 'hasSurface': merged.containsKey('surface')}, 'H4');
    // #endregion
    final event = <String, dynamic>{
      'schemaVersion': '1.0',
      'eventId': _uuid.v4(),
      'eventName': eventName,
      'sessionId': sessionId,
      'clientSeq': seq,
      'createdAtClient': DateTime.now().toUtc().toIso8601String(),
      'app': app,
      ...merged,
    };

    _buffer.add(event);

    if (_buffer.length >= _kBufferFlushSize) {
      await _flush();
    } else {
      _flushTimer ??= Timer(_kBufferFlushInterval, () {
        _flush();
        _flushTimer = null;
      });
    }
  }

  /// Flush buffer to server. Call on session_background / before unload.
  Future<void> flush() => _flush();

  Future<int?> _nextClientSeq(String sessionId) async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      final key = '$_kClientSeqPrefix$sessionId';
      final current = (box.get(key) as int?) ?? 0;
      final next = current + 1;
      await box.put(key, next);
      return next;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _buildApp() {
    return {
      'platform': DeviceContext.platform,
      'appVersion': _kAppVersion,
      'locale': DeviceContext.locale,
      'timezoneOffsetMinutes': DeviceContext.timezoneOffsetMinutes,
      'screenBucket': DeviceContext.screenBucketSchema,
    };
  }

  Future<void> _flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;

    final events = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();

    try {
      final client = _ref.read(apiClientProvider);
      await client.postEventsBatch(events);
    } catch (e) {
      // #region agent log
      _agentLog('event_tracker.dart:_flush', 'flush_failed', {'eventCount': events.length, 'error': e.runtimeType.toString()}, 'H5');
      // #endregion
      _buffer.addAll(events);
    }
  }
}

final eventTrackerProvider = Provider<EventTracker>((ref) {
  return EventTracker(ref);
});
