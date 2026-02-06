import 'dart:convert';

import 'package:dio/dio.dart';
import 'models/item.dart';

/// Rank context returned with deck response (for analytics and A/B).
class DeckRankContext {
  const DeckRankContext({
    required this.rankerRunId,
    required this.algorithmVersion,
    this.variant,
    this.variantBucket,
  });
  final String rankerRunId;
  final String algorithmVersion;
  /// A/B variant label (e.g. personal_only, personal_only_exploration_5).
  final String? variant;
  /// A/B variant bucket (0–99) for segmentation.
  final int? variantBucket;
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

/// Standard image widths for responsive loading.
enum ImageWidth {
  thumbnail(400),
  card(800),
  detail(1200);

  const ImageWidth(this.value);
  final int value;
}

/// Image formats supported by the CDN.
enum ImageFormat {
  webp,
  jpeg,
  png,
}

/// API client for Cloud Functions. Base URL from env or default (emulator).
/// When [getAdminToken] is set, adds Authorization: Bearer <token> to admin requests (except verify).
/// When no token but [getAdminPassword] is set, adds X-Admin-Password for password-only admin access.
class ApiClient {
  /// Convert an external image URL to use our image proxy endpoint.
  /// This avoids CORS issues and provides CDN-like image optimization.
  ///
  /// Parameters:
  /// - [originalUrl]: The source image URL
  /// - [width]: Optional target width (400, 800, 1200). Height auto-calculated.
  /// - [format]: Optional output format. Default: auto (WebP if supported, else JPEG)
  /// - [quality]: Optional quality (1-100). Default: 80.
  static String proxyImageUrl(
    String originalUrl, {
    ImageWidth? width,
    ImageFormat? format,
    int? quality,
  }) {
    if (originalUrl.isEmpty) return originalUrl;
    // Don't proxy our own images or already proxied URLs
    if (originalUrl.contains('/api/image-proxy')) return originalUrl;
    // Don't proxy data URIs or local files
    if (originalUrl.startsWith('data:') || originalUrl.startsWith('file:')) return originalUrl;
    // Don't proxy unsplash images - they support CORS and have their own CDN
    if (originalUrl.contains('images.unsplash.com')) return originalUrl;
    
    final params = <String, String>{
      'url': originalUrl,
    };
    
    if (width != null) {
      params['w'] = width.value.toString();
    }
    if (format != null) {
      params['format'] = format.name;
    }
    if (quality != null) {
      params['q'] = quality.toString();
    }
    
    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    
    return '${_defaultBaseUrl}/api/image-proxy?$queryString';
  }
  
  /// Get the optimized image URL for a given context.
  /// 
  /// Automatically selects appropriate width:
  /// - Card thumbnail: 400w (for background/blur)
  /// - Card main: 800w (for card display)
  /// - Detail view: 1200w (for full-screen detail)
  static String optimizedImageUrl(String originalUrl, {required ImageWidth width}) {
    return proxyImageUrl(originalUrl, width: width);
  }
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

  /// Get the /go/:itemId redirect URL for outbound links.
  /// This endpoint is a separate Firebase Function (not under /api).
  static String goUrl(String itemId) {
    return '$_defaultBaseUrl/go/$itemId';
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
  Future<DeckResponse> getDeck({required String sessionId, Map<String, dynamic>? filters, int limit = 10}) async {
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
            variant: rankMap['variant'] as String?,
            variantBucket: rankMap['variantBucket'] is int
                ? rankMap['variantBucket'] as int
                : (rankMap['variantBucket'] is num ? (rankMap['variantBucket'] as num).toInt() : null),
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

  /// Preview auto-discovery for a URL (before creating source)
  Future<Map<String, dynamic>> adminPreviewSource(String url, {double rateLimitRps = 1.0}) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/admin/sources/preview', data: {
      'url': url,
      'rateLimitRps': rateLimitRps,
    });
    return r.data ?? {};
  }

  /// Create source with auto-discovery
  Future<Map<String, dynamic>> adminCreateSourceWithDiscovery({
    required String url,
    String? name,
    double rateLimitRps = 1.0,
    bool isEnabled = true,
    List<String>? includeKeywords,
    List<String>? categoryFilter,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/admin/sources/create-with-discovery', data: {
      'url': url,
      if (name != null && name.isNotEmpty) 'name': name,
      'rateLimitRps': rateLimitRps,
      'isEnabled': isEnabled,
      if (includeKeywords != null) 'includeKeywords': includeKeywords,
      if (categoryFilter != null) 'categoryFilter': categoryFilter,
    });
    return r.data ?? {};
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

