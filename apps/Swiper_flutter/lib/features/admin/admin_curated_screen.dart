import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/deck_provider.dart';

/// Admin screen to manage curated onboarding sofas.
/// Allows viewing, adding, removing, and reordering the 6 curated items
/// shown in the visual gold card during onboarding.
class AdminCuratedScreen extends ConsumerStatefulWidget {
  const AdminCuratedScreen({super.key});

  @override
  ConsumerState<AdminCuratedScreen> createState() => _AdminCuratedScreenState();
}

class _AdminCuratedScreenState extends ConsumerState<AdminCuratedScreen> {
  List<Map<String, dynamic>>? _curatedSofas;
  List<Map<String, dynamic>>? _allItems;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      final results = await Future.wait([
        client.adminGetCuratedSofas(),
        client.adminGetItems(limit: 50),
      ]);
      setState(() {
        _curatedSofas = List<Map<String, dynamic>>.from(results[0] as List);
        _allItems = List<Map<String, dynamic>>.from(results[1] as List);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _addItem(String itemId) async {
    final client = ref.read(apiClientProvider);
    try {
      await client.adminAddCuratedSofa(itemId, _curatedSofas?.length ?? 0);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item added to curated list')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding item: $e')),
        );
      }
    }
  }

  Future<void> _removeItem(String itemId) async {
    final client = ref.read(apiClientProvider);
    try {
      await client.adminRemoveCuratedSofa(itemId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item removed from curated list')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing item: $e')),
        );
      }
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_curatedSofas == null) return;
    
    // Adjust for removal before insertion
    if (newIndex > oldIndex) newIndex--;
    
    final item = _curatedSofas!.removeAt(oldIndex);
    _curatedSofas!.insert(newIndex, item);
    setState(() {});

    final client = ref.read(apiClientProvider);
    try {
      final itemIds = _curatedSofas!.map((s) => s['id'] as String).toList();
      await client.adminReorderCuratedSofas(itemIds);
    } catch (e) {
      // Reload on error to restore server state
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering: $e')),
        );
      }
    }
  }

  void _showAddDialog() {
    if (_allItems == null || _curatedSofas == null) return;

    // Filter out already-curated items
    final curatedIds = _curatedSofas!.map((s) => s['id'] as String).toSet();
    final availableItems = _allItems!.where((item) {
      final id = item['id'] as String?;
      return id != null && !curatedIds.contains(id);
    }).toList();

    if (availableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more items available to add')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Item to Curated List',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: availableItems.length,
                itemBuilder: (context, i) {
                  final item = availableItems[i];
                  final id = item['id'] as String;
                  final title = item['title'] as String? ?? 'Untitled';
                  final images = item['images'] as List<dynamic>?;
                  final imageUrl = images?.isNotEmpty == true
                      ? (images![0] as Map<String, dynamic>)['url'] as String?
                      : null;

                  return ListTile(
                    leading: imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              ApiClient.proxyImageUrl(imageUrl, width: ImageWidth.thumbnail),
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 50,
                                height: 50,
                                color: Colors.grey[300],
                                child: const Icon(Icons.image_not_supported),
                              ),
                            ),
                          )
                        : Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey[300],
                            child: const Icon(Icons.image_not_supported),
                          ),
                    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle, color: AppTheme.primaryAction),
                      onPressed: () {
                        Navigator.pop(context);
                        _addItem(id);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Curated Onboarding Sofas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: _curatedSofas != null && _curatedSofas!.length < 6
          ? FloatingActionButton(
              onPressed: _showAddDialog,
              backgroundColor: AppTheme.primaryAction,
              child: const Icon(Icons.add),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error', style: TextStyle(color: AppTheme.negativeDislike)),
            const SizedBox(height: AppTheme.spacingUnit),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_curatedSofas == null || _curatedSofas!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.collections, size: 64, color: Colors.grey),
            const SizedBox(height: AppTheme.spacingUnit),
            const Text('No curated sofas yet'),
            const SizedBox(height: AppTheme.spacingUnit),
            ElevatedButton.icon(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Items'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.primaryAction),
                  const SizedBox(width: AppTheme.spacingUnit),
                  Expanded(
                    child: Text(
                      '${_curatedSofas!.length}/6 items. Drag to reorder. These appear in the visual gold card during onboarding.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit),
            itemCount: _curatedSofas!.length,
            onReorder: _reorder,
            itemBuilder: (context, i) {
              final sofa = _curatedSofas![i];
              final id = sofa['id'] as String;
              final title = sofa['title'] as String? ?? 'Untitled';
              final imageUrl = sofa['imageUrl'] as String?;
              final styleTags = sofa['styleTags'] as List<dynamic>?;

              return Card(
                key: ValueKey(id),
                margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                child: ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle, color: Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      imageUrl != null && imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                ApiClient.proxyImageUrl(imageUrl, width: ImageWidth.thumbnail),
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 50,
                                  height: 50,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.image_not_supported),
                                ),
                              ),
                            )
                          : Container(
                              width: 50,
                              height: 50,
                              color: Colors.grey[300],
                              child: const Icon(Icons.image_not_supported),
                            ),
                    ],
                  ),
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: styleTags != null && styleTags.isNotEmpty
                      ? Text(
                          styleTags.take(3).join(', '),
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle, color: AppTheme.negativeDislike),
                    onPressed: () => _showRemoveConfirmation(id, title),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showRemoveConfirmation(String itemId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "$title" from the curated list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeItem(itemId);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.negativeDislike),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
