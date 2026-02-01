import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'device_context.dart';
import 'models/item.dart';
import 'session_provider.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

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

  String? get sessionId => _sessionId ?? _ref.read(sessionIdProvider);

  Future<void> _load() async {
    if (!mounted) return;
    state = const AsyncValue.loading();
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
      final filtersParam = _filters.isEmpty ? null : _filters;
      final items = await _client.getDeck(sessionId: sid, filters: filtersParam);
      if (!mounted) return;
      if (mounted) {
        state = AsyncValue.data(items);
        if (!_ref.read(analyticsOptOutProvider)) {
          if (didCreateSession) {
            _client.logEvent(sessionId: sid, eventType: 'session_start').ignore();
          }
          if (items.isEmpty) {
            _client.logEvent(sessionId: sid, eventType: 'deck_empty_view').ignore();
          }
        }
      }
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  Future<void> swipe(String itemId, String direction, int positionInDeck) async {
    final sid = sessionId;
    final current = state.valueOrNull;
    if (sid == null || current == null) return;
    try {
      await _client.swipe(sessionId: sid, itemId: itemId, direction: direction, positionInDeck: positionInDeck);
      if (mounted) state = AsyncValue.data(current.where((i) => i.id != itemId).toList());
    } catch (_) {
      // Keep UI; could retry or show snackbar
    }
  }

  void removeTop() {
    if (!mounted) return;
    final current = state.valueOrNull;
    if (current != null && current.isNotEmpty) {
      state = AsyncValue.data(current.sublist(1));
    }
  }
}

final likesListProvider = FutureProvider<List<Item>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final sessionId = ref.watch(sessionIdProvider);
  if (sessionId == null) return [];
  return client.getLikes(sessionId: sessionId);
});
