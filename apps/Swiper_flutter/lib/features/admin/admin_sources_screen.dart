import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

class AdminSourcesScreen extends ConsumerWidget {
  const AdminSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Sources'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: client.adminGetSources(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sources = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(apiClientProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              itemCount: sources.length,
              itemBuilder: (context, i) {
                final s = sources[i];
                final id = s['id'] as String? ?? '';
                final name = s['name'] as String? ?? 'Unnamed';
                final mode = s['mode'] as String? ?? '';
                final isEnabled = s['isEnabled'] as bool? ?? false;
                return Card(
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text('$mode • ${isEnabled ? "Enabled" : "Disabled"}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _runNow(context, ref, id),
                          child: const Text('Run now'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateSource(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _runNow(BuildContext context, WidgetRef ref, String sourceId) async {
    final client = ref.read(apiClientProvider);
    try {
      await client.adminTriggerRun(sourceId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Run triggered')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showCreateSource(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New source'),
        content: const Text('Create source form (stub). Use Supply Engine or Firestore to add sources.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final client = ref.read(apiClientProvider);
              await client.adminCreateSource({
                'name': 'Manual source',
                'mode': 'manual',
                'isEnabled': true,
                'baseUrl': '',
                'rateLimitRps': 1,
              });
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Source created')));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
