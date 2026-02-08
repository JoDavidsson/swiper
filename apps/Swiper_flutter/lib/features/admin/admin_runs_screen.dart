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
            runId: runId,
            initialRun: run,
            source: _sourcesCache[run['sourceId']],
            scrollController: scrollController,
            apiClient: client,
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
    final isStopped = status == 'stopped';
    
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
                                    : isStopped
                                        ? Colors.orange
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
                                    : isStopped
                                        ? Icons.stop
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

/// Run detail sheet with real-time updates and stage visualization
class _RunDetailSheet extends ConsumerStatefulWidget {
  const _RunDetailSheet({
    required this.runId,
    required this.initialRun,
    this.source,
    required this.scrollController,
    required this.apiClient,
  });

  final String runId;
  final Map<String, dynamic> initialRun;
  final Map<String, dynamic>? source;
  final ScrollController scrollController;
  final dynamic apiClient; // ApiClient

  @override
  ConsumerState<_RunDetailSheet> createState() => _RunDetailSheetState();
}

class _RunDetailSheetState extends ConsumerState<_RunDetailSheet> {
  late Map<String, dynamic> _run;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _run = widget.initialRun;
    _startPollingIfNeeded();
  }

  @override
  void dispose() {
    _isPolling = false;
    super.dispose();
  }

  bool _isRunning(String status) {
    return status == 'running' || status == 'in_progress' || status == 'pending';
  }

  void _startPollingIfNeeded() {
    final status = _run['status'] as String? ?? 'unknown';
    if (_isRunning(status)) {
      _isPolling = true;
      _poll();
    }
  }

  Future<void> _poll() async {
    while (_isPolling && mounted) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || !_isPolling) break;
      
      try {
        final updated = await widget.apiClient.adminGetRun(widget.runId);
        if (!mounted) return;
        
        setState(() {
          _run = updated;
        });
        
        // Stop polling when finished
        final status = _run['status'] as String? ?? 'unknown';
        if (!_isRunning(status)) {
          _isPolling = false;
        }
      } catch (_) {
        // Continue polling on error
      }
    }
  }

  Future<void> _refresh() async {
    try {
      final updated = await widget.apiClient.adminGetRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = updated;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error refreshing: $e')),
      );
    }
  }

  bool _isStopping = false;

  Future<void> _stopCrawl() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Crawl?'),
        content: const Text(
          'Are you sure you want to stop this crawl? Partial results will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.negativeDislike),
            child: const Text('Stop'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isStopping = true);

    try {
      final sourceId = _run['sourceId'] as String? ?? '';
      await widget.apiClient.adminStopCrawl(sourceId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop signal sent — crawl will stop shortly')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error stopping crawl: $e')),
      );
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runId = _run['id'] as String? ?? 'Unknown';
    final sourceId = _run['sourceId'] as String? ?? 'Unknown';
    final status = _run['status'] as String? ?? 'unknown';
    final startedAt = _parseTimestamp(_run['startedAt']);
    final finishedAt = _parseTimestamp(_run['finishedAt']);
    final stats = _run['stats'] as Map<String, dynamic>? ?? {};
    final errorSummary = _run['errorSummary'] as String?;
    
    // Source info
    final sourceName = widget.source?['name'] as String? ?? sourceId;
    final baseUrl = widget.source?['baseUrl'] as String?;
    final sourceDomain = _extractDomain(baseUrl);
    
    // Stats
    final urlsDiscovered = stats['urlsDiscovered'] as int? ?? 0;
    final urlsCandidates = stats['urlsCandidateProducts'] as int? ?? 0;
    final fetched = stats['fetched'] as int? ?? 0;
    final success = stats['success'] as int? ?? 0;
    final failed = stats['failed'] as int? ?? 0;
    final upserted = stats['upserted'] as int? ?? 0;
    
    // Determine current stage
    final stage = _determineStage(status, urlsDiscovered, urlsCandidates, fetched, upserted);
    
    // Calculate duration
    final elapsed = _calculateElapsed(startedAt, finishedAt);
    
    final isRunning = _isRunning(status);
    final isSuccess = status == 'completed' || status == 'success' || status == 'succeeded';
    final isError = status == 'failed' || status == 'error';
    
    return SingleChildScrollView(
      controller: widget.scrollController,
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
          
          // Header with source info
          Row(
            children: [
              // Favicon
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
                          errorBuilder: (_, __, ___) => const Icon(Icons.travel_explore, color: AppTheme.textCaption),
                        ),
                      )
                    : const Icon(Icons.travel_explore, color: AppTheme.textCaption),
              ),
              const SizedBox(width: AppTheme.spacingUnit),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sourceName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    if (sourceDomain != null)
                      Text(sourceDomain, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              // Stop button (only when running)
              if (isRunning)
                _isStopping
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.stop_circle_outlined),
                        color: AppTheme.negativeDislike,
                        onPressed: _stopCrawl,
                        tooltip: 'Stop crawl',
                      ),
              // Refresh button
              IconButton(
                icon: Icon(Icons.refresh, color: isRunning ? AppTheme.textCaption : AppTheme.textSecondary),
                onPressed: isRunning ? null : _refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          
          // Status badge with live indicator
          _StatusBadge(
            status: status,
            isRunning: isRunning,
            elapsed: elapsed,
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          
          // Stage Stepper
          _StageStepper(currentStage: stage, isError: isError),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          
          // Progress Stats
          _ProgressStats(
            urlsDiscovered: urlsDiscovered,
            urlsCandidates: urlsCandidates,
            fetched: fetched,
            success: success,
            failed: failed,
            upserted: upserted,
            isRunning: isRunning,
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          
          // Error Section
          if (errorSummary != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              decoration: BoxDecoration(
                color: AppTheme.negativeDislike.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: AppTheme.negativeDislike.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, size: 18, color: AppTheme.negativeDislike),
                      const SizedBox(width: 8),
                      Text('Error', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.negativeDislike)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    errorSummary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.negativeDislike),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit * 2),
          ],
          
          // Technical Details (collapsed by default)
          ExpansionTile(
            title: Text('Technical Details', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.textSecondary)),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
            children: [
              _DetailRow(label: 'Run ID', value: runId),
              _DetailRow(label: 'Source ID', value: sourceId),
              if (startedAt != null) _DetailRow(label: 'Started', value: _formatFullTimestamp(startedAt)),
              if (finishedAt != null) _DetailRow(label: 'Finished', value: _formatFullTimestamp(finishedAt)),
            ],
          ),
        ],
      ),
    );
  }

  int _determineStage(String status, int discovered, int candidates, int fetched, int upserted) {
    if (status == 'failed' || status == 'error') return -1; // Error state
    if (status == 'completed' || status == 'success' || status == 'succeeded') return 4; // Complete
    
    if (upserted > 0) return 3; // Saving
    if (fetched > 0) return 2; // Crawling
    if (discovered > 0 || candidates > 0) return 1; // Discovery done
    return 0; // Starting
  }

  String _calculateElapsed(DateTime? start, DateTime? finish) {
    if (start == null) return '--';
    final end = finish ?? DateTime.now();
    final diff = end.difference(start);
    if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ${diff.inSeconds % 60}s';
    }
    return '${diff.inSeconds}s';
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

