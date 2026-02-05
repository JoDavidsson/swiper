import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/deck_provider.dart';

class AdminItemsScreen extends ConsumerStatefulWidget {
  const AdminItemsScreen({super.key});

  @override
  ConsumerState<AdminItemsScreen> createState() => _AdminItemsScreenState();
}

class _AdminItemsScreenState extends ConsumerState<AdminItemsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedSource;
  bool? _activeFilter; // null = all, true = active only, false = inactive only
  List<Map<String, dynamic>> _allItems = [];
  List<String> _availableSources = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final result = await client.adminGetItems(limit: 200);
      final itemsList = result['items'] as List? ?? [];
      final items = itemsList.cast<Map<String, dynamic>>();
      
      // Extract unique source IDs
      final sources = <String>{};
      for (final item in items) {
        final sourceId = item['sourceId'] as String?;
        if (sourceId != null && sourceId.isNotEmpty) {
          sources.add(sourceId);
        }
      }
      
      setState(() {
        _allItems = items;
        _availableSources = sources.toList()..sort();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _allItems.where((item) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final title = (item['title'] as String? ?? '').toLowerCase();
        final brand = (item['brand'] as String? ?? '').toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!title.contains(query) && !brand.contains(query)) {
          return false;
        }
      }
      
      // Source filter
      if (_selectedSource != null) {
        final sourceId = item['sourceId'] as String?;
        if (sourceId != _selectedSource) {
          return false;
        }
      }
      
      // Active filter
      if (_activeFilter != null) {
        final isActive = item['isActive'] as bool? ?? true;
        if (isActive != _activeFilter) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Items'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filters
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            color: AppTheme.surface,
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by title or brand...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: AppTheme.spacingUnit),
                // Filter row
                Row(
                  children: [
                    // Source filter
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _selectedSource,
                        decoration: InputDecoration(
                          labelText: 'Source',
                          contentPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All sources')),
                          ..._availableSources.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                        ],
                        onChanged: (value) => setState(() => _selectedSource = value),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingUnit),
                    // Active filter
                    Expanded(
                      child: DropdownButtonFormField<bool?>(
                        value: _activeFilter,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          contentPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: true, child: Text('Active')),
                          DropdownMenuItem(value: false, child: Text('Inactive')),
                        ],
                        onChanged: (value) => setState(() => _activeFilter = value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit, vertical: AppTheme.spacingUnit / 2),
            child: Row(
              children: [
                Text(
                  '${_filteredItems.length} of ${_allItems.length} items',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                ),
                const Spacer(),
                if (_searchQuery.isNotEmpty || _selectedSource != null || _activeFilter != null)
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _selectedSource = null;
                        _activeFilter = null;
                      });
                    },
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
          ),
          // Items list
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.negativeDislike),
            const SizedBox(height: AppTheme.spacingUnit),
            Text('Error loading items', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingUnit / 2),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.spacingUnit),
            ElevatedButton(onPressed: _loadItems, child: const Text('Retry')),
          ],
        ),
      );
    }
    
    if (_allItems.isEmpty) {
      return const Center(
        child: Text('No items yet. Ingest a feed (Supply Engine or Run now on a source).'),
      );
    }
    
    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: AppTheme.textCaption),
            const SizedBox(height: AppTheme.spacingUnit),
            Text('No items match your filters', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadItems,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return _AdminItemCard(
            item: item,
            onTap: () => _showItemDetail(item),
          );
        },
      ),
    );
  }

  void _showItemDetail(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _AdminItemDetailSheet(
          item: item,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _AdminItemCard extends StatelessWidget {
  const _AdminItemCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = item['title'] as String? ?? 'Untitled';
    final price = item['priceAmount'];
    final currency = item['priceCurrency'] as String? ?? 'SEK';
    final sourceId = item['sourceId'] as String? ?? '';
    final isActive = item['isActive'] as bool? ?? true;
    final brand = item['brand'] as String?;
    final imageUrl = _getFirstImageUrl(item);
    final priceStr = price is num ? (price).toStringAsFixed(0) : (price?.toString() ?? '?');
    
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            SizedBox(
              width: 80,
              height: 80,
              child: imageUrl != null
                  ? Image.network(
                      ApiClient.proxyImageUrl(imageUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.background,
                        child: const Icon(Icons.image_not_supported, color: AppTheme.textCaption),
                      ),
                    )
                  : Container(
                      color: AppTheme.background,
                      child: const Icon(Icons.image_not_supported, color: AppTheme.textCaption),
                    ),
            ),
            // Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingUnit),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.negativeDislike.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Inactive',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppTheme.negativeDislike,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$priceStr $currency',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.primaryAction),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${brand != null ? '$brand • ' : ''}$sourceId',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // Chevron
            const Padding(
              padding: EdgeInsets.all(AppTheme.spacingUnit),
              child: Icon(Icons.chevron_right, color: AppTheme.textCaption),
            ),
          ],
        ),
      ),
    );
  }

  String? _getFirstImageUrl(Map<String, dynamic> item) {
    final images = item['images'] as List?;
    if (images != null && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) {
        return first['url'] as String?;
      } else if (first is String) {
        return first;
      }
    }
    return item['imageUrl'] as String?;
  }
}

