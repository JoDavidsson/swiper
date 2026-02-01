import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'models/item.dart';
import 'session_provider.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final deckItemsProvider = StateNotifierProvider<DeckNotifier, AsyncValue<List<Item>>>((ref) {
  final client = ref.watch(apiClientProvider);
  final sessionId = ref.watch(sessionIdProvider);
  return DeckNotifier(client, ref, sessionId);
});

class DeckNotifier extends StateNotifier<AsyncValue<List<Item>>> {
  DeckNotifier(this._client, this._ref, this._sessionId) : super(const AsyncValue.loading()) {
    _load();
  }

  final ApiClient _client;
  final Ref _ref;
  String? _sessionId;

  String? get sessionId => _sessionId ?? _ref.read(sessionIdProvider);

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      String? sid = _ref.read(sessionIdProvider);
      if (sid == null || sid.isEmpty) {
        sid = await loadStoredSessionId();
        if (sid != null) {
          _ref.read(sessionIdProvider.notifier).state = sid;
          _sessionId = sid;
        }
      }
      if (sid == null || sid.isEmpty) {
        final res = await _client.createSession();
        sid = res['sessionId'] as String?;
        if (sid != null) {
          await saveSessionId(sid);
          _ref.read(sessionIdProvider.notifier).state = sid;
          _sessionId = sid;
        }
      } else {
        _sessionId = sid;
      }
      if (sid == null) {
        state = const AsyncValue.error('No session', StackTrace.current);
        return;
      }
      final items = await _client.getDeck(sessionId: sid);
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  Future<void> swipe(String itemId, String direction, int positionInDeck) async {
    final sid = sessionId;
    final current = state.valueOrNull;
    if (sid == null || current == null) return;
    try {
      await _client.swipe(sessionId: sid, itemId: itemId, direction: direction, positionInDeck: positionInDeck);
      state = AsyncValue.data(current.where((i) => i.id != itemId).toList());
    } catch (_) {
      // Keep UI; could retry or show snackbar
    }
  }

  void removeTop() {
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
