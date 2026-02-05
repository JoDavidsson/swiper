import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/deck_provider.dart';
import '../../data/event_tracker.dart';
import '../../data/gold_card_provider.dart';
import '../../data/locale_provider.dart';
import '../../data/session_provider.dart' show sessionIdProvider, swipeHintSeenProvider, ensureSession, clearSessionId, currentSurfaceProvider;
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/detail_sheet.dart';
import '../../shared/widgets/filter_chip.dart' show AppFilterChip;
import '../../data/models/item.dart';
import '../../shared/widgets/swipe_deck.dart';
import 'widgets/gold_card_visual.dart';
import 'widgets/gold_card_budget.dart';

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

class DeckScreen extends ConsumerStatefulWidget {
  const DeckScreen({super.key});

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends ConsumerState<DeckScreen> {
  // Track if we're showing a gold card to prevent duplicate insertions
  bool _showingGoldCard = false;
  // Key for the gold card visual widget to access its state
  final GlobalKey<GoldCardVisualState> _goldCardVisualKey = GlobalKey<GoldCardVisualState>();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) ref.read(currentSurfaceProvider.notifier).state = {'name': 'deck_card'};
    });
    final deckState = ref.watch(deckItemsProvider);
    final sessionId = ref.watch(sessionIdProvider);
    final strings = ref.watch(appStringsProvider);
    final swipeHintSeen = ref.watch(swipeHintSeenProvider);
    final goldCardState = ref.watch(goldCardProvider);
    final curatedSofasAsync = ref.watch(curatedSofasProvider);

    return AppShell(
      title: AppConstants.appName,
      leading: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () => _showMenuSheet(context, ref),
        tooltip: strings.menu,
      ),
      automaticallyImplyLeading: false,
      body: deckState.when(
        loading: () {
          return const Center(child: CircularProgressIndicator());
        },
        data: (items) {
          final notifier = ref.read(deckItemsProvider.notifier);
          final tracker = ref.read(eventTrackerProvider);
          final swipeHintNotifier = ref.read(swipeHintSeenProvider.notifier);
          final goldCardNotifier = ref.read(goldCardProvider.notifier);
          final rank = notifier.rankContext;
          final itemScores = notifier.itemScores;
          
          // Determine if we should show a gold card
          final shouldShowVisualCard = goldCardState.shouldShowVisualCard && !_showingGoldCard;
          final shouldShowBudgetCard = goldCardState.shouldShowBudgetCard && !_showingGoldCard;
          final curatedSofas = curatedSofasAsync.valueOrNull ?? [];
          
          // Show gold card as overlay if conditions are met
          if (shouldShowVisualCard && curatedSofas.isNotEmpty && items.isNotEmpty) {
            return _buildGoldCardVisualOverlay(
              context,
              curatedSofas,
              goldCardNotifier,
              tracker,
              sessionId,
              items,
              notifier,
              swipeHintNotifier,
              rank,
              itemScores,
              swipeHintSeen,
              strings,
            );
          }
          
          if (shouldShowBudgetCard) {
            return _buildGoldCardBudgetOverlay(
              context,
              goldCardNotifier,
              goldCardState,
              tracker,
              sessionId,
              items,
              notifier,
              swipeHintNotifier,
              rank,
              itemScores,
              swipeHintSeen,
              strings,
            );
          }
          
          final showSwipeHint = items.isNotEmpty && !swipeHintSeen;
          return Stack(
            children: [
              SwipeDeck(
                items: items,
                sessionId: sessionId,
                goBaseUrl: Uri.base.origin,
                onSwipeLeft: (item, position, {gesture = 'swipe'}) {
                  swipeHintNotifier.markSeen();
                  notifier.swipe(item.id, 'left', position, item: item, gesture: gesture);
                },
                onSwipeRight: (item, position, {gesture = 'swipe'}) {
                  swipeHintNotifier.markSeen();
                  notifier.swipe(item.id, 'right', position, item: item, gesture: gesture);
                  // Increment right swipe count for gold card triggering
                  goldCardNotifier.incrementRightSwipes();
                },
                onSwipeAnimationEnd: (item) {
                  notifier.removeItemById(item.id);
                },
                onCardImpressionStart: (item, impressionId) {
                  tracker.track('card_render', {
                    'item': {
                      'itemId': item.id,
                      'positionInDeck': 0,
                      'source': 'deck',
                      if (rank != null) 'snapshot': _itemSnapshot(item),
                    },
                    if (rank != null) 'rank': {
                      'rankerRunId': rank.rankerRunId,
                      'algorithmVersion': rank.algorithmVersion,
                      if (itemScores.containsKey(item.id)) 'scoreAtRender': itemScores[item.id],
                    },
                  });
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
                  final bucket = visibleDurationMs < 1000
                      ? '0_1s'
                      : visibleDurationMs < 3000
                          ? '1_3s'
                          : visibleDurationMs < 8000
                              ? '3_8s'
                              : '8s_plus';
                  tracker.track('card_impression_end', {
                    'item': {'itemId': itemId, 'positionInDeck': 0},
                    'impression': {
                      'impressionId': impressionId,
                      'visibleDurationMs': visibleDurationMs,
                      'endReason': endReason,
                      'bucket': bucket,
                    },
                  });
                },
                onSwipeCancel: (item, position) {
                  tracker.track('swipe_cancel', {
                    'item': {'itemId': item.id, 'positionInDeck': position, 'source': 'deck'},
                    'interaction': {'gesture': 'swipe'},
                  });
                },
                onSwipeUndo: (item, direction) {
                  tracker.track('swipe_undo', {
                    'item': {'itemId': item.id, 'source': 'deck'},
                    'interaction': {'direction': direction},
                  });
                  // Restore the item to the front of the deck
                  notifier.restoreItem(item);
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
                          onScroll: () => tracker.track('detail_scroll', {'item': {'itemId': item.id}}),
                          onGalleryPageChange: (i) => tracker.track('detail_gallery_interaction', {
                            'item': {'itemId': item.id},
                            'ext': {'imageIndex': i},
                          }),
                          onOutboundRedirectStart: (i) {
                            final domain = i.outboundUrl != null ? Uri.tryParse(i.outboundUrl!)?.host : null;
                            tracker.track('outbound_redirect_start', {
                              'item': {'itemId': i.id},
                              'outbound': {'destinationDomain': domain ?? 'unknown'},
                            });
                          },
                          onOutboundRedirectSuccess: (i) {
                            final domain = i.outboundUrl != null ? Uri.tryParse(i.outboundUrl!)?.host : null;
                            tracker.track('outbound_redirect_success', {
                              'item': {'itemId': i.id},
                              'outbound': {'destinationDomain': domain ?? 'unknown'},
                            });
                          },
                          onOutboundRedirectFail: (i, e) {
                            final domain = i.outboundUrl != null ? Uri.tryParse(i.outboundUrl!)?.host : null;
                            tracker.track('outbound_redirect_fail', {
                              'item': {'itemId': i.id},
                              'outbound': {'destinationDomain': domain ?? 'unknown'},
                              'error': {'errorType': e.runtimeType.toString()},
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
                // Empty deck UX improvements
                hasFiltersApplied: ref.read(deckFiltersProvider).isNotEmpty,
                onClearFilters: () {
                  ref.read(eventTrackerProvider).track('filters_clear', {});
                  ref.read(deckFiltersProvider.notifier).state = <String, dynamic>{};
                  ref.read(deckItemsProvider.notifier).refresh();
                },
                onRefresh: () => ref.read(deckItemsProvider.notifier).refresh(),
              ),
              if (showSwipeHint) SwipeHintOverlay(text: strings.swipeHint),
            ],
          );
        },
        error: (e, st) {
          return Center(
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
          );
        },
      ),
    );
  }

  Widget _buildGoldCardVisualOverlay(
    BuildContext context,
    List<CuratedSofa> curatedSofas,
    GoldCardNotifier goldCardNotifier,
    dynamic tracker,
    String? sessionId,
    List<Item> items,
    DeckNotifier deckNotifier,
    dynamic swipeHintNotifier,
    DeckRankContext? rank,
    Map<String, double> itemScores,
    bool swipeHintSeen,
    dynamic strings,
  ) {
    final startTime = DateTime.now();
    
    // Track gold card shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tracker.track('gold_card_visual_shown', {
        'goldCard': {'swipeNumber': ref.read(goldCardProvider).totalRightSwipes},
      });
    });
    
    return _GoldCardSwipeWrapper(
      child: GoldCardVisual(
        key: _goldCardVisualKey,
        sofas: curatedSofas,
        onComplete: (pickedItemIds) async {
          final durationMs = DateTime.now().difference(startTime).inMilliseconds;
          tracker.track('gold_card_visual_complete', {
            'goldCard': {
              'pickedItemIds': pickedItemIds,
              'durationMs': durationMs,
            },
          });
          await goldCardNotifier.completeVisualCard(pickedItemIds);
          // Submit to API
          if (sessionId != null) {
            try {
              await ref.read(apiClientProvider).submitOnboardingPicks(
                sessionId: sessionId,
                pickedItemIds: pickedItemIds,
              );
            } catch (_) {
              // Non-blocking - picks are stored locally regardless
            }
          }
        },
        onSkip: () {
          tracker.track('gold_card_visual_skip', {
            'goldCard': {
              'swipeNumber': ref.read(goldCardProvider).totalRightSwipes,
              'skipCount': ref.read(goldCardProvider).visualSkipCount + 1,
            },
          });
          goldCardNotifier.skipVisualCard();
        },
      ),
      onSwipeRight: () {
        // Only allow swipe right if 3 items selected
        final state = _goldCardVisualKey.currentState;
        if (state != null && state.isSelectionComplete) {
          state.submitSelection();
        }
      },
      onSwipeLeft: () {
        goldCardNotifier.skipVisualCard();
        tracker.track('gold_card_visual_skip', {
          'goldCard': {
            'swipeNumber': ref.read(goldCardProvider).totalRightSwipes,
            'skipCount': ref.read(goldCardProvider).visualSkipCount + 1,
          },
        });
      },
      canSwipeRight: () {
        final state = _goldCardVisualKey.currentState;
        return state?.isSelectionComplete ?? false;
      },
    );
  }

  Widget _buildGoldCardBudgetOverlay(
    BuildContext context,
    GoldCardNotifier goldCardNotifier,
    GoldCardState goldCardState,
    dynamic tracker,
    String? sessionId,
    List<Item> items,
    DeckNotifier deckNotifier,
    dynamic swipeHintNotifier,
    DeckRankContext? rank,
    Map<String, double> itemScores,
    bool swipeHintSeen,
    dynamic strings,
  ) {
    final startTime = DateTime.now();
    final budgetKey = GlobalKey<GoldCardBudgetState>();
    
    // Track gold card shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tracker.track('gold_card_budget_shown', {});
    });
    
    return _GoldCardSwipeWrapper(
      child: GoldCardBudget(
        key: budgetKey,
        initialMin: goldCardState.budgetMin,
        initialMax: goldCardState.budgetMax,
        onComplete: (budgetMin, budgetMax) async {
          final durationMs = DateTime.now().difference(startTime).inMilliseconds;
          tracker.track('gold_card_budget_complete', {
            'goldCard': {
              'budgetMin': budgetMin,
              'budgetMax': budgetMax,
              'durationMs': durationMs,
            },
          });
          await goldCardNotifier.completeBudgetCard(budgetMin, budgetMax);
          // Update API with budget
          if (sessionId != null && goldCardState.pickedItemIds.isNotEmpty) {
            try {
              await ref.read(apiClientProvider).submitOnboardingPicks(
                sessionId: sessionId,
                pickedItemIds: goldCardState.pickedItemIds,
                budgetMin: budgetMin,
                budgetMax: budgetMax,
              );
            } catch (_) {
              // Non-blocking
            }
          }
        },
        onSkip: () {
          tracker.track('gold_card_budget_skip', {
            'goldCard': {'skipCount': ref.read(goldCardProvider).budgetSkipCount + 1},
          });
          goldCardNotifier.skipBudgetCard();
        },
      ),
      onSwipeRight: () {
        final state = budgetKey.currentState;
        if (state != null) {
          state.widget.onComplete(state.budgetMin, state.budgetMax);
        }
      },
      onSwipeLeft: () {
        goldCardNotifier.skipBudgetCard();
        tracker.track('gold_card_budget_skip', {
          'goldCard': {'skipCount': ref.read(goldCardProvider).budgetSkipCount + 1},
        });
      },
      canSwipeRight: () => true, // Budget card can always be submitted
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
      builder: (sheetContext) => LayoutBuilder(
        builder: (ctx, constraints) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              child: SingleChildScrollView(
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
                    const Divider(height: AppTheme.spacingUnit * 2),
                    _MenuTile(
                      icon: Icons.refresh,
                      title: strings.startOver,
                      subtitle: strings.startOverSubtitle,
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await clearSessionId();
                        ref.read(sessionIdProvider.notifier).state = null;
                        await ensureSession(ref, ref.read(apiClientProvider));
                        ref.invalidate(deckItemsProvider);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
        onFilterChange: (key, from, to) {
          ref.read(eventTrackerProvider).track('filter_change', {
            'filters': {'change': {'key': key, 'from': from, 'to': to}},
          });
        },
        onApply: (filters) {
          ref.read(deckFiltersProvider.notifier).state = Map<String, dynamic>.from(filters);
          ref.read(deckItemsProvider.notifier).refresh();
          _trackFiltersApply(ref, filters);
          Navigator.of(context).pop();
        },
        onClear: () {
          ref.read(eventTrackerProvider).track('filters_clear', {});
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
    this.onFilterChange,
  });

  final Map<String, dynamic> currentFilters;
  final void Function(Map<String, dynamic> filters) onApply;
  final VoidCallback onClear;
  final void Function(String key, Object? from, Object? to)? onFilterChange;

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
                onSelected: (_) {
                  widget.onFilterChange?.call('smallSpaceOnly', _sizeClass, null);
                  setState(() => _sizeClass = null);
                },
              ),
              ..._sizeClassOptions.map((v) => AppFilterChip(
                label: Text(v == 'small' ? 'Small' : v == 'medium' ? 'Medium' : 'Large'),
                selected: _sizeClass == v,
                onSelected: (_) {
                  widget.onFilterChange?.call('smallSpaceOnly', _sizeClass, _sizeClass == v ? null : v);
                  setState(() => _sizeClass = _sizeClass == v ? null : v);
                },
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
                onSelected: (_) {
                  widget.onFilterChange?.call('colorFamilies', _colorFamily, null);
                  setState(() => _colorFamily = null);
                },
              ),
              ..._colorFamilyOptions.map((v) => AppFilterChip(
                label: Text(v[0].toUpperCase() + v.substring(1)),
                selected: _colorFamily == v,
                onSelected: (_) {
                  widget.onFilterChange?.call('colorFamilies', _colorFamily, _colorFamily == v ? null : v);
                  setState(() => _colorFamily = _colorFamily == v ? null : v);
                },
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
                onSelected: (_) {
                  widget.onFilterChange?.call('newOnly', _newUsed == 'new', null);
                  setState(() => _newUsed = null);
                },
              ),
              ..._newUsedOptions.map((v) => AppFilterChip(
                label: Text(v == 'new' ? 'New' : 'Used'),
                selected: _newUsed == v,
                onSelected: (_) {
                  widget.onFilterChange?.call('newOnly', _newUsed == 'new', _newUsed == v ? null : v == 'new');
                  setState(() => _newUsed = _newUsed == v ? null : v);
                },
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

/// Wrapper widget that makes gold cards swipeable like regular cards
class _GoldCardSwipeWrapper extends StatefulWidget {
  const _GoldCardSwipeWrapper({
    required this.child,
    required this.onSwipeRight,
    required this.onSwipeLeft,
    this.canSwipeRight,
  });

  final Widget child;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  final bool Function()? canSwipeRight;

  @override
  State<_GoldCardSwipeWrapper> createState() => _GoldCardSwipeWrapperState();
}

class _GoldCardSwipeWrapperState extends State<_GoldCardSwipeWrapper>
    with SingleTickerProviderStateMixin {
  double _dragDx = 0;
  double _dragDy = 0;
  late AnimationController _animationController;
  Animation<Offset>? _exitAnimation;
  bool _isAnimatingOut = false;

  static const double _swipeThreshold = 100;
  static const double _velocityThreshold = 800;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (_isAnimatingOut) return;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isAnimatingOut) return;
    setState(() {
      _dragDx += details.delta.dx;
      _dragDy += details.delta.dy;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isAnimatingOut) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldSwipeRight = (_dragDx > _swipeThreshold || velocity > _velocityThreshold) &&
        (widget.canSwipeRight?.call() ?? true);
    final shouldSwipeLeft = _dragDx < -_swipeThreshold || velocity < -_velocityThreshold;

    if (shouldSwipeRight) {
      _animateOut(toRight: true);
    } else if (shouldSwipeLeft) {
      _animateOut(toRight: false);
    } else {
      _snapBack();
    }
  }

  void _animateOut({required bool toRight}) {
    _isAnimatingOut = true;
    final screenWidth = MediaQuery.of(context).size.width;
    final endX = toRight ? screenWidth * 1.5 : -screenWidth * 1.5;
    
    _exitAnimation = Tween<Offset>(
      begin: Offset(_dragDx, _dragDy),
      end: Offset(endX, _dragDy),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward(from: 0).then((_) {
      if (toRight) {
        widget.onSwipeRight();
      } else {
        widget.onSwipeLeft();
      }
    });
  }

  void _snapBack() {
    setState(() {
      _dragDx = 0;
      _dragDy = 0;
    });
  }

  double get _rotation => _dragDx / 1000;

  Color? get _overlayColor {
    if (_dragDx > 30) {
      return AppTheme.positiveLike.withValues(alpha: (_dragDx / 200).clamp(0, 0.3));
    } else if (_dragDx < -30) {
      return AppTheme.negativeDislike.withValues(alpha: (-_dragDx / 200).clamp(0, 0.3));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: AppTheme.background,
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final offset = _isAnimatingOut
                      ? _exitAnimation?.value ?? Offset(_dragDx, _dragDy)
                      : Offset(_dragDx, _dragDy);
                  
                  return Transform(
                    transform: Matrix4.identity()
                      ..translate(offset.dx, offset.dy)
                      ..rotateZ(_isAnimatingOut ? _dragDx / 1000 : _rotation),
                    alignment: Alignment.center,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.child,
                        if (_overlayColor != null && !_isAnimatingOut)
                          IgnorePointer(
                            child: Container(
                              margin: const EdgeInsets.all(AppTheme.spacingUnit),
                              decoration: BoxDecoration(
                                color: _overlayColor,
                                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Control buttons
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    icon: Icons.close,
                    color: AppTheme.negativeDislike,
                    onPressed: () => _animateOut(toRight: false),
                  ),
                  const SizedBox(width: AppTheme.spacingUnit * 2),
                  _ControlButton(
                    icon: Icons.favorite,
                    color: AppTheme.positiveLike,
                    onPressed: (widget.canSwipeRight?.call() ?? true)
                        ? () => _animateOut(toRight: true)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.color, required this.onPressed});

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      icon: Icon(icon, color: onPressed != null ? color : AppTheme.textCaption),
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: color.withValues(alpha: 0.2)),
    );
  }
}
