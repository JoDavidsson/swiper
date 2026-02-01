import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

class AdminItemsScreen extends ConsumerWidget {
  const AdminItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Items'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: client.adminGetItems(limit: 100),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(
              child: Text('No items yet. Ingest a feed (Supply Engine or Run now on a source).'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(apiClientProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final title = item['title'] as String? ?? 'Untitled';
                final price = item['priceAmount'];
                final currency = item['priceCurrency'] as String? ?? 'SEK';
                final sourceId = item['sourceId'] as String? ?? '';
                final isActive = item['isActive'] as bool? ?? true;
                final priceStr = price is num ? (price).toStringAsFixed(0) : (price?.toString() ?? '?');
                return Card(
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                  child: ListTile(
                    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '$priceStr $currency • $sourceId${isActive ? '' : ' (inactive)'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
