import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';
import '../../data/session_provider.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(adminAuthProvider.notifier).state = false;
              ref.read(adminIdTokenProvider.notifier).state = null;
              ref.read(adminPasswordProvider.notifier).state = null;
              context.go('/admin/login');
            },
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          String message = err.toString();
          if (err is DioException && err.response?.data != null) {
            final d = err.response!.data;
            if (d is Map) {
              final detail = d['detail'] ?? d['error'];
              if (detail != null) message = detail.toString();
            }
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: $message',
                    style: const TextStyle(color: AppTheme.negativeDislike),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacingUnit),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(adminStatsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        },
        data: (stats) {
          final golden = _asMap(stats['goldenV2']);
          final funnel = _asMap(golden['funnel24h']);
          final submit = _asMap(golden['submitReliability24h']);
          final submitAlert = _asMap(submit['alert']);
          final latency = _asMap(golden['deckLatency24h']);
          final latencyAlert = _asMap(latency['alert']);
          final quality = _asMap(golden['deckQuality24h']);
          final weekly = _asMap(golden['experimentWeeklyByCohort']);
          final weeklyCohorts = _asMapList(weekly['cohorts']);

          final submitAlertTriggered = submitAlert['triggered'] == true;
          final latencyAlertTriggered = latencyAlert['triggered'] == true;

          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            children: [
              _StatCard(
                  title: 'Daily sessions',
                  value: _formatValue(stats['dailySessions'])),
              _StatCard(
                  title: 'Total swipes',
                  value: _formatValue(stats['totalSwipes'])),
              _StatCard(
                  title: 'Total likes',
                  value: _formatValue(stats['totalLikes'])),
              _StatCard(
                  title: 'Outbound clicks',
                  value: _formatValue(stats['outboundClicks'])),
              _StatCard(
                title: 'Like rate %',
                value: _formatPercent(stats['likeRate']),
              ),
              const Divider(),
              const _SectionTitle('Golden Card v2 observability (24h)'),
              _StatCard(
                title: 'Funnel completion %',
                value: _formatPercent(funnel['completionRatePct']),
              ),
              _StatCard(
                title: 'Funnel skip %',
                value: _formatPercent(funnel['skipRatePct']),
              ),
              _StatCard(
                title: 'Funnel intros',
                value: _formatValue(funnel['introShown']),
              ),
              _StatCard(
                title: 'Summary confirmed',
                value: _formatValue(funnel['summaryConfirmed']),
              ),
              _StatCard(
                title: 'Submit failure %',
                value: _formatPercent(submit['failureRatePct']),
                valueColor: submitAlertTriggered
                    ? AppTheme.negativeDislike
                    : AppTheme.positiveLike,
              ),
              _StatCard(
                title: 'Deck p95 latency (ms)',
                value: _formatValue(latency['currentP95Ms']),
                valueColor: latencyAlertTriggered
                    ? AppTheme.negativeDislike
                    : AppTheme.primaryAction,
              ),
              _StatCard(
                title: 'Latency regression %',
                value: _formatPercent(latency['regressionPct']),
                valueColor: latencyAlertTriggered
                    ? AppTheme.negativeDislike
                    : AppTheme.primaryAction,
              ),
              _StatCard(
                title: 'Avg same-family top8 rate',
                value: _formatDecimal(quality['sameFamilyTop8RateAvg']),
              ),
              _StatCard(
                title: 'Avg style-distance top4 min',
                value: _formatDecimal(quality['styleDistanceTop4MinAvg']),
              ),
              _AlertCard(
                title: 'Onboarding submit failure alert',
                subtitle:
                    'Threshold: >${_formatValue(submitAlert['thresholdPct'])}% with at least ${_formatValue(submitAlert['minSamples'])} sessions',
                triggered: submitAlertTriggered,
              ),
              _AlertCard(
                title: 'Deck latency regression alert',
                subtitle:
                    'Threshold: >${_formatValue(latencyAlert['thresholdPct'])}% with at least ${_formatValue(latencyAlert['minSamples'])} samples',
                triggered: latencyAlertTriggered,
              ),
              const Divider(),
              _SectionTitle(
                  'Weekly experiment cohorts (${_formatValue(weekly['windowDays'])}d)'),
              _StatCard(
                title: 'Cohorts in sample',
                value: _formatValue(weekly['cohortCount']),
              ),
              if (weeklyCohorts.isEmpty)
                const _InfoCard(
                    'No cohort data available in the weekly sample.')
              else
                ...weeklyCohorts
                    .take(8)
                    .map((cohort) => _CohortCard(cohort: cohort)),
              const Divider(),
              ListTile(
                title: const Text('Sources'),
                subtitle: const Text('CRUD + Run now'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/sources'),
              ),
              ListTile(
                title: const Text('Runs'),
                subtitle: const Text('Ingestion run history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/runs'),
              ),
              ListTile(
                title: const Text('Items'),
                subtitle: const Text('Search, edit, toggle active'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/items'),
              ),
              ListTile(
                title: const Text('Review Lab'),
                subtitle:
                    const Text('Label products for categorization training'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/review'),
              ),
              ListTile(
                title: const Text('Import'),
                subtitle: const Text('Upload CSV'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/import'),
              ),
              ListTile(
                title: const Text('QA'),
                subtitle: const Text('Completeness checker'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/qa'),
              ),
              const Divider(),
              ListTile(
                title: const Text('Curated Onboarding Sofas'),
                subtitle: const Text('Manage gold card items'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/curated'),
              ),
              ListTile(
                title: const Text('Catalog Preview'),
                subtitle: const Text('Image quality & Creative Health'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/catalog-preview'),
              ),
            ],
          );
        },
      ),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, v) => MapEntry(key.toString(), v));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((entry) => entry.map((key, v) => MapEntry(key.toString(), v)))
        .toList();
  }
  return const <Map<String, dynamic>>[];
}

String _formatValue(dynamic value) {
  if (value == null) return '-';
  if (value is num) return value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  return value.toString();
}

String _formatDecimal(dynamic value) {
  if (value == null) return '-';
  if (value is num) return value.toStringAsFixed(2);
  return value.toString();
}

String _formatPercent(dynamic value) {
  if (value == null) return '-';
  if (value is num) return '${value.toStringAsFixed(1)}%';
  return '$value%';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    this.valueColor,
  });

  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodyLarge),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: valueColor ?? AppTheme.primaryAction,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.title,
    required this.subtitle,
    required this.triggered,
  });

  final String title;
  final String subtitle;
  final bool triggered;

  @override
  Widget build(BuildContext context) {
    final color = triggered ? AppTheme.negativeDislike : AppTheme.positiveLike;
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(
          triggered ? Icons.warning_amber_rounded : Icons.check_circle,
          color: color,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text(
          triggered ? 'TRIGGERED' : 'OK',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        child: Text(message),
      ),
    );
  }
}

