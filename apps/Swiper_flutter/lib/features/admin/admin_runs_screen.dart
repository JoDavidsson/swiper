import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

class AdminRunsScreen extends ConsumerWidget {
  const AdminRunsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Ingestion runs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: client.adminGetRuns(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final runs = snapshot.data!;
          if (runs.isEmpty) {
            return const Center(child: Text('No runs yet. Trigger a run from Sources.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            itemCount: runs.length,
            itemBuilder: (context, i) {
              final r = runs[i];
              final id = r['id'] as String? ?? '';
              final sourceId = r['sourceId'] as String? ?? '';
              final status = r['status'] as String? ?? '';
              final _ = r['startedAt']; // available for future display
              final stats = r['stats'] as Map<String, dynamic>?;
              final errorSummary = r['errorSummary'] as String?;
              return Card(
                margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                child: ListTile(
                  title: Text(sourceId),
                  subtitle: Text('$status • ${stats != null ? "upserted: ${stats['upserted'] ?? 0}" : ""} ${errorSummary != null ? "• $errorSummary" : ""}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showRunDetail(context, ref, id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showRunDetail(BuildContext context, WidgetRef ref, String runId) async {
    final client = ref.read(apiClientProvider);
    final run = await client.adminGetRun(runId);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Run: $runId', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppTheme.spacingUnit),
              Text('Status: ${run['status']}', style: Theme.of(context).textTheme.bodyLarge),
              Text('Source: ${run['sourceId']}', style: Theme.of(context).textTheme.bodyMedium),
              if (run['stats'] != null) Text('Stats: ${run['stats']}', style: Theme.of(context).textTheme.bodySmall),
              if (run['errorSummary'] != null) Text('Error: ${run['errorSummary']}', style: TextStyle(color: AppTheme.negativeDislike)),
              if (run['jobs'] != null) ...[
                const SizedBox(height: AppTheme.spacingUnit),
                Text('Jobs: ${(run['jobs'] as List).length}', style: Theme.of(context).textTheme.titleSmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
