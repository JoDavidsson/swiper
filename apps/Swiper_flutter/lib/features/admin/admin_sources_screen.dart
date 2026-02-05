import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

class AdminSourcesScreen extends ConsumerStatefulWidget {
  const AdminSourcesScreen({super.key});

  @override
  ConsumerState<AdminSourcesScreen> createState() => _AdminSourcesScreenState();
}

class _AdminSourcesScreenState extends ConsumerState<AdminSourcesScreen> {
  List<Map<String, dynamic>> _sources = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final sources = await client.adminGetSources();
      setState(() {
        _sources = sources;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Sources'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSources,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSourceDialog(context, null),
        child: const Icon(Icons.add),
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
            Text('Error loading sources', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingUnit / 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            ElevatedButton(onPressed: _loadSources, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.source_outlined, size: 64, color: AppTheme.textCaption),
            const SizedBox(height: AppTheme.spacingUnit),
            Text('No sources yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingUnit / 2),
            Text('Add a source to start ingesting data', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.spacingUnit * 2),
            ElevatedButton.icon(
              onPressed: () => _showSourceDialog(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add source'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSources,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        itemCount: _sources.length,
        itemBuilder: (context, i) {
          final s = _sources[i];
          return _SourceCard(
            source: s,
            onEdit: () => _showSourceDialog(context, s),
            onRun: () => _runNow(context, s['id'] as String? ?? ''),
            onDelete: () => _confirmDelete(context, s),
          );
        },
      ),
    );
  }

  Future<void> _runNow(BuildContext context, String sourceId) async {
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

  void _showSourceDialog(BuildContext context, Map<String, dynamic>? existingSource) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _SourceDialog(
        existingSource: existingSource,
        onSaved: () {
          _loadSources();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(existingSource == null ? 'Source created' : 'Source updated')),
            );
          }
        },
        onCreate: (body) => ref.read(apiClientProvider).adminCreateSource(body),
        onUpdate: existingSource != null
            ? (body) => ref.read(apiClientProvider).adminUpdateSource(existingSource['id'] as String, body)
            : null,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Map<String, dynamic> source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete source?'),
        content: Text('Are you sure you want to delete "${source['name']}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.negativeDislike),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(apiClientProvider).adminDeleteSource(source['id'] as String);
        _loadSources();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Source deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}

/// Extracts domain from a URL for favicon fetching
String? _extractDomain(String? url) {
  if (url == null || url.isEmpty) return null;
  try {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    return uri.host.isNotEmpty ? uri.host : null;
  } catch (_) {
    return null;
  }
}

/// Returns favicon URL for a domain using Google's favicon service
String _faviconUrl(String domain) {
  return 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.onEdit,
    required this.onRun,
    required this.onDelete,
  });

  final Map<String, dynamic> source;
  final VoidCallback onEdit;
  final VoidCallback onRun;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = source['name'] as String? ?? 'Unnamed';
    final mode = source['mode'] as String? ?? '';
    final isEnabled = source['isEnabled'] as bool? ?? false;
    final baseUrl = source['baseUrl'] as String?;
    final domain = _extractDomain(baseUrl);

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Row(
            children: [
              // Favicon / icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.textCaption.withValues(alpha: 0.2)),
                ),
                child: domain != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(
                          _faviconUrl(domain),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _modeIcon(mode),
                        ),
                      )
                    : _modeIcon(mode),
              ),
              const SizedBox(width: AppTheme.spacingUnit),
              // Source info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _modeColor(mode).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            mode.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _modeColor(mode),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isEnabled ? Icons.check_circle : Icons.pause_circle,
                          size: 14,
                          color: isEnabled ? AppTheme.positiveLike : AppTheme.textCaption,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isEnabled ? 'Enabled' : 'Disabled',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (domain != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        domain,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textCaption,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: onRun,
                    tooltip: 'Run now',
                    color: AppTheme.primaryAction,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeIcon(String mode) {
    IconData icon;
    switch (mode) {
      case 'crawl':
        icon = Icons.travel_explore;
        break;
      case 'feed':
        icon = Icons.rss_feed;
        break;
      case 'api':
        icon = Icons.api;
        break;
      default:
        icon = Icons.source;
    }
    return Center(child: Icon(icon, color: AppTheme.textCaption));
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'crawl':
        return Colors.blue;
      case 'feed':
        return Colors.orange;
      case 'api':
        return Colors.purple;
      default:
        return AppTheme.textCaption;
    }
  }
}

