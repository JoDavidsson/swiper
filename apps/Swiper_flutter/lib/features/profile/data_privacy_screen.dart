import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/event_tracker.dart';
import '../../data/locale_provider.dart';
import '../../data/session_provider.dart';
import '../../shared/widgets/app_shell.dart';

/// Data & Privacy: what we collect, future opt-out and SSO placeholders.
class DataPrivacyScreen extends ConsumerWidget {
  const DataPrivacyScreen({super.key});

  void _showSocialComingSoon(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect social accounts'),
        content: const Text(
          'Coming soon – we\'ll use this to personalise your feed. Anonymous use remains the default.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AppShell(
      title: strings.dataAndPrivacy,
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        children: [
          Text(
            'What we collect',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(
            'We capture anonymous usage data to improve recommendations and build better experiences. No sign-in or personal accounts are required.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          _Section(
            title: 'Session & device',
            items: const [
              'Anonymous session ID (stored locally and on our servers)',
              'Platform (e.g. web, iOS, Android)',
              'Locale and timezone offset',
              'Screen size bucket (small / medium / large)',
              'Browser or app version (e.g. Chrome/120)',
            ],
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          _Section(
            title: 'How you use the app',
            items: const [
              'Swipes (left/right), likes, and outbound clicks',
              'Opening item details and time spent viewing',
              'Compare screen usage and filter usage',
              'Onboarding preferences (style, budget, options)',
              'Deck empty and session start events',
            ],
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Text(
            'This data is used for recommendation models and product analytics. You can opt out of non-essential collection below.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textCaption),
          ),
          const SizedBox(height: AppTheme.spacingUnit * 3),
          const Divider(),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(
            'Controls',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppTheme.spacingUnit),
          SwitchListTile(
            secondary: Icon(Icons.shield_outlined, color: AppTheme.textCaption),
            title: Text(strings.optOutOfAnalytics),
            subtitle: Text(strings.optOutSubtitle),
            value: ref.watch(analyticsOptOutProvider),
            onChanged: (value) {
              ref.read(analyticsOptOutProvider.notifier).setOptOut(value);
              ref.read(eventTrackerProvider).track('consent_updated', {
                'ext': {'analyticsOptOut': value},
              });
            },
          ),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(
            'Coming later',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.textCaption),
          ),
          const SizedBox(height: AppTheme.spacingUnit / 2),
          ListTile(
            leading: Icon(Icons.link, color: AppTheme.textCaption),
            title: Text(strings.connectSocial),
            subtitle: Text(strings.connectSocialSubtitle),
            trailing: Text(
              'Planned',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textCaption),
            ),
            onTap: () => _showSocialComingSoon(context),
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppTheme.primaryAction,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: AppTheme.spacingUnit / 2),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: AppTheme.spacingUnit, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
