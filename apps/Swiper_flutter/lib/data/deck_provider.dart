import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'api_providers.dart';
import 'device_context.dart';
import 'event_tracker.dart';
import 'models/item.dart';
import 'session_provider.dart';

export 'api_providers.dart' show apiClientProvider;
export 'api_client.dart' show DeckRankContext;

// #region agent log
void _deckAgentLog(String location, String message, Map<String, dynamic> data, [String? hypothesisId]) {
  if (!kDebugMode) return;
  try {
    final payload = {'location': location, 'message': message, 'data': data, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'sessionId': 'debug-session', 'hypothesisId': hypothesisId ?? 'H6'};
    Dio()
        .post(
          'http://127.0.0.1:7245/ingest/ddc9e3c2-ad47-4244-9d77-ce2efa8256ba',
          data: payload,
          options: Options(sendTimeout: const Duration(milliseconds: 500), receiveTimeout: const Duration(milliseconds: 500)),
        )
        .catchError((_) => Future.value(Response(requestOptions: RequestOptions(path: 'agent_ingest'))));
  } catch (_) {}
}
// #endregion

/// Admin dashboard stats. Cached so rebuilds don't create a new future (avoids infinite spinner).
final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(apiClientProvider).adminGetStats();
});

/// Current deck filters (sizeClass, colorFamily, newUsed). Empty = no filter.
final deckFiltersProvider = StateProvider<Map<String, dynamic>>((ref) => <String, dynamic>{});

final deckItemsProvider = StateNotifierProvider<DeckNotifier, AsyncValue<List<Item>>>((ref) {
  final client = ref.watch(apiClientProvider);
  final sessionId = ref.watch(sessionIdProvider);
  final filters = ref.watch(deckFiltersProvider);
  return DeckNotifier(client, ref, sessionId, filters);
});

class DeckNotifier extends StateNotifier<AsyncValue<List<Item>>> {
  DeckNotifier(this._client, this._ref, this._sessionId, this._filters) : super(const AsyncValue.loading()) {
    _load();
  }

  final ApiClient _client;
  final Ref _ref;
  String? _sessionId;
  final Map<String, dynamic> _filters;

  DeckRankContext? _rankContext;
  Map<String, double> _itemScores = const {};

  String? get sessionId => _sessionId ?? _ref.read(sessionIdProvider);
  DeckRankContext? get rankContext => _rankContext;
  Map<String, double> get itemScores => _itemScores;