  Future<Map<String, dynamic>> adminGetItems({int limit = 50, String? retailer}) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/items', queryParameters: {
      'limit': limit,
      if (retailer != null) 'retailer': retailer,
    });
    return r.data ?? {'items': []};
  }

  /// Trigger image validation for items
  Future<Map<String, dynamic>> adminValidateImages({
    int limit = 50,
    String? retailer,
    bool force = false,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>('/api/admin/validate-images', data: {
      'limit': limit,
      if (retailer != null) 'retailer': retailer,
      'force': force,
    });
    return r.data ?? {};
  }

  /// Get Creative Health statistics
  Future<Map<String, dynamic>> adminGetCreativeHealthStats({String? retailer}) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/creative-health-stats', queryParameters: {
      if (retailer != null) 'retailer': retailer,
    });
    return r.data ?? {};
  }

  // ============ Onboarding / Gold Card APIs ============

  /// Get curated sofas for the visual gold card
  Future<List<Map<String, dynamic>>> getCuratedSofas() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/onboarding/curated-sofas');
      final list = r.data?['sofas'] as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      // Fallback: return empty list, UI will handle gracefully
      return [];
    }
  }

  /// Submit onboarding picks (visual card selections + budget)
  Future<void> submitOnboardingPicks({
    required String sessionId,
    required List<String> pickedItemIds,
    double? budgetMin,
    double? budgetMax,
  }) async {
    await _dio.post('/api/onboarding/picks', data: {
      'sessionId': sessionId,
      'pickedItemIds': pickedItemIds,
      if (budgetMin != null) 'budgetMin': budgetMin,
      if (budgetMax != null) 'budgetMax': budgetMax,
    });
  }

  // ============ Admin Curated Sofas APIs ============

  /// Get all curated onboarding sofas (admin)
  Future<List<Map<String, dynamic>>> adminGetCuratedSofas() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/admin/curated-sofas');
    final list = r.data?['sofas'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Add item to curated onboarding sofas (admin)
  Future<void> adminAddCuratedSofa(String itemId, int order) async {
    await _dio.post('/api/admin/curated-sofas', data: {
      'itemId': itemId,
      'order': order,
    });
  }

  /// Remove item from curated onboarding sofas (admin)
  Future<void> adminRemoveCuratedSofa(String itemId) async {
    await _dio.delete('/api/admin/curated-sofas/$itemId');
  }

  /// Reorder curated onboarding sofas (admin)
  Future<void> adminReorderCuratedSofas(List<String> itemIds) async {
    await _dio.put('/api/admin/curated-sofas/reorder', data: {
      'itemIds': itemIds,
    });
  }

  // ============ User Auth APIs ============

  /// Link anonymous session to authenticated user.
  Future<Map<String, dynamic>> linkSession({required String token, required String sessionId}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/auth/link-session',
      data: {'sessionId': sessionId},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return r.data ?? {};
  }

  /// Get current user profile.
  Future<Map<String, dynamic>> getMe({required String token}) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/api/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return r.data ?? {};
  }

  // ============ Decision Room APIs ============

  /// Create a new Decision Room (requires auth).
  Future<Map<String, dynamic>> createDecisionRoom({
    required String token,
    required List<String> itemIds,
    String? title,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/decision-rooms',
      data: {
        'itemIds': itemIds,
        if (title != null) 'title': title,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return r.data ?? {};
  }

  /// Get Decision Room by ID (public).
  Future<Map<String, dynamic>> getDecisionRoom(String roomId) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/decision-rooms/$roomId');
    return r.data ?? {};
  }

  /// Vote on an item in a Decision Room (requires auth).
  Future<Map<String, dynamic>> voteInDecisionRoom({
    required String token,
    required String roomId,
    required String itemId,
    required String vote, // "up" or "down"
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/decision-rooms/$roomId/vote',
      data: {'itemId': itemId, 'vote': vote},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return r.data ?? {};
  }

  /// Add a comment to a Decision Room (requires auth).
  Future<Map<String, dynamic>> commentInDecisionRoom({
    required String token,
    required String roomId,
    required String text,
    String? itemId,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/decision-rooms/$roomId/comment',
      data: {
        'text': text,
        if (itemId != null) 'itemId': itemId,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return r.data ?? {};
  }

  /// Get comments for a Decision Room (public).
  Future<Map<String, dynamic>> getDecisionRoomComments(String roomId) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/decision-rooms/$roomId/comments');
    return r.data ?? {};
  }

  /// Suggest an alternative item to a Decision Room (requires auth).
  Future<Map<String, dynamic>> suggestInDecisionRoom({
    required String token,
    required String roomId,
    required String url,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/decision-rooms/$roomId/suggest',
      data: {'url': url},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return r.data ?? {};
  }

  /// Set finalists in a Decision Room (requires auth, creator only).
  Future<Map<String, dynamic>> setDecisionRoomFinalists({
    required String token,
    required String roomId,
    required List<String> finalistIds,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/decision-rooms/$roomId/finalists',
      data: {'finalistIds': finalistIds},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return r.data ?? {};
  }
}
