import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';
import '../../data/event_tracker.dart';
import '../../data/models/item.dart';
import '../../data/session_provider.dart';
import '../../shared/widgets/app_shell.dart';

/// Wraps compare content and logs compare_open once when built.
class _CompareBody extends StatefulWidget {
  const _CompareBody({
    required this.items,
    required this.sessionId,
    required this.tracker,
    required this.child,
    required this.analyticsOptOut,
  });

  final List<Item> items;
  final String? sessionId;
  final EventTracker tracker;
  final Widget child;
  final bool analyticsOptOut;

  @override
  State<_CompareBody> createState() => _CompareBodyState();
}

class _CompareBodyState extends State<_CompareBody> {
  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null && !widget.analyticsOptOut) {
      widget.tracker.track('compare_open', {
        'items': {
          'itemIds': widget.items.map((e) => e.id).toList(),
          'count': widget.items.length,
        },
        'compare': {'compareCount': widget.items.length},
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class CompareScreen extends ConsumerWidget {
  const CompareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uri = GoRouterState.of(context).uri;
    final idsParam = uri.queryParameters['ids'] ?? '';
    final ids = idsParam.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (ids.isEmpty) {
      return AppShell(
        title: 'Compare',
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Select 2–4 items from Likes to compare.', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppTheme.spacingUnit),
              ElevatedButton(
                onPressed: () => context.push('/likes'),
                child: const Text('Go to Likes'),
              ),
            ],
          ),
        ),
      );
    }

    final client = ref.watch(apiClientProvider);
    final sessionId = ref.watch(sessionIdProvider);
    return FutureBuilder<List<Item>>(
      future: client.getItemsBatch(ids),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return AppShell(title: 'Compare', body: const Center(child: CircularProgressIndicator()));
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return AppShell(
            title: 'Compare',
            body: const Center(child: Text('No items found')),
          );
        }

        final analyticsOptOut = ref.watch(analyticsOptOutProvider);
        final tracker = ref.read(eventTrackerProvider);
        return AppShell(
          title: 'Compare',
          body: _CompareBody(
            items: items,
            sessionId: sessionId,
            tracker: tracker,
            analyticsOptOut: analyticsOptOut,
            child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Compare ${items.length} items', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppTheme.spacingUnit),
                _CompareTable(items: items),
                const SizedBox(height: AppTheme.spacingUnit * 2),
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final domain = item.outboundUrl != null ? Uri.tryParse(item.outboundUrl!)?.host : null;
                      tracker.track('outbound_click', {
                        'item': {'itemId': item.id},
                        'outbound': {'destinationDomain': domain ?? 'unknown'},
                      });
                      _openOutbound(context, item);
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text('View ${item.title} on site'),
                  ),
                )),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Future<void> _openOutbound(BuildContext context, Item item) async {
    final url = Uri.parse('${Uri.base.origin}/go/${item.id}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.items});

  final List<Item> items;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _row('Price', items.map((i) => '${i.priceAmount.toStringAsFixed(0)} ${i.priceCurrency}').toList()),
      _row('Dimensions', items.map((i) => i.dimensionsCm != null ? '${i.dimensionsCm!['w']}×${i.dimensionsCm!['h']}×${i.dimensionsCm!['d']} cm' : '–').toList()),
      _row('Material', items.map((i) => i.material ?? '–').toList()),
      _row('Delivery', items.map((i) => i.deliveryComplexity ?? '–').toList()),
      _row('New/Used', items.map((i) => i.newUsed).toList()),
      _row('Eco', items.map((i) => i.ecoTags.isNotEmpty ? i.ecoTags.join(', ') : '–').toList()),
    ];

    final columnWidths = <int, TableColumnWidth>{
      0: const FlexColumnWidth(1),
      for (var i = 1; i <= items.length; i++) i: const FlexColumnWidth(2),
    };

    return Table(
      border: TableBorder.all(color: AppTheme.textCaption.withValues(alpha: 0.3)),
      columnWidths: columnWidths,
      children: [
        TableRow(
          decoration: BoxDecoration(color: AppTheme.background),
          children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('')),
            ...items.map((i) => Padding(padding: const EdgeInsets.all(8), child: Text(i.title, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis))),
          ],
        ),
        for (final cells in rows)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(8), child: Text(cells[0], style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
              for (final c in cells.sublist(1)) Padding(padding: const EdgeInsets.all(8), child: Text(c, style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
      ],
    );
  }

  List<String> _row(String label, List<String> values) {
    return [label, ...values];
  }
}
