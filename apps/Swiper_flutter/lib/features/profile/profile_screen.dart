import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/locale_provider.dart';
import '../../shared/widgets/app_shell.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final locale = ref.watch(localeProvider);
    final currentLabel = locale.languageCode == 'sv' ? strings.swedish : strings.english;
    return AppShell(
      title: strings.profile,
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        children: [
          ListTile(
            title: Text(strings.language),
            subtitle: Text('${strings.swedish} / ${strings.english} – $currentLabel'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguageSheet(context, ref),
          ),
          ListTile(
            title: Text(strings.dataAndPrivacy),
            subtitle: const Text('What we collect, opt-out and social login'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/data-privacy'),
          ),
          ListTile(
            title: Text(strings.editPreferences),
            subtitle: Text(strings.reRunOnboarding),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/onboarding'),
          ),
        ],
      ),
    );
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref) {
    final strings = ref.read(appStringsProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(strings.swedish),
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(const Locale('sv'));
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              title: Text(strings.english),
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(const Locale('en'));
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