const List<String> _sourceModes = ['feed', 'api', 'crawl', 'manual'];

/// New simplified dialog for creating sources with auto-discovery.
/// Single URL input -> Detect -> Preview -> Create
class _SourceDialog extends StatefulWidget {
  const _SourceDialog({
    this.existingSource,
    required this.onSaved,
    required this.onCreate,
    this.onUpdate,
  });

  final Map<String, dynamic>? existingSource;
  final VoidCallback onSaved;
  final Future<String> Function(Map<String, dynamic> body) onCreate;
  final Future<void> Function(Map<String, dynamic> body)? onUpdate;

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _nameController;
  late final TextEditingController _rateLimitController;
  late bool _isEnabled;
  bool _loading = false;
  bool _detecting = false;
  bool _showAdvanced = false;
  
  // Discovery results
  Map<String, dynamic>? _discoveryResult;
  String? _discoveryError;

  bool get isEditing => widget.existingSource != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existingSource;
    // For editing, use the original URL if available, otherwise baseUrl
    final existingUrl = s?['url'] as String? ?? s?['baseUrl'] as String? ?? '';
    _urlController = TextEditingController(text: existingUrl);
    _nameController = TextEditingController(text: s?['name'] as String? ?? '');
    _rateLimitController = TextEditingController(text: '${s?['rateLimitRps'] ?? 1}');
    _isEnabled = s?['isEnabled'] as bool? ?? true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _rateLimitController.dispose();
    super.dispose();
  }

  /// Call the preview endpoint to auto-discover configuration
  Future<void> _detect(WidgetRef ref) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a URL')),
      );
      return;
    }

    setState(() {
      _detecting = true;
      _discoveryError = null;
      _discoveryResult = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      final rateLimit = double.tryParse(_rateLimitController.text.trim()) ?? 1.0;
      final result = await client.adminPreviewSource(url, rateLimitRps: rateLimit);
      
      if (!mounted) return;
      setState(() {
        _discoveryResult = result;
        _detecting = false;
      });
      
      // Auto-fill name from domain if not set
      if (_nameController.text.isEmpty) {
        final discovery = result['discovery'] as Map<String, dynamic>?;
        final domain = discovery?['domain'] as String? ?? '';
        if (domain.isNotEmpty) {
          _nameController.text = domain.replaceFirst(RegExp(r'^www\.'), '');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _discoveryError = e.toString();
        _detecting = false;
      });
    }
  }

  Future<void> _submit(WidgetRef ref) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL is required')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      final rateLimit = double.tryParse(_rateLimitController.text.trim()) ?? 1.0;
      
      if (isEditing && widget.onUpdate != null) {
        // For editing, use the legacy update method
        final body = {
          'name': _nameController.text.trim(),
          'url': url,
          'baseUrl': _discoveryResult?['derivedConfig']?['baseUrl'] ?? url,
          'isEnabled': _isEnabled,
          'rateLimitRps': rateLimit.clamp(0.1, 100.0),
        };
        await widget.onUpdate!(body);
      } else {
        // For new sources, use create-with-discovery
        await client.adminCreateSourceWithDiscovery(
          url: url,
          name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
          rateLimitRps: rateLimit.clamp(0.1, 100.0),
          isEnabled: _isEnabled,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => AlertDialog(
        title: Text(isEditing ? 'Edit Retailer' : 'Add Retailer'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // URL input
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Website URL',
                    hintText: 'mio.se/soffor',
                    helperText: 'Enter a domain or category page URL',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (_) {
                    // Clear discovery results when URL changes
                    if (_discoveryResult != null) {
                      setState(() {
                        _discoveryResult = null;
                        _discoveryError = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: AppTheme.spacingUnit),
                
                // Detect button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _detecting ? null : () => _detect(ref),
                    icon: _detecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(_detecting ? 'Detecting...' : 'Detect'),
                  ),
                ),
                
                // Discovery results
                if (_discoveryError != null) ...[
                  const SizedBox(height: AppTheme.spacingUnit),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _discoveryError!,
                            style: TextStyle(color: AppTheme.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                if (_discoveryResult != null) ...[
                  const SizedBox(height: AppTheme.spacingUnit),
                  _buildDiscoveryPreview(),
                ],
                
                // Name field (optional)
                const SizedBox(height: AppTheme.spacingUnit),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'Auto-generated from domain',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                
                // Advanced settings toggle
                const SizedBox(height: AppTheme.spacingUnit / 2),
                InkWell(
                  onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: AppTheme.textCaption,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Advanced settings',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textCaption,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Advanced settings
                if (_showAdvanced) ...[
                  const SizedBox(height: AppTheme.spacingUnit),
                  TextField(
                    controller: _rateLimitController,
                    decoration: const InputDecoration(
                      labelText: 'Rate limit (req/s)',
                      helperText: 'Be polite to retailers - 1 req/s is recommended',
                      prefixIcon: Icon(Icons.speed),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppTheme.spacingUnit / 2),
                  SwitchListTile(
                    title: const Text('Enabled'),
                    subtitle: const Text('Disabled sources won\'t run automatically'),
                    value: _isEnabled,
                    onChanged: (v) => setState(() => _isEnabled = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _loading ? null : () => _submit(ref),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEditing ? 'Save' : 'Add Source'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDiscoveryPreview() {
    final discovery = _discoveryResult?['discovery'] as Map<String, dynamic>? ?? {};
    final derivedConfig = _discoveryResult?['derivedConfig'] as Map<String, dynamic>? ?? {};
    
    final domain = discovery['domain'] as String? ?? '';
    final sitemapCount = discovery['sitemap_count'] as int? ?? 0;
    final productUrls = discovery['product_urls_estimated'] as int? ?? 0;
    final matchingUrls = discovery['matching_path_urls'] as int? ?? 0;
    final strategy = derivedConfig['strategy'] as String? ?? 'crawl';
    final warnings = (discovery['warnings'] as List?)?.cast<String>() ?? [];
    final errors = (discovery['errors'] as List?)?.cast<String>() ?? [];
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Domain with favicon
          Row(
            children: [
              if (domain.isNotEmpty) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.textCaption.withValues(alpha: 0.2)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.network(
                      _faviconUrl(domain),
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.public, size: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.check_circle, color: AppTheme.success, size: 16),
              const SizedBox(width: 4),
              Text(
                'Domain: $domain',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Stats row
          _buildStatRow(Icons.map, 'Sitemaps found', sitemapCount.toString()),
          _buildStatRow(Icons.shopping_bag, 'Product URLs', productUrls > 0 ? '~$productUrls' : '0'),
          if (matchingUrls > 0)
            _buildStatRow(Icons.filter_list, 'Matching path', '~$matchingUrls'),
          _buildStatRow(
            Icons.auto_awesome,
            'Strategy',
            strategy == 'sitemap' ? 'Sitemap discovery' : 'Category crawl',
          ),
          
          // Warnings
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final w in warnings.take(2))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, color: AppTheme.warning, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        w,
                        style: TextStyle(color: AppTheme.warning, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          
          // Errors
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in errors.take(2))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error, color: AppTheme.error, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        e,
                        style: TextStyle(color: AppTheme.error, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildStatRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