/// Status badge with pulsing animation for running state
class _StatusBadge extends StatefulWidget {
  const _StatusBadge({
    required this.status,
    required this.isRunning,
    required this.elapsed,
  });

  final String status;
  final bool isRunning;
  final String elapsed;

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isRunning) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRunning && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = widget.status == 'completed' || widget.status == 'success' || widget.status == 'succeeded';
    final isError = widget.status == 'failed' || widget.status == 'error';
    final isStopped = widget.status == 'stopped';
    
    final statusColor = widget.isRunning
        ? AppTheme.primaryAction
        : isSuccess
            ? AppTheme.positiveLike
            : isError
                ? AppTheme.negativeDislike
                : isStopped
                    ? Colors.orange
                    : AppTheme.textCaption;

    final statusText = widget.isRunning
        ? 'Running'
        : isSuccess
            ? 'Completed'
            : isError
                ? 'Failed'
                : isStopped
                    ? 'Stopped'
                    : widget.status.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingUnit),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Status indicator
          widget.isRunning
              ? AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) => Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.5 + _pulseController.value * 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                )
              : Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: isSuccess
                      ? const Icon(Icons.check, size: 10, color: Colors.white)
                      : isError
                          ? const Icon(Icons.close, size: 10, color: Colors.white)
                          : null,
                ),
          const SizedBox(width: 12),
          // Status text
          Text(
            statusText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Elapsed time
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                widget.elapsed,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal stepper showing ingestion stages
class _StageStepper extends StatelessWidget {
  const _StageStepper({required this.currentStage, this.isError = false});

  final int currentStage; // 0=Starting, 1=Discovery, 2=Crawling, 3=Saving, 4=Complete, -1=Error
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('Starting', Icons.play_arrow),
      ('Discovery', Icons.search),
      ('Crawling', Icons.download),
      ('Saving', Icons.save),
      ('Complete', Icons.check_circle),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingUnit),
      child: Row(
        children: List.generate(stages.length * 2 - 1, (index) {
          // Odd indices are connectors
          if (index.isOdd) {
            final prevStageIndex = index ~/ 2;
            final isActive = currentStage > prevStageIndex && !isError;
            return Expanded(
              child: Container(
                height: 2,
                color: isActive ? AppTheme.primaryAction : AppTheme.textCaption.withValues(alpha: 0.3),
              ),
            );
          }
          
          // Even indices are stage circles
          final stageIndex = index ~/ 2;
          final (label, icon) = stages[stageIndex];
          final isActive = currentStage >= stageIndex && !isError;
          final isCurrent = currentStage == stageIndex;
          final isErrorStage = isError && (currentStage == -1 || stageIndex <= currentStage);
          
          return _StageCircle(
            label: label,
            icon: icon,
            isActive: isActive,
            isCurrent: isCurrent,
            isError: isErrorStage && stageIndex == (currentStage == -1 ? 0 : currentStage),
          );
        }),
      ),
    );
  }
}

