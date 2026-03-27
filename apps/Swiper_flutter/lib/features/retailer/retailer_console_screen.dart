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
        _error = _humanizeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _claimRetailer() async {
    final token = _token;
    final retailerId = _claimRetailerController.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
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
        SnackBar(
            content: Text('Failed to claim retailer: ${_humanizeError(e)}')),
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
        onOpenCampaigns: () => setState(() => _tabIndex = 1),
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
      _RetailerTrendsTab(
        key: ValueKey('trends_$_reloadKey'),
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
          BottomNavigationBarItem(
              icon: Icon(Icons.trending_up_outlined), label: 'Trends'),
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
    required this.onOpenCampaigns,
  });

  final String token;
  final String retailerId;
  final VoidCallback onOpenCampaigns;

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
          return _InlineErrorCard(
            title: 'Failed to load dashboard',
            message: _humanizeError(snapshot.error),
          );
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
            _SectionHeader(
              title: 'Performance overview',
              subtitle:
                  'Track spend, delivery, and outcomes at a glance. Use campaigns for control and catalog for guardrails.',
              action: TextButton.icon(
                onPressed: onOpenCampaigns,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Open campaigns'),
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit * 0.75),
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
            const SizedBox(height: AppTheme.spacingUnit),
            if (activeCampaigns == 0)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No active campaign yet',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create and activate your first campaign to start collecting delivery and outcome data.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: onOpenCampaigns,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Create first campaign'),
                      ),
                    ],
                  ),
                ),
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
                  title: Text(card['headline']?.toString() ?? 'Insight'),
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
  bool _actionInFlight = false;
  String _statusFilter = 'all';

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

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _actionInFlight = false);
      }
    }
  }

  Future<void> _createStarterSegment() async {
    await _runAction(() async {
      try {
        final nowIso = DateTime.now().toIso8601String().substring(0, 10);
        await ref.read(apiClientProvider).retailerCreateSegment(
              token: widget.token,
              retailerId: widget.retailerId,
              name: 'Starter segment $nowIso',
              description:
                  'Broad starter segment for first campaign launch and baseline learning.',
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Starter segment created')),
        );
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to create segment: ${_humanizeError(e)}')),
        );
      }
    });
  }

  Future<void> _openCreateCampaignSheet(
      List<Map<String, dynamic>> segments) async {
    if (segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No segments available. Create a starter segment first.'),
        ),
      );
      return;
    }
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CampaignComposerSheet(
        retailerId: widget.retailerId,
        segments: segments,
      ),
    );
    if (payload == null) return;
    await _runAction(() async {
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
          SnackBar(
              content: Text('Failed to create campaign: ${_humanizeError(e)}')),
        );
      }
    });
  }

  Future<void> _activateCampaign(String campaignId) async {
    await _runAction(() async {
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
          SnackBar(
              content:
                  Text('Failed to activate campaign: ${_humanizeError(e)}')),
        );
      }
    });
  }

  Future<void> _pauseCampaign(String campaignId) async {
    await _runAction(() async {
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
          SnackBar(
              content: Text('Failed to pause campaign: ${_humanizeError(e)}')),
        );
      }
    });
  }

  Future<void> _recommendCampaign(String campaignId) async {
    await _runAction(() async {
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
          SnackBar(
              content: Text(
                  'Failed to refresh recommendations: ${_humanizeError(e)}')),
        );
      }
    });
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
          return _InlineErrorCard(
            title: 'Failed to load campaigns',
            message: _humanizeError(snapshot.error),
            actionLabel: 'Retry',
            onAction: _refresh,
          );
        }
        final campaigns =
            snapshot.data?[0] as List<Map<String, dynamic>>? ?? const [];
        final segments =
            snapshot.data?[1] as List<Map<String, dynamic>>? ?? const [];
        final visibleCampaigns = _statusFilter == 'all'
            ? campaigns
            : campaigns
                .where((entry) =>
                    (entry['status']?.toString() ?? '') == _statusFilter)
                .toList();

        return ListView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          children: [
            _SectionHeader(
              title: 'Campaign Builder',
              subtitle:
                  'Create objective-driven campaigns, activate/pause quickly, and refresh recommendations.',
              action: ElevatedButton.icon(
                onPressed: _actionInFlight
                    ? null
                    : () => _openCreateCampaignSheet(segments),
                icon: _actionInFlight
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('New campaign'),
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in const ['all', 'active', 'draft', 'paused'])
                  ChoiceChip(
                    label: Text(filter == 'all' ? 'All' : filter),
                    selected: _statusFilter == filter,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _statusFilter = filter);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit * 0.75),
            if (segments.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.segment_outlined),
                  title: const Text('No segments configured'),
                  subtitle: const Text(
                    'Campaigns require at least one segment. Create a starter segment to begin.',
                  ),
                  trailing: TextButton(
                    onPressed: _actionInFlight ? null : _createStarterSegment,
                    child: const Text('Create starter'),
                  ),
                ),
              ),
            if (campaigns.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppTheme.spacingUnit),
                  child: Text(
                    'No campaigns yet. Create your first featured campaign.',
                  ),
                ),
              ),
            ...visibleCampaigns.map((campaign) {
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
                              onPressed: _actionInFlight || campaignId.isEmpty
                                  ? null
                                  : () => _activateCampaign(campaignId),
                              child: const Text('Activate'),
                            ),
                          if (status == 'active')
                            OutlinedButton(
                              onPressed: _actionInFlight || campaignId.isEmpty
                                  ? null
                                  : () => _pauseCampaign(campaignId),
                              child: const Text('Pause'),
                            ),
                          OutlinedButton(
                            onPressed: _actionInFlight || campaignId.isEmpty
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
  final TextEditingController _searchController = TextEditingController();
  String _inclusionFilter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        SnackBar(
            content: Text('Failed to update product: ${_humanizeError(e)}')),
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
          return _InlineErrorCard(
            title: 'Failed to load catalog',
            message: _humanizeError(snapshot.error),
            actionLabel: 'Retry',
            onAction: _refresh,
          );
        }
        final data = snapshot.data ?? {};
        final products = data['products'] as List? ?? const [];
        final query = _searchController.text.trim().toLowerCase();
        final filteredProducts = products.where((entry) {
          final row = entry is Map
              ? entry.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          final title = row['title']?.toString().toLowerCase() ?? '';
          final included = row['included'] != false;
          final queryMatch = query.isEmpty || title.contains(query);
          final inclusionMatch = _inclusionFilter == 'all' ||
              (_inclusionFilter == 'included' && included) ||
              (_inclusionFilter == 'excluded' && !included);
          return queryMatch && inclusionMatch;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          children: [
            _SectionHeader(
              title: 'Catalog Control',
              subtitle:
                  'Decide which products are eligible for campaigns and monitor taxonomy + creative health.',
              action: TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search products',
                hintText: 'Type product name',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in const ['all', 'included', 'excluded'])
                  ChoiceChip(
                    label: Text(filter[0].toUpperCase() + filter.substring(1)),
                    selected: _inclusionFilter == filter,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _inclusionFilter = filter);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Showing ${filteredProducts.length} of ${products.length} products',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...filteredProducts.map((entry) {
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
              final roomTypes = (row['roomTypes'] as List? ?? const [])
                  .map((entry) => entry.toString())
                  .where((entry) => entry.isNotEmpty)
                  .toList();
              final taxonomyLabels = <String>[
                if ((row['primaryCategory']?.toString() ?? '').isNotEmpty)
                  'Category: ${row['primaryCategory']}',
                if ((row['sofaTypeShape']?.toString() ?? '').isNotEmpty)
                  'Shape: ${row['sofaTypeShape']}',
                if ((row['sofaFunction']?.toString() ?? '').isNotEmpty)
                  'Function: ${row['sofaFunction']}',
                if ((row['seatCountBucket']?.toString() ?? '').isNotEmpty)
                  'Seats: ${row['seatCountBucket']}',
                if ((row['environment']?.toString() ?? '').isNotEmpty)
                  'Environment: ${row['environment']}',
                if ((row['subCategory']?.toString() ?? '').isNotEmpty)
                  'Legacy subcat: ${row['subCategory']}',
                ...roomTypes.map((room) => 'Room: $room'),
              ];
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
                      if (taxonomyLabels.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: taxonomyLabels
                              .map(
                                (label) => Chip(
                                  label: Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                            color: AppTheme.textSecondary),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                              .toList(),
                        ),
                      ],
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

enum _PriorityFilter { all, highOnly, highAndMedium }

class _RetailerInsightsTab extends ConsumerStatefulWidget {
  const _RetailerInsightsTab({
    super.key,
    required this.token,
    required this.retailerId,
  });

  final String token;
  final String retailerId;

  @override
  ConsumerState<_RetailerInsightsTab> createState() =>
      _RetailerInsightsTabState();
}

class _RetailerInsightsTabState extends ConsumerState<_RetailerInsightsTab> {
  late Future<Map<String, dynamic>> _future;
  _PriorityFilter _filter = _PriorityFilter.all;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    return ref
        .read(apiClientProvider)
        .retailerGetInsights(token: widget.token, retailerId: widget.retailerId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Color _colorForPriority(String? priority) {
    switch (priority?.toString().toLowerCase()) {
      case 'high':
        return Colors.red[600]!;
      case 'medium':
        return Colors.amber;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _navigateToAction(BuildContext context, Map<String, dynamic> entry) {
    final action = entry['action'] as Map<String, dynamic>?;
    if (action == null) return;
    final url = action['url']?.toString();
    if (url == null || url.isEmpty) return;

    // Handle internal retailer console navigation
    // e.g. /retailer/campaigns/${id} or /retailer/products?filter=...
    if (url.startsWith('/retailer')) {
      // Parse the path and switch tabs accordingly
      final uri = Uri.parse(url);
      final path = uri.path;

      if (path.startsWith('/retailer/campaigns/')) {
        // Navigate to campaigns tab and potentially open a specific campaign
        // For now just show a snackbar - full deep linking would need more work
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Campaign: ${action['label'] ?? 'View'}')),
        );
      } else if (path.contains('products')) {
        // Navigate to catalog tab
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Catalog: ${action['label'] ?? 'Review products'}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(action['label'] ?? 'Open')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Priority filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingUnit,
            AppTheme.spacingUnit,
            AppTheme.spacingUnit,
            0,
          ),
          child: Row(
            children: [
              Text(
                'Filter:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All'),
                selected: _filter == _PriorityFilter.all,
                onSelected: (_) => setState(() => _filter = _PriorityFilter.all),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('High only'),
                selected: _filter == _PriorityFilter.highOnly,
                onSelected: (_) =>
                    setState(() => _filter = _PriorityFilter.highOnly),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('High + Medium'),
                selected: _filter == _PriorityFilter.highAndMedium,
                onSelected: (_) =>
                    setState(() => _filter = _PriorityFilter.highAndMedium),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _InlineErrorCard(
                  title: 'Failed to load insights',
                  message: _humanizeError(snapshot.error),
                  actionLabel: 'Retry',
                  onAction: _refresh,
                );
              }
              final insights =
                  (snapshot.data?['insights'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
              if (insights.isEmpty) {
                return const _InlineErrorCard(
                  title: 'No insights yet',
                  message:
                      'Insights appear after campaigns start serving impressions.',
                );
              }

              final filtered = insights.where((entry) {
                final priority = entry['priority']?.toString().toLowerCase();
                switch (_filter) {
                  case _PriorityFilter.highOnly:
                    return priority == 'high';
                  case _PriorityFilter.highAndMedium:
                    return priority == 'high' || priority == 'medium';
                  case _PriorityFilter.all:
                    return true;
                }
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    'No insights match the current filter.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return _InsightCard(
                      entry: entry,
                      color: _colorForPriority(entry['priority']),
                      onAction: () => _navigateToAction(context, entry),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.entry,
    required this.color,
    this.onAction,
  });

  final Map<String, dynamic> entry;
  final Color color;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final priority = entry['priority']?.toString().toUpperCase() ?? '';
    final headline = entry['headline']?.toString() ?? 'Insight';
    final body = entry['body']?.toString() ?? '';
    final metricRaw = entry['metric'] as Map<String, dynamic>?;
    final actionRaw = entry['action'] as Map<String, dynamic>?;
    final actionLabel = actionRaw?['label']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Priority badge + headline
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      priority,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      headline,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 0),
                  child: Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // Metric + action button row
              Row(
                children: [
                  if (metricRaw != null) ...[
                    _MetricBadge(
                      label: metricRaw['label']?.toString() ?? '',
                      value: metricRaw['value']?.toString() ?? '',
                      unit: metricRaw['unit']?.toString() ?? '',
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Spacer(),
                  if (actionLabel != null && actionLabel.isNotEmpty)
                    FilledButton.tonal(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: Text(actionLabel),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Text(
        '$label $value$unit',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
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
        SnackBar(content: Text('Failed to export CSV: ${_humanizeError(e)}')),
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
        SnackBar(
            content: Text('Failed to create share link: ${_humanizeError(e)}')),
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
          return _InlineErrorCard(
            title: 'Failed to load report',
            message: _humanizeError(snapshot.error),
          );
        }
        final report = snapshot.data ?? {};
        final byCampaign = report['byCampaign'] as List? ?? const [];
        final bySegment = report['bySegment'] as List? ?? const [];

        return ListView(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          children: [
            _SectionHeader(
              title: 'Reporting',
              subtitle:
                  'Export CSV for analysts, share links with stakeholders, and track campaign contribution by segment.',
              action: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _exportCsv(context, ref),
                    child: const Text('Export CSV'),
                  ),
                  OutlinedButton(
                    onPressed: () => _shareReport(context, ref),
                    child: const Text('Share'),
                  ),
                ],
              ),
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

class _RetailerTrendsTab extends ConsumerStatefulWidget {
  const _RetailerTrendsTab({
    super.key,
    required this.token,
    required this.retailerId,
  });

  final String token;
  final String retailerId;

  @override
  ConsumerState<_RetailerTrendsTab> createState() => _RetailerTrendsTabState();
}

class _RetailerTrendsTabState extends ConsumerState<_RetailerTrendsTab> {
  // Mock geographic hierarchy data for Sweden
  static final Map<String, dynamic> _mockTrendsData = {
    'country': 'Sweden',
    'productCount': 847,
    'totalImpressions': 1245893,
    'ctr': 0.0342,
    'cpScore': 2.41,
    'priority': 'medium',
    'regions': [
      {
        'name': 'Stockholm',
        'productCount': 312,
        'totalImpressions': 456789,
        'ctr': 0.0387,
        'cpScore': 2.68,
        'priority': 'high',
        'cities': [
          {
            'name': 'Stockholm City',
            'productCount': 198,
            'totalImpressions': 289456,
            'ctr': 0.0412,
            'cpScore': 2.89,
            'priority': 'high',
            'postcodes': [
              {'code': '111 22', 'productCount': 45, 'totalImpressions': 67890, 'ctr': 0.0431, 'cpScore': 3.01, 'priority': 'high'},
              {'code': '111 35', 'productCount': 52, 'totalImpressions': 72156, 'ctr': 0.0398, 'cpScore': 2.76, 'priority': 'medium'},
              {'code': '114 79', 'productCount': 41, 'totalImpressions': 58900, 'ctr': 0.0387, 'cpScore': 2.65, 'priority': 'medium'},
              {'code': '117 65', 'productCount': 60, 'totalImpressions': 90510, 'ctr': 0.0423, 'cpScore': 3.14, 'priority': 'high'},
            ],
          },
          {
            'name': 'Södertälje',
            'productCount': 68,
            'totalImpressions': 98765,
            'ctr': 0.0354,
            'cpScore': 2.41,
            'priority': 'medium',
            'postcodes': [
              {'code': '152 42', 'productCount': 34, 'totalImpressions': 45678, 'ctr': 0.0341, 'cpScore': 2.28, 'priority': 'medium'},
              {'code': '153 31', 'productCount': 34, 'totalImpressions': 53087, 'ctr': 0.0367, 'cpScore': 2.54, 'priority': 'medium'},
            ],
          },
          {
            'name': 'Tumba',
            'productCount': 46,
            'totalImpressions': 68568,
            'ctr': 0.0331,
            'cpScore': 2.23,
            'priority': 'low',
            'postcodes': [
              {'code': '147 34', 'productCount': 46, 'totalImpressions': 68568, 'ctr': 0.0331, 'cpScore': 2.23, 'priority': 'low'},
            ],
          },
        ],
      },
      {
        'name': 'Västra Götaland',
        'productCount': 234,
        'totalImpressions': 367890,
        'ctr': 0.0321,
        'cpScore': 2.31,
        'priority': 'medium',
        'cities': [
          {
            'name': 'Gothenburg',
            'productCount': 189,
            'totalImpressions': 298765,
            'ctr': 0.0334,
            'cpScore': 2.38,
            'priority': 'medium',
            'postcodes': [
              {'code': '411 05', 'productCount': 67, 'totalImpressions': 89456, 'ctr': 0.0356, 'cpScore': 2.51, 'priority': 'medium'},
              {'code': '412 56', 'productCount': 58, 'totalImpressions': 78123, 'ctr': 0.0321, 'cpScore': 2.29, 'priority': 'medium'},
              {'code': '416 77', 'productCount': 64, 'totalImpressions': 131186, 'ctr': 0.0325, 'cpScore': 2.34, 'priority': 'medium'},
            ],
          },
          {
            'name': 'Mölndal',
            'productCount': 45,
            'totalImpressions': 69125,
            'ctr': 0.0312,
            'cpScore': 2.19,
            'priority': 'low',
            'postcodes': [
              {'code': '431 44', 'productCount': 45, 'totalImpressions': 69125, 'ctr': 0.0312, 'cpScore': 2.19, 'priority': 'low'},
            ],
          },
        ],
      },
      {
        'name': 'Skåne',
        'productCount': 178,
        'totalImpressions': 245123,
        'ctr': 0.0298,
        'cpScore': 2.12,
        'priority': 'low',
        'cities': [
          {
            'name': 'Malmö',
            'productCount': 112,
            'totalImpressions': 167890,
            'ctr': 0.0312,
            'cpScore': 2.21,
            'priority': 'low',
            'postcodes': [
              {'code': '211 26', 'productCount': 48, 'totalImpressions': 72340, 'ctr': 0.0324, 'cpScore': 2.29, 'priority': 'medium'},
              {'code': '213 45', 'productCount': 38, 'totalImpressions': 54321, 'ctr': 0.0298, 'cpScore': 2.11, 'priority': 'low'},
              {'code': '215 82', 'productCount': 26, 'totalImpressions': 41229, 'ctr': 0.0314, 'cpScore': 2.23, 'priority': 'low'},
            ],
          },
          {
            'name': 'Lund',
            'productCount': 66,
            'totalImpressions': 77233,
            'ctr': 0.0276,
            'cpScore': 1.98,
            'priority': 'low',
            'postcodes': [
              {'code': '223 51', 'productCount': 38, 'totalImpressions': 45123, 'ctr': 0.0281, 'cpScore': 2.01, 'priority': 'low'},
              {'code': '224 78', 'productCount': 28, 'totalImpressions': 32110, 'ctr': 0.0269, 'cpScore': 1.93, 'priority': 'low'},
            ],
          },
        ],
      },
      {
        'name': 'Uppsala',
        'productCount': 73,
        'totalImpressions': 112091,
        'ctr': 0.0312,
        'cpScore': 2.28,
        'priority': 'medium',
        'cities': [
          {
            'name': 'Uppsala',
            'productCount': 73,
            'totalImpressions': 112091,
            'ctr': 0.0312,
            'cpScore': 2.28,
            'priority': 'medium',
            'postcodes': [
              {'code': '753 20', 'productCount': 41, 'totalImpressions': 62340, 'ctr': 0.0321, 'cpScore': 2.35, 'priority': 'medium'},
              {'code': '756 45', 'productCount': 32, 'totalImpressions': 49751, 'ctr': 0.0301, 'cpScore': 2.19, 'priority': 'low'},
            ],
          },
        ],
      },
      {
        'name': 'Östergötland',
        'productCount': 50,
        'totalImpressions': 64000,
        'ctr': 0.0289,
        'cpScore': 2.05,
        'priority': 'low',
        'cities': [
          {
            'name': 'Norrköping',
            'productCount': 50,
            'totalImpressions': 64000,
            'ctr': 0.0289,
            'cpScore': 2.05,
            'priority': 'low',
            'postcodes': [
              {'code': '602 24', 'productCount': 50, 'totalImpressions': 64000, 'ctr': 0.0289, 'cpScore': 2.05, 'priority': 'low'},
            ],
          },
        ],
      },
    ],
  };

  final Set<String> _expandedNodes = {};

  Color _colorForPriority(String? priority) {
    switch (priority?.toString().toLowerCase()) {
      case 'high':
        return Colors.red[600]!;
      case 'medium':
        return Colors.amber;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _toggleNode(String nodeId) {
    setState(() {
      if (_expandedNodes.contains(nodeId)) {
        _expandedNodes.remove(nodeId);
      } else {
        _expandedNodes.add(nodeId);
      }
    });
  }

  Widget _buildPostcodeRow(Map<String, dynamic> postcode) {
    final priorityColor = _colorForPriority(postcode['priority']);
    return Container(
      margin: const EdgeInsets.only(left: 48, bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: priorityColor.withOpacity(0.4), width: 2),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: priorityColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                postcode['priority']?.toString().toUpperCase() ?? '',
                style: TextStyle(
                  color: priorityColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              postcode['code']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
        subtitle: Text(
          '${postcode['productCount']} products | ${_num(postcode['totalImpressions']).toStringAsFixed(0)} impr | CTR ${(_num(postcode['ctr']) * 100).toStringAsFixed(1)}% | CP ${_num(postcode['cpScore']).toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildCityRow(Map<String, dynamic> city, String regionId) {
    final priorityColor = _colorForPriority(city['priority']);
    final cityId = '$regionId-${city['name']}';
    final isExpanded = _expandedNodes.contains(cityId);
    final postcodes = city['postcodes'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 24, bottom: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: priorityColor.withOpacity(0.5), width: 2),
            ),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: GestureDetector(
              onTap: postcodes.isNotEmpty ? () => _toggleNode(cityId) : null,
              child: Icon(
                postcodes.isNotEmpty
                    ? (isExpanded ? Icons.expand_less : Icons.expand_more)
                    : Icons.remove,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    city['priority']?.toString().toUpperCase() ?? '',
                    style: TextStyle(
                      color: priorityColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  city['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
            subtitle: Text(
              '${city['productCount']} products | ${_num(city['totalImpressions']).toStringAsFixed(0)} impr | CTR ${(_num(city['ctr']) * 100).toStringAsFixed(1)}% | CP ${_num(city['cpScore']).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        if (isExpanded)
          ...postcodes.map((postcode) => _buildPostcodeRow(postcode as Map<String, dynamic>)),
      ],
    );
  }

  Widget _buildRegionRow(Map<String, dynamic> region) {
    final priorityColor = _colorForPriority(region['priority']);
    final regionId = region['name']?.toString() ?? '';
    final isExpanded = _expandedNodes.contains(regionId);
    final cities = region['cities'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: priorityColor, width: 3),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: GestureDetector(
              onTap: cities.isNotEmpty ? () => _toggleNode(regionId) : null,
              child: Icon(
                cities.isNotEmpty
                    ? (isExpanded ? Icons.expand_less : Icons.expand_more)
                    : Icons.remove,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    region['priority']?.toString().toUpperCase() ?? '',
                    style: TextStyle(
                      color: priorityColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  region['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            subtitle: Text(
              '${region['productCount']} products | ${_num(region['totalImpressions']).toStringAsFixed(0)} impr | CTR ${(_num(region['ctr']) * 100).toStringAsFixed(1)}% | CP ${_num(region['cpScore']).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        if (isExpanded)
          ...cities.map((city) => _buildCityRow(city as Map<String, dynamic>, regionId)),
      ],
    );
  }

  Widget _buildCountryHeader() {
    final data = _mockTrendsData;
    final priorityColor = _colorForPriority(data['priority']);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: priorityColor, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.public, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    data['country']?.toString() ?? 'Sweden',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: priorityColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      data['priority']?.toString().toUpperCase() ?? '',
                      style: TextStyle(
                        color: priorityColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _MetricBadge(
                    label: 'Products',
                    value: data['productCount'].toString(),
                    unit: '',
                  ),
                  _MetricBadge(
                    label: 'Impressions',
                    value: _num(data['totalImpressions']).toStringAsFixed(0),
                    unit: '',
                  ),
                  _MetricBadge(
                    label: 'CTR',
                    value: (_num(data['ctr']) * 100).toStringAsFixed(1),
                    unit: '%',
                  ),
                  _MetricBadge(
                    label: 'CP Score',
                    value: _num(data['cpScore']).toStringAsFixed(2),
                    unit: '',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _mockTrendsData;
    final regions = data['regions'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingUnit),
      children: [
        _SectionHeader(
          title: 'Trends by Geography',
          subtitle:
              'Product performance broken down by Swedish geographic hierarchy. Expand regions, cities, and postcodes to drill down.',
          action: IconButton(
            onPressed: () {
              setState(() {
                _expandedNodes.clear();
              });
            },
            icon: const Icon(Icons.unfold_less),
            tooltip: 'Collapse all',
          ),
        ),
        const SizedBox(height: AppTheme.spacingUnit),
        _buildCountryHeader(),
        const SizedBox(height: 4),
        ...regions.map((region) => _buildRegionRow(region as Map<String, dynamic>)),
        const SizedBox(height: AppTheme.spacingUnit),
        Card(
          color: AppTheme.surfaceVariant.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trends data is currently in development. API integration coming soon.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
              const SizedBox(height: 6),
              Text(
                'Set a segment, product mode, and budget. Start with auto mode to bootstrap quickly.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textSecondary),
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
                value: _segmentId,
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
                value: _productMode,
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
                  onPressed: widget.segments.isEmpty ? null : _submit,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          action!,
        ],
      ],
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
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
        color: color.withOpacity(0.15),
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

String _humanizeError(Object? error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    final payload = error.response?.data;
    if (payload is Map && payload['error'] != null) {
      final message = payload['error'].toString();
      return statusCode != null ? '[$statusCode] $message' : message;
    }
    if (statusCode != null) return 'Request failed with status $statusCode';
    return error.message ?? 'Network request failed';
  }
  if (error == null) return 'Unknown error';
  final text = error.toString();
  if (text.startsWith('DioException')) return 'Network request failed';
  return text;
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
