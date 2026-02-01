import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/deck_provider.dart';
import '../../data/locale_provider.dart';
import '../../data/session_provider.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Text(
                  AppConstants.appName,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: AppTheme.primaryAction,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: AppTheme.spacingUnit),
                Text(
                  AppConstants.tagline,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
                const Spacer(flex: 2),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await ensureSession(ref, ref.read(apiClientProvider));
                      if (context.mounted) context.go('/onboarding');
                    },
                    child: Text(ref.watch(appStringsProvider).getStarted),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingUnit),
                TextButton(
                  onPressed: () async {
                    await ensureSession(ref, ref.read(apiClientProvider));
                    if (context.mounted) context.go('/deck');
                  },
                  child: Text(ref.watch(appStringsProvider).skipToSwipe),
                ),
                const SizedBox(height: AppTheme.spacingUnit * 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
