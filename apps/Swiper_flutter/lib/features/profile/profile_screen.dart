import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../shared/widgets/app_shell.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      title: 'Profile',
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        children: [
          ListTile(
            title: const Text('Language'),
            subtitle: const Text('Swedish / English – coming soon'),
            trailing: const Icon(Icons.chevron_right),
            enabled: false,
          ),
          ListTile(
            title: const Text('Data & Privacy'),
            subtitle: const Text('What we collect, opt-out and social login (coming later)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/data-privacy'),
          ),
          ListTile(
            title: const Text('Edit preferences'),
            subtitle: const Text('Re-run onboarding quiz'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),
        ],
      ),
    );
  }
}
