import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'constants.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/deck/deck_screen.dart';
import '../features/likes/likes_screen.dart';
import '../features/compare/compare_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/data_privacy_screen.dart';
import '../features/shared_shortlist/shared_shortlist_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/decision_room/decision_room_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/admin/admin_login_screen.dart';
import '../features/admin/admin_sources_screen.dart';
import '../features/admin/admin_runs_screen.dart';
import '../features/admin/admin_items_screen.dart';
import '../features/admin/admin_import_screen.dart';
import '../features/admin/admin_qa_screen.dart';
import '../features/admin/admin_curated_screen.dart';
import '../features/admin/admin_catalog_preview_screen.dart';
import '../features/retailer/retailer_console_screen.dart';
import '../data/session_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Keep admin auth in a listenable so we refresh redirects without recreating the router.
  // Recreating the router (e.g. ref.watch(adminAuthProvider)) resets to initialLocation '/' and kicks user back to splash.
  final initialAuth = ref.read(adminAuthProvider);
  final adminAuthNotifier = ValueNotifier<bool>(initialAuth);
  ref.listen<bool>(adminAuthProvider, (_, next) {
    adminAuthNotifier.value = next;
  });

  return GoRouter(
    initialLocation: '/deck',
    debugLogDiagnostics: true,
    refreshListenable: adminAuthNotifier,
    redirect: (context, state) {
      final isAdmin = adminAuthNotifier.value;
      final loc = state.matchedLocation;
      String? result;
      // Admin routes: send unauthenticated to login; send /admin or /admin/login to dashboard when logged in.
      if (loc.startsWith('/admin')) {
        if (isAdmin && (loc == '/admin' || loc == '/admin/login')) {
          result = '/admin/dashboard';
        } else if (!isAdmin && loc != '/admin' && loc != '/admin/login') {
          result = '/admin/login';
        }
      }
      // When a second router instance is created it can have initialLocation '/' while user is logged in; redirect to dashboard (avoids kick-back to splash).
      else if (isAdmin && loc == '/') {
        result = '/admin/dashboard';
      }
      return result;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const DeckScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => AppConstants.enableStandaloneOnboarding
            ? const OnboardingScreen()
            : const DeckScreen(),
      ),
      GoRoute(
        path: '/deck',
        builder: (context, state) => const DeckScreen(),
      ),
      GoRoute(
        path: '/likes',
        builder: (context, state) => const LikesScreen(),
      ),
      GoRoute(
        path: '/compare',
        builder: (context, state) => const CompareScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/profile/data-privacy',
        builder: (context, state) => const DataPrivacyScreen(),
      ),
      GoRoute(
        path: '/s/:token',
        builder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return SharedShortlistScreen(shareToken: token);
        },
      ),
      // Decision Room
      GoRoute(
        path: '/r/:roomId',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId'] ?? '';
          return DecisionRoomScreen(roomId: roomId);
        },
      ),
      // Auth routes
      GoRoute(
        path: '/auth/login',
        builder: (context, state) {
          final redirectTo = state.extra as String?;
          return LoginScreen(redirectTo: redirectTo);
        },
      ),
      GoRoute(
        path: '/auth/signup',
        builder: (context, state) {
          final redirectTo = state.extra as String?;
          return SignUpScreen(redirectTo: redirectTo);
        },
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: '/admin/login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: '/admin/sources',
        builder: (context, state) => const AdminSourcesScreen(),
      ),
      GoRoute(
        path: '/admin/runs',
        builder: (context, state) => const AdminRunsScreen(),
      ),
      GoRoute(
        path: '/admin/items',
        builder: (context, state) => const AdminItemsScreen(),
      ),
      GoRoute(
        path: '/admin/import',
        builder: (context, state) => const AdminImportScreen(),
      ),
      GoRoute(
        path: '/admin/qa',
        builder: (context, state) => const AdminQAScreen(),
      ),
      GoRoute(
        path: '/admin/curated',
        builder: (context, state) => const AdminCuratedScreen(),
      ),
      GoRoute(
        path: '/admin/catalog-preview',
        builder: (context, state) => const AdminCatalogPreviewScreen(),
      ),
      GoRoute(
        path: '/retailer',
        builder: (context, state) => const RetailerConsoleScreen(),
      ),
    ],
  );
});
