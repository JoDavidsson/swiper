import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/splash/splash_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/deck/deck_screen.dart';
import '../features/likes/likes_screen.dart';
import '../features/compare/compare_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/data_privacy_screen.dart';
import '../features/shared_shortlist/shared_shortlist_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/admin/admin_login_screen.dart';
import '../features/admin/admin_sources_screen.dart';
import '../features/admin/admin_runs_screen.dart';
import '../features/admin/admin_items_screen.dart';
import '../features/admin/admin_import_screen.dart';
import '../features/admin/admin_qa_screen.dart';
import '../data/session_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final isAdmin = ref.watch(adminAuthProvider);
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
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
      // Flat admin routes (no nested children) to avoid go_router 13.x "path cannot be empty" assert
      GoRoute(
        path: '/admin',
        redirect: (context, state) => isAdmin ? '/admin/dashboard' : '/admin/login',
        builder: (context, state) => const SizedBox.shrink(), // always redirected
      ),
      GoRoute(
        path: '/admin/login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: '/admin/dashboard',
        redirect: (context, state) => isAdmin ? null : '/admin/login',
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: '/admin/sources',
        redirect: (context, state) => isAdmin ? null : '/admin/login',
        builder: (context, state) => const AdminSourcesScreen(),
      ),
      GoRoute(
        path: '/admin/runs',
        redirect: (context, state) => isAdmin ? null : '/admin/login',
        builder: (context, state) => const AdminRunsScreen(),
      ),
      GoRoute(
        path: '/admin/items',
        redirect: (context, state) => isAdmin ? null : '/admin/login',
        builder: (context, state) => const AdminItemsScreen(),
      ),
      GoRoute(
        path: '/admin/import',
        redirect: (context, state) => isAdmin ? null : '/admin/login',
        builder: (context, state) => const AdminImportScreen(),
      ),
      GoRoute(
        path: '/admin/qa',
        redirect: (context, state) => isAdmin ? null : '/admin/login',
        builder: (context, state) => const AdminQAScreen(),
      ),
    ],
  );
});
