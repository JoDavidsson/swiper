import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

class AdminImportScreen extends ConsumerWidget {
  const AdminImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Import'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
        children: [
          Text(
            'Ingest data into Firestore',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(
            'To import from a CSV or feed:\n\n'
            '1. Add a source in Sources (e.g. mode feed, baseUrl or config in Supply Engine).\n'
            '2. Use "Run now" on that source in the Sources screen.\n\n'
            'For the sample feed (local or Supply Engine): trigger the run below if you have a source configured.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                final sources = await client.adminGetSources();
                if (sources.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No sources. Add one in Sources first.')),
                    );
                  }
                  return;
                }
                final source = sources.firstWhere(
                  (s) => (s['name'] as String? ?? '').toLowerCase().contains('sample'),
                  orElse: () => sources.first,
                );
                final id = source['id'] as String? ?? '';
                if (id.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No source ID')));
                  }
                  return;
                }
                await client.adminTriggerRun(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Run triggered')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Trigger sample / first source run'),
          ),
        ],
      ),
    );
  }
}
