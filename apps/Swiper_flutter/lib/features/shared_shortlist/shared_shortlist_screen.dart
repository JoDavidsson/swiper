import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';
import '../../data/event_tracker.dart';
import '../../data/models/item.dart';
import '../../shared/widgets/detail_sheet.dart';

class SharedShortlistScreen extends ConsumerWidget {
  const SharedShortlistScreen({super.key, required this.shareToken});

  final String shareToken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    return FutureBuilder<Map<String, dynamic>>(
      future: client.getShortlistByToken(shareToken),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(title: const Text('Shared shortlist')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        final itemsRaw = data['items'] as List? ?? [];
        final items = itemsRaw.map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map))).toList();

        if (items.isEmpty) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(title: const Text('Shared shortlist')),
            body: const Center(child: Text('This shortlist is empty.')),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(title: const Text('Shared shortlist')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${items.length} items', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppTheme.spacingUnit),
                ...items.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
                  child: InkWell(
                    onTap: () {
                      final tracker = ref.read(eventTrackerProvider);
                      showDetailSheet(
                        context,
                        item,
                        goBaseUrl: Uri.base.origin,
                        onOutboundClick: (i) {
                          final domain = i.outboundUrl != null ? Uri.tryParse(i.outboundUrl!)?.host : null;
                          tracker.track('outbound_click', {
                            'item': {'itemId': i.id},
                            'outbound': {'destinationDomain': domain ?? 'unknown'},
                          });
                        },
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingUnit),
                      child: Row(
                        children: [
                          if (item.firstImageUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                              child: Image.network(item.firstImageUrl!, width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported)),
                            )
                          else
                            const SizedBox(width: 80, height: 80, child: Icon(Icons.image_not_supported)),
                          const SizedBox(width: AppTheme.spacingUnit),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title, style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                                Text('${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.primaryAction)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => _openOutbound(context, item),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
                const SizedBox(height: AppTheme.spacingUnit),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Start swiping'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _openOutbound(BuildContext context, Item item) async {
  final url = Uri.parse('${Uri.base.origin}/go/${item.id}');
  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