class _StageCircle extends StatelessWidget {
  const _StageCircle({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isCurrent,
    this.isError = false,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final bool isCurrent;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? AppTheme.negativeDislike
        : isActive
            ? AppTheme.primaryAction
            : AppTheme.textCaption.withValues(alpha: 0.4);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isCurrent ? 36 : 28,
          height: isCurrent ? 36 : 28,
          decoration: BoxDecoration(
            color: isActive ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(isCurrent ? 18 : 14),
            border: Border.all(color: color, width: isCurrent ? 3 : 2),
          ),
          child: Icon(
            isError ? Icons.error : icon,
            size: isCurrent ? 18 : 14,
            color: isActive ? Colors.white : color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isActive ? (isError ? AppTheme.negativeDislike : AppTheme.textPrimary) : AppTheme.textCaption,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

/// Progress statistics panel
class _ProgressStats extends StatelessWidget {
  const _ProgressStats({
    required this.urlsDiscovered,
    required this.urlsCandidates,
    required this.fetched,
    required this.success,
    required this.failed,
    required this.upserted,
    required this.isRunning,
  });

  final int urlsDiscovered;
  final int urlsCandidates;
  final int fetched;
  final int success;
  final int failed;
  final int upserted;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final total = urlsCandidates > 0 ? urlsCandidates : urlsDiscovered;
    final progress = total > 0 ? (fetched / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingUnit),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.textCaption.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          // Progress bar
          if (isRunning && total > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppTheme.textCaption.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation(AppTheme.primaryAction),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.primaryAction,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit),
          ],
          // Stats grid
          Row(
            children: [
              _ProgressStat(label: 'Discovered', value: urlsDiscovered, icon: Icons.radar),
              _ProgressStat(label: 'Candidates', value: urlsCandidates, icon: Icons.filter_list),
              _ProgressStat(label: 'Crawled', value: fetched, icon: Icons.download),
            ],
          ),
          const SizedBox(height: AppTheme.spacingUnit / 2),
          Row(
            children: [
              _ProgressStat(label: 'Success', value: success, icon: Icons.check_circle_outline, color: AppTheme.positiveLike),
              _ProgressStat(label: 'Failed', value: failed, icon: Icons.error_outline, color: failed > 0 ? AppTheme.negativeDislike : null),
              _ProgressStat(label: 'Saved', value: upserted, icon: Icons.save_alt, color: AppTheme.positiveLike, highlight: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  const _ProgressStat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.highlight = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color? color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.textSecondary;
    
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: highlight
            ? BoxDecoration(
                color: AppTheme.positiveLike.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              )
            : null,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: effectiveColor),
                const SizedBox(width: 4),
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: effectiveColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textCaption,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
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