  Future<void> _load({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) {
      state = const AsyncValue.loading();
    }
    // #region agent log
    _deckAgentLog('deck_provider.dart:_load', 'deck_load_start', {'showLoading': showLoading}, 'H-D2');
    if (!showLoading) {
      _deckAgentLog('deck_provider.dart:_load', 'load_no_spinner', {'skippedLoading': true}, 'H-D2');
    }
    // #endregion
    try {
      String? sid = _ref.read(sessionIdProvider);
      if (sid == null || sid.isEmpty) {
        sid = await loadStoredSessionId();
        if (mounted && sid != null) {
          _ref.read(sessionIdProvider.notifier).state = sid;
          _sessionId = sid;
        }
      }
      if (!mounted) return;
      bool didCreateSession = false;
      if (sid == null || sid.isEmpty) {
        final body = DeviceContext.toSessionBody();
        final res = await _client.createSession(body: body);
        if (!mounted) return;
        didCreateSession = true;
        sid = res['sessionId'] as String?;
        if (sid != null) {
          await saveSessionId(sid);
          if (mounted) _ref.read(sessionIdProvider.notifier).state = sid;
          _sessionId = sid;
        }
      } else {
        _sessionId = sid;
      }
      if (!mounted) return;
      if (sid == null) {
        // #region agent log
        _deckAgentLog('deck_provider.dart:_load', 'deck_no_session', {}, 'H8');
        // #endregion
        if (mounted) state = AsyncValue.error('No session', StackTrace.current);
        return;
      }

      final tracker = _ref.read(eventTrackerProvider);
      final filtersParam = _filters.isEmpty ? null : _filters;
      tracker.track('deck_request', filtersParam != null && filtersParam.isNotEmpty
          ? {'filters': {'active': _filters}}
          : {});

      final stopwatch = Stopwatch()..start();
      final response = await _client.getDeck(sessionId: sid, filters: filtersParam, limit: 10);
      stopwatch.stop();
      if (!mounted) return;

      _rankContext = response.rank;
      _itemScores = response.itemScores;

      if (mounted) {
        final currentItems = state.valueOrNull;
        if (!showLoading && currentItems != null && currentItems.isNotEmpty) {
          final existingIds = currentItems.map((i) => i.id).toSet();
          final appended = response.items.where((i) => !existingIds.contains(i.id)).toList();
          final merged = <Item>[...currentItems, ...appended];
          state = AsyncValue.data(merged);
        } else {
          state = AsyncValue.data(response.items);
          // #region agent log
          _deckAgentLog(
            'deck_provider.dart:_load',
            'deck_load_data',
            {
              'itemCount': response.items.length,
              'wasRefetch': !showLoading,
              'replaced': true,
            },
            showLoading ? 'H8' : 'H-D3',
          );
          // #endregion
        }
        tracker.track('deck_response', {
          if (response.rank != null)
            'rank': {
              'rankerRunId': response.rank!.rankerRunId,
              'algorithmVersion': response.rank!.algorithmVersion,
              if (response.rank!.variant != null) 'variant': response.rank!.variant,
              if (response.rank!.variantBucket != null) 'variantBucket': response.rank!.variantBucket,
              'itemIds': response.items.map((i) => i.id).toList(),
            },
          'perf': {'latencyMs': stopwatch.elapsedMilliseconds},
        });
        if (didCreateSession) {
          tracker.track('session_start', {});
        }
        if (response.items.isEmpty) {
          tracker.track('empty_deck', {});
        }
      }
    } catch (e, st) {
      if (mounted) {
        // #region agent log
        _deckAgentLog('deck_provider.dart:_load', 'deck_load_error', {'errorType': e.runtimeType.toString()}, 'H8');
        // #endregion
        final sid = _ref.read(sessionIdProvider) ?? _sessionId;
        if (sid != null && sid.length >= 8) {
          _ref.read(eventTrackerProvider).track('client_error', {
            'error': {'errorType': e.runtimeType.toString()},
            'surface': {'name': 'deck_card'},
          });
        }
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() async {
    final sid = sessionId;
    // #region agent log
    _deckAgentLog('deck_provider.dart:refresh', 'refresh_called', {'sessionIdPresent': sid != null});
    // #endregion
    if (sid != null) {
      _ref.read(eventTrackerProvider).track('deck_refresh', {});
    }
    await _load();
  }

  /// Calls API and tracks the swipe. Does not mutate list; call [removeItemById] after animation completes.
  Future<void> swipe(
    String itemId,
    String direction,
    int positionInDeck, {
    String gesture = 'swipe',
    double? velocity,
    Item? item,
  }) async {
    final sid = sessionId;
    final current = state.valueOrNull;
    if (sid == null || current == null) return;

    try {
      await _client.swipe(sessionId: sid, itemId: itemId, direction: direction, positionInDeck: positionInDeck);
      final tracker = _ref.read(eventTrackerProvider);
      final eventName = direction == 'right' ? 'swipe_right' : 'swipe_left';
      final rank = _rankContext != null
          ? {
              'rankerRunId': _rankContext!.rankerRunId,
              if (_itemScores.containsKey(itemId)) 'scoreAtRender': _itemScores[itemId],
              if (_rankContext!.variant != null) 'variant': _rankContext!.variant,
              if (_rankContext!.variantBucket != null) 'variantBucket': _rankContext!.variantBucket,
            }
          : null;
      final snapshot = item != null
          ? {
              if (item.brand != null) 'brand': item.brand,
              'newUsed': item.newUsed,
              if (item.sizeClass != null) 'sizeClass': item.sizeClass,
              if (item.material != null) 'material': item.material,
              if (item.colorFamily != null) 'colorFamily': item.colorFamily,
              'styleTags': item.styleTags,
            }
          : null;
      tracker.track(eventName, {
        'item': {
          'itemId': itemId,
          'positionInDeck': positionInDeck,
          'source': 'deck',
          if (snapshot != null) 'snapshot': snapshot,
        },
        'interaction': {
          'gesture': gesture,
          'direction': direction,
          if (velocity != null) 'velocity': velocity,
        },
        if (rank != null) 'rank': rank,
      });
    } catch (_) {
      // Non-blocking; removal still happens on animation end
    }
  }

  void removeItemById(String itemId) {
    if (!mounted) return;
    final current = state.valueOrNull;
    if (current != null) {
      final listLengthBefore = current.length;
      final nextList = current.where((i) => i.id != itemId).toList();
      // #region agent log
      _deckAgentLog('deck_provider.dart:removeItemById', 'removeItemById', {'itemId': itemId, 'listLengthBefore': listLengthBefore, 'listLengthAfter': nextList.length}, 'flow');
      // #endregion
      state = AsyncValue.data(nextList);
      if (nextList.length < 3) {
        // #region agent log
        _deckAgentLog('deck_provider.dart:removeItemById', 'refetch_triggered', {'nextListLength': nextList.length, 'showLoading': false}, 'H-D1');
        // #endregion
        _load(showLoading: false);
      }
    }
  }

  void removeTop() {
    if (!mounted) return;
    final current = state.valueOrNull;
    if (current != null && current.isNotEmpty) {
      state = AsyncValue.data(current.sublist(1));
    }
  }

  /// Restore an item to the front of the deck (for undo functionality)
  void restoreItem(Item item) {
    if (!mounted) return;
    final current = state.valueOrNull ?? [];
    // Only restore if item isn't already in the deck
    if (!current.any((i) => i.id == item.id)) {
      state = AsyncValue.data([item, ...current]);
      _deckAgentLog('deck_provider.dart:restoreItem', 'item_restored', {'itemId': item.id}, 'undo');
    }
  }
}

final likesListProvider = FutureProvider<List<Item>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final sessionId = ref.watch(sessionIdProvider);
  if (sessionId == null) return [];
  return client.getLikes(sessionId: sessionId);
});

/// Toggle like via API and track like_add or like_remove. Use this when adding like/unlike UI (e.g. from Likes or detail).
Future<bool> toggleLikeWithTracking(WidgetRef ref, {required String sessionId, required String itemId}) async {
  final client = ref.read(apiClientProvider);
  final liked = await client.toggleLike(sessionId: sessionId, itemId: itemId);
  ref.read(eventTrackerProvider).track(liked ? 'like_add' : 'like_remove', {
    'item': {'itemId': itemId},
  });
  return liked;
}
