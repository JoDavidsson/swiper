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
                  Text('Error: $message', style: TextStyle(color: AppTheme.negativeDislike), textAlign: TextAlign.center),
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
        data: (stats) => ListView(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            children: [
              _StatCard(title: 'Daily sessions', value: '${stats['dailySessions'] ?? 0}'),
              _StatCard(title: 'Total swipes', value: '${stats['totalSwipes'] ?? 0}'),
              _StatCard(title: 'Total likes', value: '${stats['totalLikes'] ?? 0}'),
              _StatCard(title: 'Outbound clicks', value: '${stats['outboundClicks'] ?? 0}'),
              _StatCard(title: 'Like rate %', value: '${stats['likeRate'] ?? 0}'),
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
            ],
          ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});

  final String title;
  final String value;

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
            Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.primaryAction)),
          ],
        ),
      ),
    );
  }
}
