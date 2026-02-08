import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api_providers.dart';
import '../../data/auth_provider.dart';

class RetailerConsoleScreen extends ConsumerStatefulWidget {
  const RetailerConsoleScreen({super.key});

  @override
  ConsumerState<RetailerConsoleScreen> createState() =>
      _RetailerConsoleScreenState();
}

class _RetailerConsoleScreenState extends ConsumerState<RetailerConsoleScreen> {
  int _tabIndex = 0;
  bool _loading = true;
  String? _error;
  String? _token;
  Map<String, dynamic>? _retailer;
  int _reloadKey = 0;
  final TextEditingController _claimRetailerController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRetailerContext();
  }

  @override
  void dispose() {
    _claimRetailerController.dispose();
    super.dispose();
  }

  Future<void> _loadRetailerContext() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await ref.read(authProvider.notifier).getIdToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _token = null;
          _retailer = null;
          _loading = false;
        });
        return;
      }
      final client = ref.read(apiClientProvider);
      Map<String, dynamic>? retailer;
      try {
        final me = await client.retailerGetMe(token: token);
        final retailerRaw = me['retailer'];
        if (retailerRaw is Map) {
          retailer = Map<String, dynamic>.from(retailerRaw);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
      setState(() {
        _token = token;
        _retailer = retailer;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _claimRetailer() async {
    final token = _token;
    final retailerId = _claimRetailerController.text.trim();
    if (token == null || retailerId.isEmpty) return;
    try {
      await ref
          .read(apiClientProvider)
          .retailerClaim(token: token, retailerId: retailerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Retailer claimed. Reloading your console...')),
      );
      await _loadRetailerContext();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to claim retailer: $e')),
      );
    }
  }

  void _refreshAll() {
    setState(() {
      _reloadKey += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (!authState.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Retailer Console')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingUnit * 1.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront_outlined, size: 48),
                const SizedBox(height: AppTheme.spacingUnit),
                const Text(
                  'Sign in to access your retailer console.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingUnit),
                ElevatedButton(
                  onPressed: () =>
                      context.go('/auth/login', extra: '/retailer'),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Retailer Console')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Retailer Console')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingUnit * 1.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.negativeDislike),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingUnit),
                ElevatedButton(
                  onPressed: _loadRetailerContext,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_retailer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Retailer Console')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit * 1.5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_business_outlined, size: 52),
                  const SizedBox(height: AppTheme.spacingUnit),
                  const Text(
                    'No retailer is linked to your account yet.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 0.5),
                  const Text(
                    'Enter your retailer id (slug) to claim access and start building campaigns.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacingUnit),
                  TextField(
                    controller: _claimRetailerController,
                    decoration: const InputDecoration(
                      labelText: 'Retailer id',
                      hintText: 'e.g. ikea',
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingUnit),
                  ElevatedButton(
                    onPressed: _claimRetailer,
                    child: const Text('Claim retailer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final retailerId = _retailer!['id']?.toString() ?? '';
    final retailerName = _retailer!['name']?.toString() ?? retailerId;

    final tabs = [
      _RetailerHomeTab(
        key: ValueKey('home_$_reloadKey'),
        token: _token!,
        retailerId: retailerId,
      ),
      _RetailerCampaignsTab(
        key: ValueKey('campaigns_$_reloadKey'),
        token: _token!,
        retailerId: retailerId,
        onChanged: _refreshAll,
      ),
      _RetailerCatalogTab(
        key: ValueKey('catalog_$_reloadKey'),
        token: _token!,
        retailerId: retailerId,
      ),
      _RetailerInsightsTab(
        key: ValueKey('insights_$_reloadKey'),
        token: _token!,
        retailerId: retailerId,
      ),
      _RetailerReportsTab(
        key: ValueKey('reports_$_reloadKey'),
        token: _token!,
        retailerId: retailerId,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Retailer Console - $retailerName'),
        actions: [
          IconButton(
            onPressed: _loadRetailerContext,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: () async {
              await ref.read(authProvider.notifier).signOut();
              if (!context.mounted) return;
              context.go('/deck');
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: IndexedStack(index: _tabIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _tabIndex = index),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.campaign_outlined), label: 'Campaigns'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined), label: 'Catalog'),
          BottomNavigationBarItem(
              icon: Icon(Icons.insights_outlined), label: 'Insights'),
          BottomNavigationBarItem(
              icon: Icon(Icons.assessment_outlined), label: 'Reports'),
        ],
      ),
    );
  }
}

class _RetailerHomeTab extends ConsumerWidget {
  const _RetailerHomeTab({
    super.key,
    required this.token,
    required this.retailerId,
  });

  final String token;
  final String retailerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(apiClientProvider);
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        client.retailerGetReport(token: token, retailerId: retailerId),
        client.retailerGetCampaigns(token: token, retailerId: retailerId),
        client.retailerGetInsights(token: token, retailerId: retailerId),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Failed to load dashboard: ${snapshot.error}'));
        }
        final report = snapshot.data?[0] as Map<String, dynamic>? ?? {};
        final campaigns =
            snapshot.data?[1] as List<Map<String, dynamic>>? ?? const [];
        final insights = (snapshot.data?[2]
                as Map<String, dynamic>?)?['insights'] as List? ??
            const [];

        final spend = _num(report['spend']);
        final featuredImpressions = _num(report['featuredImpressions']);
        final outcomes = _num(report['confidenceOutcomes']);
        final cpScore = _num(report['cpScore']);
        final activeCampaigns = campaigns
            .where((entry) => (entry['status']?.toString() ?? '') == 'active')
            .length;

        return ListView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          children: [
            Wrap(
              spacing: AppTheme.spacingUnit,
              runSpacing: AppTheme.spacingUnit,
              children: [
                _MetricCard(
                  label: 'Spend',
                  value: '${spend.toStringAsFixed(0)} SEK',
                ),
                _MetricCard(
                  label: 'Featured impressions',
                  value: featuredImpressions.toStringAsFixed(0),
                ),
                _MetricCard(
                  label: 'Confidence outcomes',
                  value: outcomes.toStringAsFixed(0),
                ),
                _MetricCard(
                  label: 'CPScore',
                  value: cpScore.toStringAsFixed(2),
                ),
                _MetricCard(
                  label: 'Active campaigns',
                  value: '$activeCampaigns',
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit * 1.5),
            Text(
              'Top insights',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.spacingUnit * 0.5),
            ...insights.take(3).map((entry) {
              final card = entry is Map
                  ? entry.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};
              return Card(
                child: ListTile(
                  title: Text(card['title']?.toString() ?? 'Insight'),
                  subtitle: Text(card['body']?.toString() ?? ''),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _RetailerCampaignsTab extends ConsumerStatefulWidget {
  const _RetailerCampaignsTab({
    super.key,
    required this.token,
    required this.retailerId,
    required this.onChanged,
  });

  final String token;
  final String retailerId;
  final VoidCallback onChanged;

  @override
  ConsumerState<_RetailerCampaignsTab> createState() =>
      _RetailerCampaignsTabState();
}

class _RetailerCampaignsTabState extends ConsumerState<_RetailerCampaignsTab> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() {
    final client = ref.read(apiClientProvider);
    return Future.wait([
      client.retailerGetCampaigns(
        token: widget.token,
        retailerId: widget.retailerId,
        limit: 100,
      ),
      client.retailerGetSegments(
        token: widget.token,
        retailerId: widget.retailerId,
        includeTemplates: true,
      ),
    ]);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openCreateCampaignSheet(
      List<Map<String, dynamic>> segments) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CampaignComposerSheet(
        retailerId: widget.retailerId,
        segments: segments,
      ),
    );
    if (payload == null) return;
    try {
      await ref.read(apiClientProvider).retailerCreateCampaign(
            token: widget.token,
            body: payload,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaign created')),
      );
      await _refresh();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create campaign: $e')),
      );
    }
  }

  Future<void> _activateCampaign(String campaignId) async {
    try {
      await ref.read(apiClientProvider).retailerActivateCampaign(
            token: widget.token,
            campaignId: campaignId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaign activated')),
      );
      await _refresh();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to activate campaign: $e')),
      );
    }
  }

  Future<void> _pauseCampaign(String campaignId) async {
    try {
      await ref.read(apiClientProvider).retailerPauseCampaign(
            token: widget.token,
            campaignId: campaignId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaign paused')),
      );
      await _refresh();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pause campaign: $e')),
      );
    }
  }

  Future<void> _recommendCampaign(String campaignId) async {
    try {
      await ref.read(apiClientProvider).retailerRecommendCampaign(
            token: widget.token,
            campaignId: campaignId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recommendations refreshed')),
      );
      await _refresh();
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to refresh recommendations: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Failed to load campaigns: ${snapshot.error}'));
        }
        final campaigns =
            snapshot.data?[0] as List<Map<String, dynamic>>? ?? const [];
        final segments =
            snapshot.data?[1] as List<Map<String, dynamic>>? ?? const [];

        return ListView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Campaign Builder',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _openCreateCampaignSheet(segments),
                  icon: const Icon(Icons.add),
                  label: const Text('New campaign'),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            if (campaigns.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppTheme.spacingUnit),
                  child: Text(
                    'No campaigns yet. Create your first featured campaign.',
                  ),
                ),
              ),
            ...campaigns.map((campaign) {
              final campaignId = campaign['id']?.toString() ?? '';
              final status = campaign['status']?.toString() ?? 'unknown';
              final budgetTotal = _num(campaign['budgetTotal']);
              final budgetSpent = _num(campaign['budgetSpent']);
              final productMode = campaign['productMode']?.toString() ?? 'all';
              final recommendedCount =
                  (campaign['recommendedProductIds'] as List?)?.length ?? 0;
              final featuredImpressions = _num(campaign['featuredImpressions']);
              return Card(
                margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              campaign['name']?.toString() ??
                                  'Untitled campaign',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          _StatusChip(status: status),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingUnit * 0.5),
                      Text(
                        'Segment: ${campaign['segmentId'] ?? '-'} | Mode: $productMode',
                      ),
                      Text(
                        'Budget: ${budgetSpent.toStringAsFixed(0)} / ${budgetTotal.toStringAsFixed(0)} SEK',
                      ),
                      Text(
                        'Featured impressions: ${featuredImpressions.toStringAsFixed(0)}',
                      ),
                      if (productMode == 'auto')
                        Text('Recommended products: $recommendedCount'),
                      const SizedBox(height: AppTheme.spacingUnit * 0.5),
                      Wrap(
                        spacing: AppTheme.spacingUnit * 0.5,
                        children: [
                          if (status == 'draft' || status == 'paused')
                            OutlinedButton(
                              onPressed: campaignId.isEmpty
                                  ? null
                                  : () => _activateCampaign(campaignId),
                              child: const Text('Activate'),
                            ),
                          if (status == 'active')
                            OutlinedButton(
                              onPressed: campaignId.isEmpty
                                  ? null
                                  : () => _pauseCampaign(campaignId),
                              child: const Text('Pause'),
                            ),
                          OutlinedButton(
                            onPressed: campaignId.isEmpty
                                ? null
                                : () => _recommendCampaign(campaignId),
                            child: const Text('Refresh recommendations'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _RetailerCatalogTab extends ConsumerStatefulWidget {
  const _RetailerCatalogTab({
    super.key,
    required this.token,
    required this.retailerId,
  });

  final String token;
  final String retailerId;

  @override
  ConsumerState<_RetailerCatalogTab> createState() =>
      _RetailerCatalogTabState();
}

class _RetailerCatalogTabState extends ConsumerState<_RetailerCatalogTab> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    return ref.read(apiClientProvider).retailerGetCatalog(
          token: widget.token,
          retailerId: widget.retailerId,
          limit: 120,
        );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _toggleInclusion(
      String productId, bool included, String title) async {
    try {
      await ref.read(apiClientProvider).retailerUpdateCatalogProduct(
            token: widget.token,
            retailerId: widget.retailerId,
            productId: productId,
            included: included,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              included ? '$title included in campaigns' : '$title excluded'),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update product: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Failed to load catalog: ${snapshot.error}'));
        }
        final data = snapshot.data ?? {};
        final products = data['products'] as List? ?? const [];

        return ListView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          children: [
            Text(
              'Catalog Control',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.spacingUnit * 0.5),
            const Text(
              'Use include/exclude to control which products can appear in featured campaigns.',
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            ...products.map((entry) {
              final row = entry is Map
                  ? entry.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};
              final productId = row['id']?.toString() ?? '';
              final title = row['title']?.toString() ?? 'Untitled';
              final included = row['included'] != false;
              final score = row['score'] is Map
                  ? Map<String, dynamic>.from(row['score'] as Map)
                  : null;
              final creativeHealth = row['creativeHealth'] is Map
                  ? Map<String, dynamic>.from(row['creativeHealth'] as Map)
                  : null;
              final issues = (creativeHealth?['issues'] as List? ?? const [])
                  .map((e) => e.toString())
                  .toList();
              return Card(
                margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
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
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Switch(
                            value: included,
                            onChanged: productId.isEmpty
                                ? null
                                : (value) =>
                                    _toggleInclusion(productId, value, title),
                          ),
                        ],
                      ),
                      Text(
                        'Price: ${_num(row['priceAmount']).toStringAsFixed(0)} ${row['priceCurrency'] ?? 'SEK'}',
                      ),
                      if (score != null)
                        Text(
                          'Score: ${_num(score['value']).toStringAsFixed(1)} (${score['band'] ?? '-'})',
                        ),
                      if (creativeHealth != null)
                        Text(
                          'Creative health: ${creativeHealth['band'] ?? '-'} (${_num(creativeHealth['score']).toStringAsFixed(0)})',
                          style: TextStyle(
                            color: (creativeHealth['band'] == 'red')
                                ? AppTheme.negativeDislike
                                : AppTheme.textSecondary,
                          ),
                        ),
                      if (issues.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Warnings: ${issues.join(', ')}',
                            style: const TextStyle(
                              color: AppTheme.warning,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _RetailerInsightsTab extends ConsumerWidget {
  const _RetailerInsightsTab({
    super.key,
    required this.token,
    required this.retailerId,
  });

  final String token;
  final String retailerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref
          .read(apiClientProvider)
          .retailerGetInsights(token: token, retailerId: retailerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Failed to load insights: ${snapshot.error}'));
        }
        final insights = snapshot.data?['insights'] as List? ?? const [];
        if (insights.isEmpty) {
          return const Center(child: Text('No insights available yet.'));
        }
        return ListView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          children: insights.map((entry) {
            final card = entry is Map
                ? entry.map((k, v) => MapEntry(k.toString(), v))
                : <String, dynamic>{};
            final type = card['type']?.toString() ?? 'insight';
            final severity = card['severity']?.toString() ?? 'neutral';
            final color = severity == 'positive'
                ? AppTheme.positiveLike
                : severity == 'warning'
                    ? AppTheme.warning
                    : AppTheme.primaryAction;
            return Card(
              margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  foregroundColor: color,
                  child: Icon(_iconForInsightType(type)),
                ),
                title: Text(card['title']?.toString() ?? 'Insight'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(card['body']?.toString() ?? ''),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _RetailerReportsTab extends ConsumerWidget {
  const _RetailerReportsTab({
    super.key,
    required this.token,
    required this.retailerId,
  });

  final String token;
  final String retailerId;

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final csv = await ref.read(apiClientProvider).retailerExportReportCsv(
            token: token,
            retailerId: retailerId,
          );
      await Clipboard.setData(ClipboardData(text: csv));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copied to clipboard')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export CSV: $e')),
      );
    }
  }

  Future<void> _shareReport(BuildContext context, WidgetRef ref) async {
    try {
      final payload = await ref.read(apiClientProvider).retailerShareReport(
            token: token,
            retailerId: retailerId,
          );
      final shareUrl = payload['shareUrl']?.toString() ??
          payload['sharePath']?.toString() ??
          '';
      if (shareUrl.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: shareUrl));
      }
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Share report link'),
          content: Text(shareUrl.isEmpty
              ? 'Share link created.'
              : 'Copied to clipboard:\n$shareUrl'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create share link: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref
          .read(apiClientProvider)
          .retailerGetReport(token: token, retailerId: retailerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Failed to load report: ${snapshot.error}'));
        }
        final report = snapshot.data ?? {};
        final byCampaign = report['byCampaign'] as List? ?? const [];
        final bySegment = report['bySegment'] as List? ?? const [];

        return ListView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reporting',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _exportCsv(context, ref),
                  child: const Text('Export CSV'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _shareReport(context, ref),
                  child: const Text('Share'),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            Wrap(
              spacing: AppTheme.spacingUnit,
              runSpacing: AppTheme.spacingUnit,
              children: [
                _MetricCard(
                  label: 'Spend',
                  value: '${_num(report['spend']).toStringAsFixed(0)} SEK',
                ),
                _MetricCard(
                  label: 'Impressions',
                  value: _num(report['impressions']).toStringAsFixed(0),
                ),
                _MetricCard(
                  label: 'Featured impressions',
                  value: _num(report['featuredImpressions']).toStringAsFixed(0),
                ),
                _MetricCard(
                  label: 'Confidence outcomes',
                  value: _num(report['confidenceOutcomes']).toStringAsFixed(0),
                ),
                _MetricCard(
                  label: 'CPScore',
                  value: _num(report['cpScore']).toStringAsFixed(2),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit * 1.5),
            Text(
              'By segment',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            ...bySegment.map((entry) {
              final row = entry is Map
                  ? entry.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};
              return ListTile(
                dense: true,
                title: Text(row['segmentId']?.toString() ?? '-'),
                subtitle: Text(
                  'Impressions ${_num(row['impressions']).toStringAsFixed(0)} | Outcomes ${_num(row['outcomes']).toStringAsFixed(0)}',
                ),
                trailing: Text('CP ${_num(row['cpScore']).toStringAsFixed(2)}'),
              );
            }),
            const Divider(),
            Text(
              'By campaign',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            ...byCampaign.map((entry) {
              final row = entry is Map
                  ? entry.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(row['name']?.toString() ?? 'Campaign'),
                  subtitle: Text(
                    'Spend ${_num(row['spend']).toStringAsFixed(0)} SEK | Featured ${_num(row['featuredImpressions']).toStringAsFixed(0)}',
                  ),
                  trailing:
                      Text('CP ${_num(row['cpScore']).toStringAsFixed(2)}'),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _CampaignComposerSheet extends StatefulWidget {
  const _CampaignComposerSheet({
    required this.retailerId,
    required this.segments,
  });

  final String retailerId;
  final List<Map<String, dynamic>> segments;

  @override
  State<_CampaignComposerSheet> createState() => _CampaignComposerSheetState();
}

class _CampaignComposerSheetState extends State<_CampaignComposerSheet> {
  final _nameController = TextEditingController();
  final _budgetTotalController = TextEditingController();
  final _budgetDailyController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _frequencyCapController = TextEditingController(text: '12');
  final _productIdsController = TextEditingController();

  String _productMode = 'auto';
  String? _segmentId;

  @override
  void initState() {
    super.initState();
    if (widget.segments.isNotEmpty) {
      _segmentId = widget.segments.first['id']?.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetTotalController.dispose();
    _budgetDailyController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _frequencyCapController.dispose();
    _productIdsController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final segmentId = _segmentId;
    if (name.isEmpty || segmentId == null || segmentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaign name and segment are required')),
      );
      return;
    }
    final budgetTotal = double.tryParse(_budgetTotalController.text.trim());
    final budgetDaily = double.tryParse(_budgetDailyController.text.trim());
    final frequencyCap = int.tryParse(_frequencyCapController.text.trim());
    final startDate = _startDateController.text.trim();
    final endDate = _endDateController.text.trim();
    final productIds = _productIdsController.text
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();

    if (_productMode == 'selected' && productIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected mode requires product ids')),
      );
      return;
    }

    Navigator.of(context).pop({
      'retailerId': widget.retailerId,
      'name': name,
      'segmentId': segmentId,
      'productMode': _productMode,
      if (_productMode == 'selected') 'productIds': productIds,
      if (budgetTotal != null) 'budgetTotal': budgetTotal,
      if (budgetDaily != null) 'budgetDaily': budgetDaily,
      if (frequencyCap != null) 'frequencyCap': frequencyCap,
      if (startDate.isNotEmpty) 'startDate': startDate,
      if (endDate.isNotEmpty) 'endDate': endDate,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create campaign',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Campaign name',
                  hintText: 'e.g. Spring Modular Push',
                ),
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              DropdownButtonFormField<String>(
                initialValue: _segmentId,
                decoration: const InputDecoration(labelText: 'Segment'),
                items: widget.segments.map((segment) {
                  final id = segment['id']?.toString() ?? '';
                  final name = segment['name']?.toString() ?? id;
                  final isTemplate = segment['isTemplate'] == true;
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(isTemplate ? '$name (template)' : name),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _segmentId = value),
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              DropdownButtonFormField<String>(
                initialValue: _productMode,
                decoration: const InputDecoration(labelText: 'Product mode'),
                items: const [
                  DropdownMenuItem(
                      value: 'auto', child: Text('Auto recommended')),
                  DropdownMenuItem(
                      value: 'selected', child: Text('Selected products')),
                  DropdownMenuItem(
                      value: 'all', child: Text('All retailer products')),
                ],
                onChanged: (value) =>
                    setState(() => _productMode = value ?? 'auto'),
              ),
              if (_productMode == 'selected') ...[
                const SizedBox(height: AppTheme.spacingUnit),
                TextField(
                  controller: _productIdsController,
                  decoration: const InputDecoration(
                    labelText: 'Product ids (comma-separated)',
                    hintText: 'prod-1,prod-2,prod-3',
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.spacingUnit),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _budgetTotalController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Total budget (SEK)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _budgetDailyController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Daily budget (SEK)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startDateController,
                      decoration: const InputDecoration(
                        labelText: 'Start date',
                        hintText: 'YYYY-MM-DD',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _endDateController,
                      decoration: const InputDecoration(
                        labelText: 'End date',
                        hintText: 'YYYY-MM-DD',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              TextField(
                controller: _frequencyCapController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Frequency cap (1 in N cards)',
                ),
              ),
              const SizedBox(height: AppTheme.spacingUnit * 1.25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Create campaign'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'active':
        color = AppTheme.positiveLike;
        break;
      case 'paused':
        color = AppTheme.warning;
        break;
      case 'draft':
        color = AppTheme.textSecondary;
        break;
      default:
        color = AppTheme.primaryAction;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

double _num(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

IconData _iconForInsightType(String type) {
  switch (type) {
    case 'winner':
      return Icons.emoji_events_outlined;
    case 'needs_help':
      return Icons.warning_amber_outlined;
    case 'trend':
      return Icons.trending_up_outlined;
    case 'anomaly':
      return Icons.analytics_outlined;
    default:
      return Icons.lightbulb_outline;
  }
}
