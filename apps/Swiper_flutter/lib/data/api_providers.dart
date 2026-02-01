import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'session_provider.dart';

/// API client for Cloud Functions. Used by deck, likes, events, etc.
final apiClientProvider = Provider<ApiClient>((ref) {
  final getAdminToken = () => ref.read(adminIdTokenProvider);
  final getAdminPassword = () => ref.read(adminPasswordProvider);
  return ApiClient(getAdminToken: getAdminToken, getAdminPassword: getAdminPassword);
});
