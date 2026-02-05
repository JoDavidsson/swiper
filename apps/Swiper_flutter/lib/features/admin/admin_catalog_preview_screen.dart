import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/deck_provider.dart';
import '../../data/models/item.dart';

/// Admin screen for previewing retailer catalog with premium image rendering
/// and Creative Health scores.
class AdminCatalogPreviewScreen extends ConsumerStatefulWidget {
  const AdminCatalogPreviewScreen({super.key});

  @override
  ConsumerState<AdminCatalogPreviewScreen> createState() => _AdminCatalogPreviewScreenState();
}

class _AdminCatalogPreviewScreenState extends ConsumerState<AdminCatalogPreviewScreen> {
  List<Item> _items = [];
  Map<String, dynamic> _healthStats = {};
  bool _loading = true;
  String? _error;
  String? _selectedRetailer;
  
  // View mode: 'grid' or 'comparison'
  String _viewMode = 'grid';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      
      // Load items and health stats in parallel
      final results = await Future.wait<Map<String, dynamic>>([
        client.adminGetItems(limit: 100, retailer: _selectedRetailer),
        client.adminGetCreativeHealthStats(retailer: _selectedRetailer),
      ]);
      
      final itemsData = results[0];
      final statsData = results[1];
      
      final itemsList = (itemsData['items'] as List<dynamic>?) ?? [];
      final items = itemsList.map((j) => Item.fromJson(j as Map<String, dynamic>)).toList();
      
      setState(() {
        _items = items;
        _healthStats = statsData;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load catalog: $e';
        _loading = false;
      });
    }
  }

  Future<void> _triggerValidation() async {
    final messenger = ScaffoldMessenger.of(context);
    
    try {
      final client = ref.read(apiClientProvider);
      final result = await client.adminValidateImages(
        limit: 50,
        retailer: _selectedRetailer,
      );
      
      messenger.showSnackBar(
        SnackBar(
          content: Text('Validated ${result['validated']} items'),
          backgroundColor: AppTheme.success,
        ),
      );
      
      // Reload data
      await _loadData();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Validation failed: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog Preview'),
        actions: [
          // View mode toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'grid', icon: Icon(Icons.grid_view)),
              ButtonSegment(value: 'comparison', icon: Icon(Icons.compare)),
            ],
            selected: {_viewMode},
            onSelectionChanged: (value) {
              setState(() => _viewMode = value.first);
            },
          ),
          const SizedBox(width: 8),
          // Validate button
          TextButton.icon(
            onPressed: _loading ? null : _triggerValidation,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Validate'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Stats header
          _buildStatsHeader(),
          
          // Main content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
                    : _viewMode == 'grid'
                        ? _buildGridView()
                        : _buildComparisonView(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    final total = _healthStats['total'] ?? 0;
    final validated = _healthStats['validated'] ?? 0;
    final avgScore = _healthStats['averageScore'] ?? 0;
    final byBand = _healthStats['byBand'] as Map<String, dynamic>? ?? {};
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.surface,
      child: Row(
        children: [
          _StatChip(
            label: 'Total',
            value: total.toString(),
            color: AppTheme.textPrimary,
          ),
          const SizedBox(width: 16),
          _StatChip(
            label: 'Validated',
            value: '$validated / $total',
            color: AppTheme.primaryAction,
          ),
          const SizedBox(width: 16),
          _StatChip(
            label: 'Avg Score',
            value: avgScore.toString(),
            color: _getBandColor(avgScore as int),
          ),
          const Spacer(),
          _BandChip(label: 'Green', count: byBand['green'] ?? 0, color: AppTheme.success),
          const SizedBox(width: 8),
          _BandChip(label: 'Yellow', count: byBand['yellow'] ?? 0, color: AppTheme.warning),
          const SizedBox(width: 8),
          _BandChip(label: 'Red', count: byBand['red'] ?? 0, color: AppTheme.error),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return _CatalogPreviewCard(item: item);
      },
    );
  }

  Widget _buildComparisonView() {
    // Side-by-side comparison: legacy vs premium rendering
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return _ComparisonCard(item: item);
      },
    );
  }

  Color _getBandColor(int score) {
    if (score >= 75) return AppTheme.success;
    if (score >= 45) return AppTheme.warning;
    return AppTheme.error;
  }
}

