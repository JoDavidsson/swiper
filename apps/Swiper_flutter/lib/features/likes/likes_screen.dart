import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/deck_provider.dart';
import '../../data/models/item.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/detail_sheet.dart';

class LikesScreen extends ConsumerStatefulWidget {
  const LikesScreen({super.key});

  @override
  ConsumerState<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends ConsumerState<LikesScreen> {
  bool _gridView = true;
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final likesAsync = ref.watch(likesListProvider);
    final sessionId = ref.watch(sessionIdProvider);

    return AppShell(
      title: 'Likes',
      body: likesAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: AppTheme.textCaption),
                  const SizedBox(height: AppTheme.spacingUnit),
                  Text('No likes yet', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppTheme.spacingUnit),
                  Text('Swipe right to save items here.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
                  const SizedBox(height: AppTheme.spacingUnit * 2),
                  ElevatedButton(
                    onPressed: () => context.go('/deck'),
                    child: const Text('Back to deck'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(_gridView ? Icons.view_list : Icons.grid_view),
                    onPressed: () => setState(() => _gridView = !_gridView),
                    tooltip: _gridView ? 'List view' : 'Grid view',
                  ),
                ],
              ),
              Expanded(
                child: _gridView
                    ? GridView.builder(
                        padding: const EdgeInsets.all(AppTheme.spacingUnit),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: AppTheme.spacingUnit,
                          mainAxisSpacing: AppTheme.spacingUnit,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) => _LikeCard(
                          item: items[i],
                          selected: _selectedIds.contains(items[i].id),
                          onTap: () => showDetailSheet(context, items[i], goBaseUrl: Uri.base.origin),
                          onLongPress: () => setState(() {
                            if (_selectedIds.contains(items[i].id)) {
                              _selectedIds.remove(items[i].id);
                            } else {
                              _selectedIds.add(items[i].id);
                            }
                          }),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppTheme.spacingUnit),
                        itemCount: items.length,
                        itemBuilder: (context, i) => _LikeCard(
                          item: items[i],
                          selected: _selectedIds.contains(items[i].id),
                          onTap: () => showDetailSheet(context, items[i], goBaseUrl: Uri.base.origin),
                          onLongPress: () => setState(() {
                            if (_selectedIds.contains(items[i].id)) {
                              _selectedIds.remove(items[i].id);
                            } else {
                              _selectedIds.add(items[i].id);
                            }
                          }),
                        ),
                      ),
              ),
              if (_selectedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  child: Row(
                    children: [
                      if (_selectedIds.length >= AppConstants.minCompareItems && _selectedIds.length <= AppConstants.maxCompareItems)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => context.push(Uri(path: '/compare', queryParameters: {'ids': _selectedIds.join(',')}).toString()),
                            child: const Text('Compare'),
                          ),
                        ),
                      if (_selectedIds.length >= AppConstants.minCompareItems) const SizedBox(width: AppTheme.spacingUnit),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: sessionId != null ? () => _shareShortlist(context, sessionId, _selectedIds.toList()) : null,
                          child: const Text('Share shortlist'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _shareShortlist(BuildContext context, String sessionId, List<String> itemIds) async {
    final client = ref.read(apiClientProvider);
    try {
      final res = await client.createShortlist(sessionId: sessionId, itemIds: itemIds);
      final token = res['shareToken'] as String?;
      if (token == null) return;
      final url = '${Uri.base.origin}/s/$token';
      await Share.share('Check out my shortlist: $url', subject: 'Swiper shortlist');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share link: $url')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

class _LikeCard extends StatelessWidget {
  const _LikeCard({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Item item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: selected ? const BorderSide(color: AppTheme.primaryAction, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: item.firstImageUrl != null
                  ? Image.network(item.firstImageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported, color: AppTheme.textCaption))
                  : Container(color: AppTheme.background, child: Icon(Icons.image_not_supported, color: AppTheme.textCaption)),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit / 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.primaryAction)),
                  if (item.brand != null) Text(item.brand!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