class _AdminItemDetailSheet extends StatelessWidget {
  const _AdminItemDetailSheet({required this.item, required this.scrollController});

  final Map<String, dynamic> item;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final title = item['title'] as String? ?? 'Untitled';
    final price = item['priceAmount'];
    final currency = item['priceCurrency'] as String? ?? 'SEK';
    final priceStr = price is num ? (price).toStringAsFixed(0) : (price?.toString() ?? '?');
    
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(AppTheme.spacingUnit * 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
              decoration: BoxDecoration(
                color: AppTheme.textCaption.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppTheme.spacingUnit / 2),
          Text(
            '$priceStr $currency',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.primaryAction),
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Text('Item Details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.spacingUnit),
          _buildDetailRow(context, 'ID', item['id']?.toString() ?? 'N/A'),
          _buildDetailRow(context, 'Source', item['sourceId']?.toString() ?? 'N/A'),
          _buildDetailRow(context, 'Brand', item['brand']?.toString() ?? 'N/A'),
          _buildDetailRow(context, 'Status', (item['isActive'] as bool? ?? true) ? 'Active' : 'Inactive'),
          _buildDetailRow(context, 'New/Used', item['newUsed']?.toString() ?? 'N/A'),
          _buildDetailRow(context, 'Size Class', item['sizeClass']?.toString() ?? 'N/A'),
          _buildDetailRow(context, 'Material', item['material']?.toString() ?? 'N/A'),
          _buildDetailRow(context, 'Color', item['colorFamily']?.toString() ?? 'N/A'),
          if (item['styleTags'] != null && (item['styleTags'] as List).isNotEmpty)
            _buildDetailRow(context, 'Style Tags', (item['styleTags'] as List).join(', ')),
          if (item['dimensionsCm'] != null)
            _buildDetailRow(context, 'Dimensions', _formatDimensions(item['dimensionsCm'])),
          if (item['outboundUrl'] != null)
            _buildDetailRow(context, 'Outbound URL', item['outboundUrl']!.toString()),
          if (item['lastUpdatedAt'] != null)
            _buildDetailRow(context, 'Last Updated', _formatDate(item['lastUpdatedAt'])),
          if (item['createdAt'] != null)
            _buildDetailRow(context, 'Created', _formatDate(item['createdAt'])),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          // Images section
          if (_getImages(item).isNotEmpty) ...[
            Text('Images (${_getImages(item).length})', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppTheme.spacingUnit),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _getImages(item).length,
                itemBuilder: (context, i) {
                  final url = _getImages(item)[i];
                  return Padding(
                    padding: EdgeInsets.only(right: i < _getImages(item).length - 1 ? AppTheme.spacingUnit : 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      child: Image.network(
                        ApiClient.proxyImageUrl(url),
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 120,
                          height: 120,
                          color: AppTheme.background,
                          child: const Icon(Icons.broken_image, color: AppTheme.textCaption),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: AppTheme.spacingUnit * 2),
          // Raw JSON section
          ExpansionTile(
            title: const Text('Raw Data'),
            tilePadding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingUnit),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                ),
                width: double.infinity,
                child: SelectableText(
                  _formatJson(item),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingUnit / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getImages(Map<String, dynamic> item) {
    final images = item['images'] as List?;
    if (images == null) return [];
    return images.map((img) {
      if (img is Map) return img['url'] as String?;
      if (img is String) return img;
      return null;
    }).whereType<String>().toList();
  }

  String _formatDimensions(dynamic dims) {
    if (dims is Map) {
      final w = dims['w'];
      final h = dims['h'];
      final d = dims['d'];
      return '${w ?? '?'} × ${h ?? '?'} × ${d ?? '?'} cm';
    }
    return dims.toString();
  }

  String _formatDate(dynamic date) {
    if (date is String) {
      return date.split('T').first;
    }
    if (date is Map && date['_seconds'] != null) {
      final seconds = date['_seconds'] as int;
      final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      return dt.toIso8601String().split('T').first;
    }
    return date.toString();
  }

  String _formatJson(Map<String, dynamic> json) {
    final buffer = StringBuffer();
    _formatJsonRecursive(json, buffer, 0);
    return buffer.toString();
  }

  void _formatJsonRecursive(dynamic value, StringBuffer buffer, int indent) {
    final prefix = '  ' * indent;
    if (value is Map) {
      buffer.writeln('{');
      final entries = value.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        buffer.write('$prefix  "${entries[i].key}": ');
        _formatJsonRecursive(entries[i].value, buffer, indent + 1);
        if (i < entries.length - 1) buffer.write(',');
        buffer.writeln();
      }
      buffer.write('$prefix}');
    } else if (value is List) {
      if (value.isEmpty) {
        buffer.write('[]');
      } else {
        buffer.writeln('[');
        for (var i = 0; i < value.length; i++) {
          buffer.write('$prefix  ');
          _formatJsonRecursive(value[i], buffer, indent + 1);
          if (i < value.length - 1) buffer.write(',');
          buffer.writeln();
        }
        buffer.write('$prefix]');
      }
    } else if (value is String) {
      final escaped = value.replaceAll('"', '\\"').replaceAll('\n', '\\n');
      buffer.write('"$escaped"');
    } else {
      buffer.write(value);
    }
  }
}
