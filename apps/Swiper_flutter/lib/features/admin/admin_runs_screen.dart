import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

class AdminRunsScreen extends ConsumerStatefulWidget {
  const AdminRunsScreen({super.key});

  @override
  ConsumerState<AdminRunsScreen> createState() => _AdminRunsScreenState();
}

class _AdminRunsScreenState extends ConsumerState<AdminRunsScreen> {
  List<Map<String, dynamic>> _runs = [];
  Map<String, Map<String, dynamic>> _sourcesCache = {};
  bool _loading = true;
  String? _error;

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
      final runs = await client.adminGetRuns();
      
      // Load sources for context
      try {
        final sources = await client.adminGetSources();
        _sourcesCache = {
          for (final s in sources)
            if (s['id'] != null) s['id'] as String: s
        };
      } catch (_) {
        // Sources not critical, continue without
      }
      
      setState(() {
        _runs = runs;
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
        title: const Text('Ingestion Runs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildContent(),
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
            Text('Error loading runs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingUnit / 2),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.spacingUnit),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }
    
    if (_runs.isEmpty) {
      return const Center(
        child: Text('No runs yet. Trigger a run from Sources.'),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        itemCount: _runs.length,
        itemBuilder: (context, i) => _RunCard(
          run: _runs[i],
          source: _sourcesCache[_runs[i]['sourceId']],
          onTap: () => _showRunDetail(_runs[i]['id'] as String? ?? ''),
        ),
      ),
    );
  }

  Future<void> _showRunDetail(String runId) async {
    if (runId.isEmpty) return;
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final client = ref.read(apiClientProvider);
      final run = await client.adminGetRun(runId);
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      
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
          builder: (context, scrollController) => _RunDetailSheet(
            run: run,
            source: _sourcesCache[run['sourceId']],
            scrollController: scrollController,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading run details: $e')),
      );
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

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run, this.source, required this.onTap});

  final Map<String, dynamic> run;
  final Map<String, dynamic>? source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sourceId = run['sourceId'] as String? ?? 'Unknown';
    final status = run['status'] as String? ?? 'unknown';
    final startedAt = _parseTimestamp(run['startedAt']);
    final finishedAt = _parseTimestamp(run['finishedAt']);
    final stats = run['stats'] as Map<String, dynamic>?;
    final errorSummary = run['errorSummary'] as String?;
    
    // Get source info for better display - try baseUrl first, then other URL fields
    final sourceName = source?['name'] as String? ?? sourceId;
    final sourceMode = source?['mode'] as String? ?? '';
    final baseUrl = source?['baseUrl'] as String?;
    final sourceUrl = baseUrl ?? source?['feedUrl'] as String? ?? source?['crawlRootUrl'] as String?;
    final sourceDomain = _extractDomain(sourceUrl);
    
    // Calculate duration
    String? duration;
    if (startedAt != null && finishedAt != null) {
      final diff = finishedAt.difference(startedAt);
      if (diff.inMinutes > 0) {
        duration = '${diff.inMinutes}m ${diff.inSeconds % 60}s';
      } else {
        duration = '${diff.inSeconds}s';
      }
    }
    
    final isSuccess = status == 'completed' || status == 'success' || status == 'succeeded';
    final isError = status == 'failed' || status == 'error';
    final isRunning = status == 'running' || status == 'in_progress';
    
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with favicon
              Row(
                children: [
                  // Website favicon with status overlay
                  Stack(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.textCaption.withValues(alpha: 0.2)),
                        ),
                        child: sourceDomain != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: Image.network(
                                  _faviconUrl(sourceDomain),
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildModeIcon(sourceMode),
                                ),
                              )
                            : _buildModeIcon(sourceMode),
                      ),
                      // Status indicator badge
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isSuccess
                                ? AppTheme.positiveLike
                                : isError
                                    ? AppTheme.negativeDislike
                                    : isRunning
                                        ? AppTheme.primaryAction
                                        : AppTheme.textCaption,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppTheme.surface, width: 2),
                          ),
                          child: Icon(
                            isSuccess
                                ? Icons.check
                                : isError
                                    ? Icons.close
                                    : isRunning
                                        ? Icons.sync
                                        : Icons.schedule,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppTheme.spacingUnit),
                  // Source info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sourceName,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (sourceDomain != null) ...[
                              Icon(Icons.language, size: 12, color: AppTheme.textCaption),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  sourceDomain,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ] else ...[
                              Text(
                                sourceId.length > 12 ? '${sourceId.substring(0, 12)}...' : sourceId,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textCaption,
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Status badge and time
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSuccess
                              ? AppTheme.positiveLike.withValues(alpha: 0.15)
                              : isError
                                  ? AppTheme.negativeDislike.withValues(alpha: 0.15)
                                  : isRunning
                                      ? AppTheme.primaryAction.withValues(alpha: 0.15)
                                      : AppTheme.textCaption.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                        ),
                        child: Text(
                          _formatStatus(status),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isSuccess
                                ? AppTheme.positiveLike
                                : isError
                                    ? AppTheme.negativeDislike
                                    : isRunning
                                        ? AppTheme.primaryAction
                                        : AppTheme.textCaption,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (startedAt != null)
                        Text(
                          _formatTimestamp(startedAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textCaption,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              // Stats row
              Row(
                children: [
                  if (stats != null) ...[
                    _StatChip(
                      icon: Icons.add_circle_outline,
                      label: 'Upserted',
                      value: '${stats['upserted'] ?? 0}',
                    ),
                    const SizedBox(width: AppTheme.spacingUnit),
                    if ((stats['skipped'] ?? 0) > 0)
                      _StatChip(
                        icon: Icons.skip_next,
                        label: 'Skipped',
                        value: '${stats['skipped']}',
                      ),
                    if ((stats['failed'] ?? stats['errors'] ?? 0) > 0) ...[
                      const SizedBox(width: AppTheme.spacingUnit),
                      _StatChip(
                        icon: Icons.warning_amber,
                        label: 'Errors',
                        value: '${stats['failed'] ?? stats['errors'] ?? 0}',
                        isError: true,
                      ),
                    ],
                  ],
                  const Spacer(),
                  // Duration
                  if (duration != null)
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 12, color: AppTheme.textCaption),
                        const SizedBox(width: 4),
                        Text(
                          duration,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textCaption,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              // Error summary
              if (errorSummary != null) ...[
                const SizedBox(height: AppTheme.spacingUnit / 2),
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit / 2),
                  decoration: BoxDecoration(
                    color: AppTheme.negativeDislike.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 14, color: AppTheme.negativeDislike),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          errorSummary,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.negativeDislike,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  DateTime? _parseTimestamp(dynamic ts) {
    if (ts == null) return null;
    if (ts is String) return DateTime.tryParse(ts);
    if (ts is Map && ts['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch((ts['_seconds'] as int) * 1000);
    }
    return null;
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildModeIcon(String mode) {
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

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'succeeded':
        return 'SUCCESS';
      case 'completed':
        return 'SUCCESS';
      case 'failed':
        return 'FAILED';
      case 'running':
        return 'RUNNING';
      case 'in_progress':
        return 'RUNNING';
      default:
        return status.toUpperCase();
    }
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    this.isError = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isError ? AppTheme.negativeDislike : AppTheme.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isError ? AppTheme.negativeDislike : AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _RunDetailSheet extends StatelessWidget {
  const _RunDetailSheet({
    required this.run,
    this.source,
    required this.scrollController,
  });

  final Map<String, dynamic> run;
  final Map<String, dynamic>? source;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final runId = run['id'] as String? ?? 'Unknown';
    final sourceId = run['sourceId'] as String? ?? 'Unknown';
    final status = run['status'] as String? ?? 'unknown';
    final startedAt = _parseTimestamp(run['startedAt']);
    final finishedAt = _parseTimestamp(run['finishedAt']);
    final stats = run['stats'] as Map<String, dynamic>?;
    final errorSummary = run['errorSummary'] as String?;
    final jobs = run['jobs'] as List?;
    
    // Source info
    final sourceName = source?['name'] as String? ?? sourceId;
    final sourceUrl = source?['feedUrl'] as String? ?? source?['crawlRootUrl'] as String?;
    final sourceType = source?['type'] as String?;
    
    // Calculate duration
    String? duration;
    if (startedAt != null && finishedAt != null) {
      final diff = finishedAt.difference(startedAt);
      if (diff.inMinutes > 0) {
        duration = '${diff.inMinutes} min ${diff.inSeconds % 60} sec';
      } else {
        duration = '${diff.inSeconds} seconds';
      }
    }
    
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
          // Header
          Text('Ingestion Run Details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          
          // Source Section
          _SectionHeader(title: 'Source'),
          _DetailRow(label: 'Name', value: sourceName),
          _DetailRow(label: 'Source ID', value: sourceId),
          if (sourceType != null) _DetailRow(label: 'Type', value: sourceType),
          if (sourceUrl != null) _DetailRow(label: 'URL', value: sourceUrl, isUrl: true),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          
          // Run Info Section
          _SectionHeader(title: 'Run Information'),
          _DetailRow(label: 'Run ID', value: runId),
          _DetailRow(label: 'Status', value: status.toUpperCase(), 
            valueColor: status == 'completed' || status == 'success' 
                ? AppTheme.positiveLike 
                : status == 'failed' || status == 'error'
                    ? AppTheme.negativeDislike
                    : null),
          if (startedAt != null) 
            _DetailRow(label: 'Started', value: _formatFullTimestamp(startedAt)),
          if (finishedAt != null) 
            _DetailRow(label: 'Finished', value: _formatFullTimestamp(finishedAt)),
          if (duration != null) 
            _DetailRow(label: 'Duration', value: duration),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          
          // Stats Section
          if (stats != null) ...[
            _SectionHeader(title: 'Statistics'),
            Wrap(
              spacing: AppTheme.spacingUnit,
              runSpacing: AppTheme.spacingUnit,
              children: [
                _StatCard(label: 'Upserted', value: '${stats['upserted'] ?? 0}', icon: Icons.add_circle_outline),
                if (stats['skipped'] != null) _StatCard(label: 'Skipped', value: '${stats['skipped']}', icon: Icons.skip_next),
                if (stats['errors'] != null) _StatCard(label: 'Errors', value: '${stats['errors']}', icon: Icons.warning_amber, isError: (stats['errors'] as int? ?? 0) > 0),
                if (stats['processed'] != null) _StatCard(label: 'Processed', value: '${stats['processed']}', icon: Icons.check_circle_outline),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit * 2),
          ],
          
          // Error Section
          if (errorSummary != null) ...[
            _SectionHeader(title: 'Error Details'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              decoration: BoxDecoration(
                color: AppTheme.negativeDislike.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: AppTheme.negativeDislike.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                errorSummary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.negativeDislike,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit * 2),
          ],
          
          // Jobs Section
          if (jobs != null && jobs.isNotEmpty) ...[
            _SectionHeader(title: 'Jobs (${jobs.length})'),
            ...jobs.take(10).map((job) {
              final jobMap = job as Map<String, dynamic>;
              final jobStatus = jobMap['status'] as String? ?? 'unknown';
              final jobUrl = jobMap['url'] as String?;
              final itemsCount = jobMap['itemsCount'] as int?;
              return Container(
                margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit / 2),
                padding: const EdgeInsets.all(AppTheme.spacingUnit / 2),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                ),
                child: Row(
                  children: [
                    Icon(
                      jobStatus == 'completed' ? Icons.check_circle : Icons.error_outline,
                      size: 16,
                      color: jobStatus == 'completed' ? AppTheme.positiveLike : AppTheme.negativeDislike,
                    ),
                    const SizedBox(width: AppTheme.spacingUnit / 2),
                    Expanded(
                      child: Text(
                        jobUrl ?? 'Unknown',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (itemsCount != null)
                      Text(
                        '$itemsCount items',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              );
            }),
            if (jobs.length > 10)
              Text(
                '... and ${jobs.length - 10} more jobs',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
          ],
        ],
      ),
    );
  }

  DateTime? _parseTimestamp(dynamic ts) {
    if (ts == null) return null;
    if (ts is String) return DateTime.tryParse(ts);
    if (ts is Map && ts['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch((ts['_seconds'] as int) * 1000);
    }
    return null;
  }

  String _formatFullTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingUnit / 2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isUrl = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingUnit / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: valueColor,
                decoration: isUrl ? TextDecoration.underline : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.isError = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit, vertical: AppTheme.spacingUnit / 2),
      decoration: BoxDecoration(
        color: isError 
            ? AppTheme.negativeDislike.withValues(alpha: 0.1)
            : AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isError ? AppTheme.negativeDislike : AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isError ? AppTheme.negativeDislike : null,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
