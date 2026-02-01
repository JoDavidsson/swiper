import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

class AdminQAScreen extends ConsumerWidget {
  const AdminQAScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('QA completeness'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: client.adminGetQa(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final qa = snapshot.data!;
          final total = (qa['total'] as num?)?.toInt() ?? 0;
          final missingPrice = (qa['missingPrice'] as num?)?.toInt() ?? 0;
          final missingDimensions = (qa['missingDimensions'] as num?)?.toInt() ?? 0;
          final missingImages = (qa['missingImages'] as num?)?.toInt() ?? 0;
          final missingOutboundUrl = (qa['missingOutboundUrl'] as num?)?.toInt() ?? 0;
          final missingTags = (qa['missingTags'] as num?)?.toInt() ?? 0;

          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Completeness report (active items)', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppTheme.spacingUnit),
                      Text('Total items: $total', style: Theme.of(context).textTheme.bodyLarge),
                      const Divider(),
                      _Row(label: 'Missing price', count: missingPrice, total: total),
                      _Row(label: 'Missing dimensions', count: missingDimensions, total: total),
                      _Row(label: 'Missing images', count: missingImages, total: total),
                      _Row(label: 'Missing outbound URL', count: missingOutboundUrl, total: total),
                      _Row(label: 'Missing style tags', count: missingTags, total: total),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.count, required this.total});

  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text('$count ($pct%)', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: count > 0 ? AppTheme.negativeDislike : AppTheme.positiveLike)),
        ],
      ),
    );
  }
}
