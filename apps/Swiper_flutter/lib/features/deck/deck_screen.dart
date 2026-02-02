import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/deck_provider.dart';
import '../../data/event_tracker.dart';
import '../../data/locale_provider.dart';
import '../../data/session_provider.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/detail_sheet.dart';
import '../../shared/widgets/filter_chip.dart' show AppFilterChip;
import '../../data/models/item.dart';
import '../../shared/widgets/swipe_deck.dart';

Map<String, dynamic> _itemSnapshot(Item item) {
  return {
    if (item.brand != null) 'brand': item.brand,
    'newUsed': item.newUsed,
    if (item.sizeClass != null) 'sizeClass': item.sizeClass,
    if (item.material != null) 'material': item.material,
    if (item.colorFamily != null) 'colorFamily': item.colorFamily,
    'styleTags': item.styleTags,
  };
}

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
    final strings = ref.watch(appStringsProvider);
    final swipeHintSeen = ref.watch(swipeHintSeenProvider);

    return AppShell(
      title: AppConstants.appName,
      leading: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () => _showMenuSheet(context, ref),
        tooltip: strings.menu,
      ),
      automaticallyImplyLeading: false,
      body: deckState.when(
        data: (items) {
          final notifier = ref.read(deckItemsProvider.notifier);
          final tracker = ref.read(eventTrackerProvider);
          final swipeHintNotifier = ref.read(swipeHintSeenProvider.notifier);
          final rank = notifier.rankContext;
          final itemScores = notifier.itemScores;
          final canUndo = notifier.canUndo;
          final showSwipeHint = items.isNotEmpty && !swipeHintSeen;
          return Stack(
            children: [
              SwipeDeck(
                items: items,
                sessionId: sessionId,
                goBaseUrl: Uri.base.origin,
                canUndo: canUndo,
                onUndo: () => notifier.undoLastSwipe(),
                onSwipeLeft: (item, position, {gesture = 'swipe'}) {
                  swipeHintNotifier.markSeen();
                  notifier.swipe(item.id, 'left', position, item: item, gesture: gesture);
                },
                onSwipeRight: (item, position, {gesture = 'swipe'}) {
                  swipeHintNotifier.markSeen();
                  notifier.swipe(item.id, 'right', position, item: item, gesture: gesture);
                },
                onCardImpressionStart: (item, impressionId) {
                  tracker.track('card_impression_start', {
                    'item': {
                      'itemId': item.id,
                      'positionInDeck': 0,
                      'source': 'deck',
                      if (rank != null) 'snapshot': _itemSnapshot(item),
                    },
                    'impression': {'impressionId': impressionId},
                    if (rank != null) 'rank': {
                      'rankerRunId': rank.rankerRunId,
                      'algorithmVersion': rank.algorithmVersion,
                      if (itemScores.containsKey(item.id)) 'scoreAtRender': itemScores[item.id],
                    },
                  });
                },
                onCardImpressionEnd: (impressionId, visibleDurationMs, endReason, itemId) {
                  tracker.track('card_impression_end', {
                    'item': {'itemId': itemId, 'positionInDeck': 0},
                    'impression': {
                      'impressionId': impressionId,
                      'visibleDurationMs': visibleDurationMs,
                      'endReason': endReason,
                    },
                  });
                },
                onTapDetail: sessionId != null
                    ? (item) async {
                        swipeHintNotifier.markSeen();
                        tracker.track('detail_open', {
                          'item': {'itemId': item.id, 'source': 'deck'},
                          'surface': {'name': 'detail'},
                        });
                        final started = DateTime.now();
                        await showDetailSheet(
                          context,
                          item,
                          goBaseUrl: Uri.base.origin,
                          onOutboundClick: (i) {
                            final domain = i.outboundUrl != null ? Uri.tryParse(i.outboundUrl!)?.host : null;
                            tracker.track('outbound_click', {
                              'item': {'itemId': i.id},
                              'outbound': {'destinationDomain': domain ?? 'unknown'},
                            });
                          },
                        );
                        final timeViewedMs = DateTime.now().difference(started).inMilliseconds;
                        if (context.mounted) {
                          tracker.track('detail_close', {
                            'item': {'itemId': item.id},
                            'ext': {'durationMs': timeViewedMs},
                          });
                        }
                      }
                    : null,
              ),
              if (showSwipeHint) SwipeHintOverlay(text: strings.swipeHint),
            ],
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
    );
  }

  void _showMenuSheet(BuildContext context, WidgetRef ref) {
    final strings = ref.read(appStringsProvider);
    final locale = ref.read(localeProvider);
    final currentLabel = locale.languageCode == 'sv' ? strings.swedish : strings.english;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHandle(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(strings.menu, style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              _MenuTile(
                icon: Icons.tune,
                title: strings.filters,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showFiltersSheet(context, ref);
                },
              ),
              _MenuTile(
                icon: Icons.favorite,
                title: strings.likes,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/likes');
                },
              ),
              const Divider(height: AppTheme.spacingUnit * 2),
              _MenuTile(
                icon: Icons.settings,
                title: strings.preferences,
                subtitle: strings.reRunOnboarding,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/onboarding');
                },
              ),
              _MenuTile(
                icon: Icons.shield_outlined,
                title: strings.dataAndPrivacy,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/profile/data-privacy');
                },
              ),
              _MenuTile(
                icon: Icons.language,
                title: strings.language,
                subtitle: '${strings.swedish} / ${strings.english} – $currentLabel',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showLanguageSheet(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref) {
    final strings = ref.read(appStringsProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(strings.swedish),
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(const Locale('sv'));
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              title: Text(strings.english),
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(const Locale('en'));
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFiltersSheet(BuildContext context, WidgetRef ref) {
    ref.read(eventTrackerProvider).track('filters_open', {});
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
          _trackFiltersApply(ref, filters);
          Navigator.of(context).pop();
        },
        onClear: () {
          ref.read(deckFiltersProvider.notifier).state = <String, dynamic>{};
          ref.read(deckItemsProvider.notifier).refresh();
          _trackFiltersApply(ref, <String, dynamic>{});
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _trackFiltersApply(WidgetRef ref, Map<String, dynamic> filters) {
    final active = <String, dynamic>{};
    final newUsed = filters['newUsed'] as String?;
    if (newUsed != null) active['newOnly'] = newUsed == 'new';
    final colorFamily = filters['colorFamily'] as String?;
    if (colorFamily != null && colorFamily.isNotEmpty) {
      active['colorFamilies'] = [colorFamily];
    }
    ref.read(eventTrackerProvider).track('filters_apply', {'filters': {'active': active}});
  }
}

class SwipeHintOverlay extends StatefulWidget {
  const SwipeHintOverlay({super.key, required this.text});

  final String text;

  @override
  State<SwipeHintOverlay> createState() => _SwipeHintOverlayState();
}

class _SwipeHintOverlayState extends State<SwipeHintOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _slide = Tween<Offset>(begin: const Offset(-0.2, 0), end: const Offset(0.2, 0)).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit * 1.5, vertical: AppTheme.spacingUnit),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppTheme.radiusChip),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SlideTransition(
                  position: _slide,
                  child: const Icon(Icons.arrow_forward, color: Colors.white, size: 36),
                ),
                const SizedBox(height: AppTheme.spacingUnit / 2),
                Text(
                  widget.text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
        decoration: BoxDecoration(
          color: AppTheme.textCaption.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      onTap: onTap,
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