/// Stat chip for header.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Band count chip.
class _BandChip extends StatelessWidget {
  const _BandChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Preview card with premium image rendering and health score.
class _CatalogPreviewCard extends StatelessWidget {
  const _CatalogPreviewCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.firstImageUrl;
    final proxiedUrl = imageUrl != null 
        ? ApiClient.proxyImageUrl(imageUrl, width: ImageWidth.card)
        : null;
    final bgUrl = imageUrl != null
        ? ApiClient.proxyImageUrl(imageUrl, width: ImageWidth.thumbnail)
        : null;
    
    // Extract creative health from item if available
    final healthScore = item.creativeHealthScore ?? 0;
    final healthBand = item.creativeHealthBand ?? 'unknown';
    
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Premium image preview
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (proxiedUrl != null && bgUrl != null)
                  _PremiumImagePreview(
                    imageUrl: proxiedUrl,
                    backgroundUrl: bgUrl,
                  )
                else
                  Container(
                    color: AppTheme.surfaceVariant,
                    child: const Icon(Icons.image_not_supported),
                  ),
                
                // Health score badge
                Positioned(
                  top: 8,
                  right: 8,
                  child: _HealthBadge(score: healthScore, band: healthBand),
                ),
              ],
            ),
          ),
          
          // Info
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    '${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Premium image preview with blurred background.
class _PremiumImagePreview extends StatelessWidget {
  const _PremiumImagePreview({
    required this.imageUrl,
    required this.backgroundUrl,
  });

  final String imageUrl;
  final String backgroundUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred background
        Transform.scale(
          scale: 1.1,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: CachedNetworkImage(
              imageUrl: backgroundUrl,
              fit: BoxFit.cover,
              memCacheWidth: 400,
            ),
          ),
        ),
        // Contained foreground
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              memCacheWidth: 800,
            ),
          ),
        ),
      ],
    );
  }
}

/// Health score badge.
class _HealthBadge extends StatelessWidget {
  const _HealthBadge({required this.score, required this.band});

  final int score;
  final String band;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (band) {
      case 'green':
        color = AppTheme.success;
        break;
      case 'yellow':
        color = AppTheme.warning;
        break;
      case 'red':
        color = AppTheme.error;
        break;
      default:
        color = AppTheme.textSecondary;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        score.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Side-by-side comparison card (legacy vs premium).
class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.firstImageUrl;
    final proxiedUrl = imageUrl != null
        ? ApiClient.proxyImageUrl(imageUrl, width: ImageWidth.card)
        : null;
    final bgUrl = imageUrl != null
        ? ApiClient.proxyImageUrl(imageUrl, width: ImageWidth.thumbnail)
        : null;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            
            // Side-by-side comparison
            Row(
              children: [
                // Legacy rendering
                Expanded(
                  child: Column(
                    children: [
                      const Text('Legacy (cover)', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      AspectRatio(
                        aspectRatio: 4 / 5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: proxiedUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: proxiedUrl,
                                  fit: BoxFit.cover,
                                )
                              : Container(color: AppTheme.surfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                
                // Premium rendering
                Expanded(
                  child: Column(
                    children: [
                      const Text('Premium (contain + blur)', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      AspectRatio(
                        aspectRatio: 4 / 5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: proxiedUrl != null && bgUrl != null
                              ? _PremiumImagePreview(
                                  imageUrl: proxiedUrl,
                                  backgroundUrl: bgUrl,
                                )
                              : Container(color: AppTheme.surfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
