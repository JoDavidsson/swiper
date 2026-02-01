import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'api_providers.dart';
import 'device_context.dart';
import 'session_provider.dart';

const String _kClientSeqPrefix = 'swiper_client_seq_';
const int _kBufferFlushSize = 20;
const Duration _kBufferFlushInterval = Duration(seconds: 5);
const String _kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

/// Event names that are always sent even when analytics opt-out is enabled (minimal ML).
const Set<String> _essentialEventNames = {
  'session_start',
  'session_resume',
  'session_end',
  'deck_request',
  'deck_response',
  'swipe_left',
  'swipe_right',
  'like_add',
  'like_remove',
  'outbound_click',
  'card_impression_start',
  'card_impression_end',
  'empty_deck',
};

/// Canonical event tracker (v1). Buffers events and flushes to POST /api/events/batch.
class EventTracker {
  EventTracker(this._ref);

  final Ref _ref;
  final List<Map<String, dynamic>> _buffer = [];
  Timer? _flushTimer;
  static const _uuid = Uuid();

  /// Enqueue a v1 event. Auto-fills schemaVersion, eventId, createdAtClient, sessionId, clientSeq, app.
  /// [partial] can contain item, rank, impression, interaction, filters, onboarding, compare, share, outbound, perf, error, ext, surface.
  Future<void> track(String eventName, [Map<String, dynamic> partial = const {}]) async {
    final sessionId = _ref.read(sessionIdProvider);
    if (sessionId == null || sessionId.length < 8) return;

    final optOut = _ref.read(analyticsOptOutProvider);
    if (optOut && !_essentialEventNames.contains(eventName)) return;

    final seq = await _nextClientSeq(sessionId);
    if (seq == null) return;

    final app = _buildApp();
    final event = <String, dynamic>{
      'schemaVersion': '1.0',
      'eventId': _uuid.v4(),
      'eventName': eventName,
      'sessionId': sessionId,
      'clientSeq': seq,
      'createdAtClient': DateTime.now().toUtc().toIso8601String(),
      'app': app,
      ...partial,
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
    } catch (_) {
      _buffer.addAll(events);
    }
  }
}

final eventTrackerProvider = Provider<EventTracker>((ref) {
  return EventTracker(ref);
});
