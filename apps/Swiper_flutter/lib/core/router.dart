import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/splash/splash_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/deck/deck_screen.dart';
import '../features/likes/likes_screen.dart';
import '../features/compare/compare_screen.dart';
import '../features/profile/profile_screen.dart';
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
        path: '/s/:token',
        builder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return SharedShortlistScreen(shareToken: token);
        },
      ),
      GoRoute(
        path: '/admin',
        redirect: (context, state) {
          if (!isAdmin) return '/admin/login';
          return null;
        },
        routes: [
          GoRoute(
            path: 'login',
            builder: (context, state) => const AdminLoginScreen(),
          ),
          GoRoute(
            path: '',
            builder: (context, state) => const AdminScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/admin/sources',
        builder: (context, state) => const AdminSourcesScreen(),
        redirect: (context, state) => isAdmin ? null : '/admin/login',
      ),
      GoRoute(
        path: '/admin/runs',
        builder: (context, state) => const AdminRunsScreen(),
        redirect: (context, state) => isAdmin ? null : '/admin/login',
      ),
      GoRoute(
        path: '/admin/items',
        builder: (context, state) => const AdminItemsScreen(),
        redirect: (context, state) => isAdmin ? null : '/admin/login',
      ),
      GoRoute(
        path: '/admin/import',
        builder: (context, state) => const AdminImportScreen(),
        redirect: (context, state) => isAdmin ? null : '/admin/login',
      ),
      GoRoute(
        path: '/admin/qa',
        builder: (context, state) => const AdminQAScreen(),
        redirect: (context, state) => isAdmin ? null : '/admin/login',
      ),
    ],
  );
});
