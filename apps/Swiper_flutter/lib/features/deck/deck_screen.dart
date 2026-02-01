import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/deck_provider.dart';
import '../../data/session_provider.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/detail_sheet.dart';
import '../../shared/widgets/filter_chip.dart' show AppFilterChip;
import '../../shared/widgets/swipe_deck.dart';

String _userFriendlyError(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    if (status == 404 || status == 502 || status == 503) {
      return 'Backend not available (${e.response?.statusCode}). '
          'Start Firebase emulators: run ./scripts/run_emulators.sh in the project root, then retry.';
    }
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach backend. Start Firebase emulators: ./scripts/run_emulators.sh';
    }
  }
  return e.toString();
}

class DeckScreen extends ConsumerWidget {
  const DeckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deckState = ref.watch(deckItemsProvider);
    final sessionId = ref.watch(sessionIdProvider);

    return AppShell(
      title: AppConstants.appName,
      showBottomNav: true,
      body: deckState.when(
        data: (items) {
          final notifier = ref.read(deckItemsProvider.notifier);
          final client = ref.read(apiClientProvider);
          return SwipeDeck(
            items: items,
            sessionId: sessionId,
            goBaseUrl: Uri.base.origin,
            onSwipeLeft: (item, position) => notifier.swipe(item.id, 'left', position),
            onSwipeRight: (item, position) => notifier.swipe(item.id, 'right', position),
            onTapDetail: sessionId != null
                ? (item) async {
                    final sid = sessionId;
                    if (!ref.read(analyticsOptOutProvider)) {
                      client.logEvent(sessionId: sid, eventType: 'open_detail', itemId: item.id).ignore();
                    }
                    final started = DateTime.now();
                    await showDetailSheet(context, item, goBaseUrl: Uri.base.origin);
                    final timeViewedMs = DateTime.now().difference(started).inMilliseconds;
                    if (context.mounted && !ref.read(analyticsOptOutProvider)) {
                      client.logEvent(
                        sessionId: sid,
                        eventType: 'detail_dismiss',
                        itemId: item.id,
                        metadata: <String, dynamic>{'timeViewedMs': timeViewedMs},
                      ).ignore();
                    }
                  }
                : null,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_userFriendlyError(e), style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: AppTheme.spacingUnit),
                ElevatedButton(
                  onPressed: () => ref.read(deckItemsProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: () => _showFiltersSheet(context, ref),
          tooltip: 'Filters',
        ),
        IconButton(
          icon: const Icon(Icons.favorite_border),
          onPressed: () => context.push('/likes'),
          tooltip: 'Likes',
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push('/profile'),
          tooltip: 'Profile',
        ),
      ],
    );
  }

  void _showFiltersSheet(BuildContext context, WidgetRef ref) {
    final sessionId = ref.read(sessionIdProvider);
    if (sessionId != null && !ref.read(analyticsOptOutProvider)) {
      ref.read(apiClientProvider).logEvent(sessionId: sessionId, eventType: 'filter_sheet_open').ignore();
    }
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
      ),
      builder: (context) => _DeckFiltersSheet(
        currentFilters: ref.read(deckFiltersProvider),
        onApply: (filters) {
          ref.read(deckFiltersProvider.notifier).state = Map<String, dynamic>.from(filters);
          ref.read(deckItemsProvider.notifier).refresh();
          if (sessionId != null && !ref.read(analyticsOptOutProvider)) {
            ref.read(apiClientProvider).logEvent(
              sessionId: sessionId,
              eventType: 'filter_change',
              metadata: Map<String, dynamic>.from(filters),
            ).ignore();
          }
          Navigator.of(context).pop();
        },
        onClear: () {
          ref.read(deckFiltersProvider.notifier).state = <String, dynamic>{};
          ref.read(deckItemsProvider.notifier).refresh();
          if (sessionId != null && !ref.read(analyticsOptOutProvider)) {
            ref.read(apiClientProvider).logEvent(
              sessionId: sessionId,
              eventType: 'filter_change',
              metadata: <String, dynamic>{},
            ).ignore();
          }
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

/// Size class options (DATA_MODEL / TAG_TAXONOMY).
const List<String> _sizeClassOptions = ['small', 'medium', 'large'];

/// Color family options (DATA_MODEL / TAG_TAXONOMY).
const List<String> _colorFamilyOptions = [
  'white', 'beige', 'brown', 'gray', 'black', 'green', 'blue', 'red', 'yellow', 'orange', 'pink', 'multi',
];

/// New/used options.
const List<String> _newUsedOptions = ['new', 'used'];

class _DeckFiltersSheet extends StatefulWidget {
  const _DeckFiltersSheet({
    required this.currentFilters,
    required this.onApply,
    required this.onClear,
  });

  final Map<String, dynamic> currentFilters;
  final void Function(Map<String, dynamic> filters) onApply;
  final VoidCallback onClear;

  @override
  State<_DeckFiltersSheet> createState() => _DeckFiltersSheetState();
}

class _DeckFiltersSheetState extends State<_DeckFiltersSheet> {
  String? _sizeClass;
  String? _colorFamily;
  String? _newUsed;

  @override
  void initState() {
    super.initState();
    _sizeClass = widget.currentFilters['sizeClass'] as String?;
    _colorFamily = widget.currentFilters['colorFamily'] as String?;
    _newUsed = widget.currentFilters['newUsed'] as String?;
  }

  Map<String, dynamic> get _selectedFilters {
    final map = <String, dynamic>{};
    if (_sizeClass != null && _sizeClass!.isNotEmpty) map['sizeClass'] = _sizeClass!;
    if (_colorFamily != null && _colorFamily!.isNotEmpty) map['colorFamily'] = _colorFamily!;
    if (_newUsed != null && _newUsed!.isNotEmpty) map['newUsed'] = _newUsed!;
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(
            'Narrow the deck by size, color, and condition.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Text('Size', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: AppTheme.spacingUnit / 2),
          Wrap(
            spacing: AppTheme.spacingUnit / 2,
            runSpacing: AppTheme.spacingUnit / 2,
            children: [
              AppFilterChip(
                label: const Text('Any'),
                selected: _sizeClass == null,
                onSelected: (_) => setState(() => _sizeClass = null),
              ),
              ..._sizeClassOptions.map((v) => AppFilterChip(
                label: Text(v == 'small' ? 'Small' : v == 'medium' ? 'Medium' : 'Large'),
                selected: _sizeClass == v,
                onSelected: (_) => setState(() => _sizeClass = _sizeClass == v ? null : v),
              )),
            ],
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Text('Color', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: AppTheme.spacingUnit / 2),
          Wrap(
            spacing: AppTheme.spacingUnit / 2,
            runSpacing: AppTheme.spacingUnit / 2,
            children: [
              AppFilterChip(
                label: const Text('Any'),
                selected: _colorFamily == null,
                onSelected: (_) => setState(() => _colorFamily = null),
              ),
              ..._colorFamilyOptions.map((v) => AppFilterChip(
                label: Text(v[0].toUpperCase() + v.substring(1)),
                selected: _colorFamily == v,
                onSelected: (_) => setState(() => _colorFamily = _colorFamily == v ? null : v),
              )),
            ],
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Text('Condition', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: AppTheme.spacingUnit / 2),
          Wrap(
            spacing: AppTheme.spacingUnit / 2,
            runSpacing: AppTheme.spacingUnit / 2,
            children: [
              AppFilterChip(
                label: const Text('Any'),
                selected: _newUsed == null,
                onSelected: (_) => setState(() => _newUsed = null),
              ),
              ..._newUsedOptions.map((v) => AppFilterChip(
                label: Text(v == 'new' ? 'New' : 'Used'),
                selected: _newUsed == v,
                onSelected: (_) => setState(() => _newUsed = _newUsed == v ? null : v),
              )),
            ],
          ),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Row(
            children: [
              OutlinedButton(
                onPressed: widget.onClear,
                child: const Text('Clear all'),
              ),
              const SizedBox(width: AppTheme.spacingUnit),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => widget.onApply(_selectedFilters),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