class _CohortCard extends StatelessWidget {
  const _CohortCard({required this.cohort});

  final Map<String, dynamic> cohort;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cohort['cohortId']?.toString() ?? 'unknown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            Wrap(
              spacing: AppTheme.spacingUnit,
              runSpacing: AppTheme.spacingUnit,
              children: [
                _MetricChip(
                  label: 'Sessions',
                  value: _formatValue(cohort['sessionCount']),
                ),
                _MetricChip(
                  label: 'Complete %',
                  value: _formatPercent(cohort['completionRatePct']),
                ),
                _MetricChip(
                  label: 'Skip %',
                  value: _formatPercent(cohort['skipRatePct']),
                ),
                _MetricChip(
                  label: 'Swipe right %',
                  value: _formatPercent(cohort['swipeRightRatePct']),
                ),
                _MetricChip(
                  label: 'Deck responses',
                  value: _formatValue(cohort['deckResponses']),
                ),
                _MetricChip(
                  label: 'Same-family top8',
                  value: _formatDecimal(cohort['sameFamilyTop8RateAvg']),
                ),
                _MetricChip(
                  label: 'Style-distance top4 min',
                  value: _formatDecimal(cohort['styleDistanceTop4MinAvg']),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.primaryAction.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingUnit,
          vertical: AppTheme.spacingUnit * 0.75,
        ),
        child: Text(
          '$label: $value',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
