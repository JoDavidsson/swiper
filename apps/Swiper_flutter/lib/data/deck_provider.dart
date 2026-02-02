import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'api_providers.dart';
import 'device_context.dart';
import 'event_tracker.dart';
import 'models/item.dart';
import 'session_provider.dart';

export 'api_providers.dart' show apiClientProvider;

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
  _LastSwipe? _lastSwipe;

  String? get sessionId => _sessionId ?? _ref.read(sessionIdProvider);
  DeckRankContext? get rankContext => _rankContext;
  Map<String, double> get itemScores => _itemScores;
  bool get canUndo => _lastSwipe != null;

  Future<void> _load() async {
    if (!mounted) return;
    state = const AsyncValue.loading();
    _lastSwipe = null;
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
        if (mounted) state = AsyncValue.error('No session', StackTrace.current);
        return;
      }

      final tracker = _ref.read(eventTrackerProvider);
      final filtersParam = _filters.isEmpty ? null : _filters;
      tracker.track('deck_request', filtersParam != null && filtersParam.isNotEmpty
          ? {'filters': {'active': _filters}}
          : {});

      final stopwatch = Stopwatch()..start();
      final response = await _client.getDeck(sessionId: sid, filters: filtersParam);
      stopwatch.stop();
      if (!mounted) return;

      _rankContext = response.rank;
      _itemScores = response.itemScores;

      if (mounted) {
        state = AsyncValue.data(response.items);
        tracker.track('deck_response', {
          if (response.rank != null)
            'rank': {
              'rankerRunId': response.rank!.rankerRunId,
              'algorithmVersion': response.rank!.algorithmVersion,
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
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

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
    final next = current.where((i) => i.id != itemId).toList();
    if (mounted) state = AsyncValue.data(next);
    final resolvedItem = item ?? current.firstWhere((i) => i.id == itemId, orElse: () => current.first);
    _lastSwipe = _LastSwipe(
      item: resolvedItem,
      direction: direction,
      positionInDeck: positionInDeck,
      gesture: gesture,
      rankContext: _rankContext,
      scoreAtRender: _itemScores[itemId],
    );
    try {
      final tracker = _ref.read(eventTrackerProvider);
      final eventName = direction == 'right' ? 'swipe_right' : 'swipe_left';
      final rank = _rankContext != null
          ? {
              'rankerRunId': _rankContext!.rankerRunId,
              if (_itemScores.containsKey(itemId)) 'scoreAtRender': _itemScores[itemId],
            }
          : null;
      final snapshot = {
        if (resolvedItem.brand != null) 'brand': resolvedItem.brand,
        'newUsed': resolvedItem.newUsed,
        if (resolvedItem.sizeClass != null) 'sizeClass': resolvedItem.sizeClass,
        if (resolvedItem.material != null) 'material': resolvedItem.material,
        if (resolvedItem.colorFamily != null) 'colorFamily': resolvedItem.colorFamily,
        'styleTags': resolvedItem.styleTags,
      };
      tracker.track(eventName, {
        'item': {
          'itemId': itemId,
          'positionInDeck': positionInDeck,
          'source': 'deck',
          'snapshot': snapshot,
        },
        'interaction': {
          'gesture': gesture,
          'direction': direction,
          if (velocity != null) 'velocity': velocity,
        },
        if (rank != null) 'rank': rank,
      });
      await _client.swipe(sessionId: sid, itemId: itemId, direction: direction, positionInDeck: positionInDeck);
    } catch (_) {
      if (mounted) state = AsyncValue.data(current);
      _lastSwipe = null;
    }
  }

  Future<void> undoLastSwipe() async {
    final last = _lastSwipe;
    if (last == null) return;
    final current = state.valueOrNull ?? <Item>[];
    if (current.any((i) => i.id == last.item.id)) {
      _lastSwipe = null;
      return;
    }
    if (mounted) state = AsyncValue.data([last.item, ...current]);
    _lastSwipe = null;
    final tracker = _ref.read(eventTrackerProvider);
    tracker.track('swipe_undo', {
      'item': {
        'itemId': last.item.id,
        'positionInDeck': 0,
        'source': 'deck',
      },
      'interaction': {
        'direction': last.direction,
        'gesture': last.gesture,
      },
      if (last.rankContext != null)
        'rank': {
          'rankerRunId': last.rankContext!.rankerRunId,
          if (last.scoreAtRender != null) 'scoreAtRender': last.scoreAtRender,
        },
    });
  }

  void removeTop() {
    if (!mounted) return;
    final current = state.valueOrNull;
    if (current != null && current.isNotEmpty) {
      state = AsyncValue.data(current.sublist(1));
    }
  }
}

class _LastSwipe {
  _LastSwipe({
    required this.item,
    required this.direction,
    required this.positionInDeck,
    required this.gesture,
    this.rankContext,
    this.scoreAtRender,
  });

  final Item item;
  final String direction;
  final int positionInDeck;
  final String gesture;
  final DeckRankContext? rankContext;
  final double? scoreAtRender;
}

final likesListProvider = FutureProvider<List<Item>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final sessionId = ref.watch(sessionIdProvider);
  if (sessionId == null) return [];
  return client.getLikes(sessionId: sessionId);
});
