import 'dart:convert';

import 'package:dio/dio.dart';
import 'models/item.dart';

/// Rank context returned with deck response (for analytics).
class DeckRankContext {
  const DeckRankContext({required this.rankerRunId, required this.algorithmVersion});
  final String rankerRunId;
  final String algorithmVersion;
}

/// Deck API response: items plus optional rank context and per-item scores.
class DeckResponse {
  const DeckResponse({
    required this.items,
    this.rank,
    this.itemScores = const {},
  });
  final List<Item> items;
  final DeckRankContext? rank;
  final Map<String, double> itemScores;
}

/// API client for Cloud Functions. Base URL from env or default (emulator).
/// When [getAdminToken] is set, adds Authorization: Bearer <token> to admin requests (except verify).
/// When no token but [getAdminPassword] is set, adds X-Admin-Password for password-only admin access.
class ApiClient {
  ApiClient({String? baseUrl, String? Function()? getAdminToken, String? Function()? getAdminPassword})
      : _dio = Dio(BaseOptions(baseUrl: baseUrl ?? _defaultBaseUrl)),
        _getAdminToken = getAdminToken,
        _getAdminPassword = getAdminPassword {
    if (getAdminToken != null || getAdminPassword != null) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_isAdminPath(options.path) && !options.path.contains('admin/verify')) {
            final token = _getAdminToken?.call();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            } else {
              final password = _getAdminPassword?.call();
              if (password != null && password.isNotEmpty) {
                options.headers['X-Admin-Password'] = password;
              }
            }
          }
          handler.next(options);
        },
      ));
    }
  }

  final String? Function()? _getAdminToken;
  final String? Function()? _getAdminPassword;

  static bool _isAdminPath(String path) {
    return path.contains('/api/admin') || path.startsWith('admin/');
  }

  static String get _defaultBaseUrl {
    // Emulator: http://localhost:5001/<project>/<region>; prod: set via --dart-define=API_BASE_URL=...
    const env = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:5002/swiper-95482/europe-west1',
    );
    return env;
  }

  final Dio _dio;

  /// Create or refresh anonymous session. Optionally send device context for ML/analytics.
  Future<Map<String, dynamic>> createSession({Map<String, dynamic>? body}) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/session', data: body);
    return r.data ?? {};
  }

  /// Deck response: items plus rank context for analytics.
  static List<Item> itemsFromDeckResponse(Map<String, dynamic> r) {
    final list = r['items'] as List? ?? [];
    return list.map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Get deck items for session. Backend returns items, rank (rankerRunId, algorithmVersion), and optional itemScores.
  Future<DeckResponse> getDeck({required String sessionId, Map<String, dynamic>? filters, int limit = 500}) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/items/deck', queryParameters: {
      'sessionId': sessionId,
      if (filters != null && filters.isNotEmpty) 'filters': jsonEncode(filters),
      'limit': limit,
    });
    final data = r.data ?? {};
    final items = ApiClient.itemsFromDeckResponse(data);
    final rankMap = data['rank'] as Map<String, dynamic>?;
    final rank = rankMap != null
        ? DeckRankContext(
            rankerRunId: rankMap['rankerRunId'] as String? ?? '',
            algorithmVersion: rankMap['algorithmVersion'] as String? ?? '',
          )
        : null;
    final itemScoresRaw = data['itemScores'] as Map<String, dynamic>?;
    final itemScores = <String, double>{};
    if (itemScoresRaw != null) {
      for (final e in itemScoresRaw.entries) {
        final v = e.value;
        if (v is num) itemScores[e.key] = v.toDouble();
      }
    }
    if (rank != null && itemScores.isNotEmpty) {
      return DeckResponse(items: items, rank: rank, itemScores: itemScores);
    }
    return DeckResponse(items: items, rank: rank, itemScores: const {});
  }

  /// Record swipe.
  Future<void> swipe({required String sessionId, required String itemId, required String direction, int positionInDeck = 0}) async {
    await _dio.post('/api/swipe', data: {
      'sessionId': sessionId,
      'itemId': itemId,
      'direction': direction,
      'positionInDeck': positionInDeck,
    });
  }

  /// Get items by ids (for compare / shortlist).
  Future<List<Item>> getItemsBatch(List<String> ids) async {
    if (ids.isEmpty) return [];
    final r = await _dio.get<Map<String, dynamic>>('/api/items/batch', queryParameters: {'ids': ids.join(',')});
    final list = r.data?['items'] as List? ?? [];
    return list.map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Get liked items for session.
  Future<List<Item>> getLikes({required String sessionId}) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/likes', queryParameters: {'sessionId': sessionId});
    final list = r.data?['items'] as List? ?? [];
    return list.map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Toggle like.
  Future<bool> toggleLike({required String sessionId, required String itemId}) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/likes/toggle', data: {'sessionId': sessionId, 'itemId': itemId});
    return r.data?['liked'] as bool? ?? false;
  }

  /// Create shortlist and get share token.
  Future<Map<String, dynamic>> createShortlist({required String sessionId, required List<String> itemIds}) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/shortlists/create', data: {'sessionId': sessionId, 'itemIds': itemIds});
    return r.data ?? {};
  }

  /// Get shortlist by share token.
  Future<Map<String, dynamic>> getShortlistByToken(String shareToken) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/shortlists/byToken/$shareToken');
    return r.data ?? {};
  }

  /// Log event (legacy). Prefer event_tracker.track() for v1 schema.
  Future<void> logEvent({required String sessionId, required String eventType, String? itemId, Map<String, dynamic>? metadata}) async {
    await _dio.post('/api/events', data: {
      'sessionId': sessionId,
      'eventType': eventType,
      if (itemId != null) 'itemId': itemId,
      if (metadata != null) 'metadata': metadata,
    });
  }

  /// Send batched v1 events. Server adds createdAtServer and dedupes by eventId.
  Future<void> postEventsBatch(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;
    await _dio.post('/api/events/batch', data: {'events': events});
  }

  /// Admin login: verify password against backend (legacy). For full access use Sign in with Google.
  Future<bool> adminLogin(String password) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>('/api/admin/verify', data: {'password': password});
      return r.data?['ok'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Admin verify with Firebase ID token (Bearer). Add your email to Firestore adminAllowlist.
  Future<bool> adminVerifyWithToken(String idToken) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/api/admin/verify',
        options: Options(headers: {'Authorization': 'Bearer $idToken'}),
      );
      return r.data?['ok'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> adminGetStats() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/stats');
    return r.data ?? {};
  }

  Future<List<Map<String, dynamic>>> adminGetSources() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/sources');
    final list = r.data?['sources'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<String> adminCreateSource(Map<String, dynamic> body) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/admin/sources', data: body);
    return r.data?['id'] as String? ?? '';
  }

  Future<Map<String, dynamic>> adminGetSource(String sourceId) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/sources/$sourceId');
    return r.data ?? {};
  }

  Future<void> adminUpdateSource(String sourceId, Map<String, dynamic> body) async {
    await _dio.put('/api/admin/sources/$sourceId', data: body);
  }

  Future<void> adminDeleteSource(String sourceId) async {
    await _dio.delete('/api/admin/sources/$sourceId');
  }

  Future<List<Map<String, dynamic>>> adminGetRuns({String? sourceId}) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/runs', queryParameters: sourceId != null ? {'sourceId': sourceId} : null);
    final list = r.data?['runs'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> adminGetRun(String runId) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/runs/$runId');
    return r.data ?? {};
  }

  Future<Map<String, dynamic>> adminTriggerRun(String sourceId) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/admin/run', data: {'sourceId': sourceId});
    return r.data ?? {};
  }

  Future<Map<String, dynamic>> adminGetQa() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/qa');
    return r.data ?? {};
  }

  Future<List<Map<String, dynamic>>> adminGetItems({int limit = 50}) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/items', queryParameters: {'limit': limit});
    final list = r.data?['items'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
