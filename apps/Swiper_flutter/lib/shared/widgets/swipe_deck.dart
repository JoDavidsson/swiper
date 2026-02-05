import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models/item.dart';
import 'draggable_swipe_card.dart';
import 'deck_card.dart';
import 'detail_sheet.dart';

const _minImpressionDurationMs = 150;
const _uuid = Uuid();

/// Full-screen swipe deck: stack of cards with stack peek.
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    super.key,
    required this.items,
    required this.sessionId,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    this.onSwipeAnimationEnd,
    this.goBaseUrl,
    this.onTapDetail,
    this.onCardImpressionStart,
    this.onCardImpressionEnd,
    this.onSwipeCancel,
    this.onSwipeUndo,
    this.hasFiltersApplied = false,
    this.onClearFilters,
    this.onRefresh,
  });

  final List<Item> items;
  final String? sessionId;
  final void Function(Item item, int position, {String gesture}) onSwipeLeft;
  final void Function(Item item, int position, {String gesture}) onSwipeRight;
  /// Called when the swipe-off animation completes so the list can remove the card (next card is already visible behind).
  final void Function(Item item)? onSwipeAnimationEnd;
  final String? goBaseUrl;
  /// If set, called when user taps card (e.g. to log open_detail, show sheet, log detail_dismiss).
  final Future<void> Function(Item item)? onTapDetail;
  /// Called when top card becomes visible (for card_impression_start).
  final void Function(Item item, String impressionId)? onCardImpressionStart;
  /// Called when top card leaves (for card_impression_end). Only called if visibleDurationMs >= 150. [itemId] is the card that left.
  final void Function(String impressionId, int visibleDurationMs, String endReason, String itemId)? onCardImpressionEnd;
  /// Called when user releases card without crossing swipe threshold (swipe_cancel).
  final void Function(Item item, int position)? onSwipeCancel;
  /// Called when user taps undo (swipe_undo). Wire to event tracker when undo is implemented.
  final void Function(Item item, String direction)? onSwipeUndo;
  /// Whether filters are currently applied (for empty state messaging).
  final bool hasFiltersApplied;
  /// Callback when user wants to clear filters from empty state.
  final VoidCallback? onClearFilters;
  /// Callback when user wants to refresh the deck.
  final VoidCallback? onRefresh;

  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

const _kAgentIngestUrl = 'http://127.0.0.1:7245/ingest/ddc9e3c2-ad47-4244-9d77-ce2efa8256ba';

void _deckLayoutLog(String topId, List<String> restIds, int stackDepth) {
  if (!kDebugMode) return;
  try {
    final payload = {
      'location': 'swipe_deck.dart:build',
      'message': 'deck_layout',
      'data': {'topId': topId, 'restIds': restIds, 'stackDepth': stackDepth},
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sessionId': 'debug-session',
      'hypothesisId': 'flow',
    };
    Dio().post(_kAgentIngestUrl, data: payload).catchError((_) => Future.value(Response(requestOptions: RequestOptions(path: _kAgentIngestUrl))));
  } catch (_) {}
}

class _SwipeDeckState extends State<SwipeDeck> {
  String? _currentTopId;
  String? _impressionId;
  DateTime? _impressionStartedAt;
  // Reserved for programmatic swipe triggers (e.g., button controls)
  // ignore: unused_field
  VoidCallback? _triggerSwipeLeft;
  // ignore: unused_field
  VoidCallback? _triggerSwipeRight;
  // ignore: unused_field
  bool Function()? _isAnimatingGetter;
  String? _lastLoggedLayoutTopId;
  List<String>? _lastLoggedRestIds;
  
  // Undo support: track last swiped item and direction
  Item? _lastSwipedItem;
  String? _lastSwipeDirection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartImpression());
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchUpcomingImages());
  }

  @override
  void didUpdateWidget(SwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      // Clear triggers if items become empty
      if (widget.items.isEmpty) {
        _triggerSwipeLeft = null;
        _triggerSwipeRight = null;
        _isAnimatingGetter = null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartImpression());
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchUpcomingImages());
    }
  }

  void _prefetchUpcomingImages() {
    if (!mounted) return;
    // Prefetch top + next 4 to avoid image pop-in/flash on promotion.
    final toPrefetch = widget.items.take(5);
    for (final item in toPrefetch) {
      final rawUrl = item.firstImageUrl;
      if (rawUrl == null || rawUrl.isEmpty) continue;
      final url = ApiClient.proxyImageUrl(rawUrl);
      // Ignore failures (offline/cors/etc). Prefetch is best-effort.
      precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {});
    }
  }

  void _endImpressionIfAny(String endReason) {
    if (_impressionId == null || _impressionStartedAt == null || widget.onCardImpressionEnd == null) return;
    final itemId = _currentTopId ?? '';
    final durationMs = DateTime.now().difference(_impressionStartedAt!).inMilliseconds;
    if (durationMs >= _minImpressionDurationMs) {
      widget.onCardImpressionEnd!(_impressionId!, durationMs, endReason, itemId);
    }
    _impressionId = null;
    _impressionStartedAt = null;
    _currentTopId = null;
  }

  void _maybeStartImpression() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    if (top.id == _currentTopId) return;
    _endImpressionIfAny('nav');
    _currentTopId = top.id;
    _impressionId = _uuid.v4();
    _impressionStartedAt = DateTime.now();
    widget.onCardImpressionStart?.call(top, _impressionId!);
  }

  void _onSwipeAnimationEnd(Item item) {
    // #region agent log
    Dio().post(_kAgentIngestUrl, data: {'location': 'swipe_deck.dart:_onSwipeAnimationEnd', 'message': 'animation_end_callback', 'data': {'itemId': item.id}, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'sessionId': 'debug-session', 'hypothesisId': 'flow'}).catchError((_) => Future.value(Response(requestOptions: RequestOptions(path: _kAgentIngestUrl))));
    // #endregion
    widget.onSwipeAnimationEnd?.call(item);
  }

  void _onSwipeLeft() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _lastSwipedItem = top;
    _lastSwipeDirection = 'left';
    _endImpressionIfAny('swipe');
    widget.onSwipeLeft(top, 0);
  }

  void _onSwipeRight() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _lastSwipedItem = top;
    _lastSwipeDirection = 'right';
    _endImpressionIfAny('swipe');
    widget.onSwipeRight(top, 0);
  }

  void _onSwipeLeftButton() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _lastSwipedItem = top;
    _lastSwipeDirection = 'left';
    _endImpressionIfAny('swipe');
    widget.onSwipeLeft(top, 0, gesture: 'button');
    // Always remove directly for button presses (reliable, no animation timing issues)
    widget.onSwipeAnimationEnd?.call(top);
  }

  void _onSwipeRightButton() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _lastSwipedItem = top;
    _lastSwipeDirection = 'right';
    _endImpressionIfAny('swipe');
    widget.onSwipeRight(top, 0, gesture: 'button');
    // Always remove directly for button presses (reliable, no animation timing issues)
    widget.onSwipeAnimationEnd?.call(top);
  }

  Future<void> _onTapDetail() async {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _endImpressionIfAny('detail_open');
    if (widget.onTapDetail != null) {
      await widget.onTapDetail!(top);
    } else {
      if (mounted) showDetailSheet(context, top, goBaseUrl: widget.goBaseUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return _EmptyDeckWidget(
        hasFiltersApplied: widget.hasFiltersApplied,
        onClearFilters: widget.onClearFilters,
        onRefresh: widget.onRefresh,
      );
    }

    final top = widget.items.first;
    // Cap visible stack at 5 cards so order and images match "next to show".
    final rest = widget.items.length > 1
        ? widget.items.sublist(1, math.min(6, widget.items.length))
        : <Item>[];

    if (kDebugMode) {
      final restIds = rest.map((e) => e.id).toList();
      final stackDepth = rest.length + 1;
      final layoutChanged = _lastLoggedLayoutTopId != top.id ||
          !listEquals(_lastLoggedRestIds, restIds);
      if (layoutChanged) {
        _deckLayoutLog(top.id, restIds, stackDepth);
        _lastLoggedLayoutTopId = top.id;
        _lastLoggedRestIds = restIds;
      }
    }

    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            // Stable non-white background to avoid flash between frames.
            color: AppTheme.background,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = rest.length - 1; i >= 0; i--)
                  Positioned.fill(
                    key: ValueKey(rest[i].id),
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.only(
                        // Depth index: i=0 is next card under top.
                        top: 8.0 * i,
                        left: 8.0 * i,
                      ),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        // Depth index: i=0 is closest under top.
                        scale: 1.0 - 0.05 * i,
                        child: DeckCard(
                          item: rest[i],
                          compact: true,
                          elevation: 1.0 + (rest.length - 1 - i).clamp(0, 3) * 0.5,
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  key: ValueKey(top.id),
                  child: DraggableSwipeCard(
                    key: ValueKey(top.id),
                    item: top,
                    onSwipeLeft: _onSwipeLeft,
                    onSwipeRight: _onSwipeRight,
                    onSwipeAnimationEnd: _onSwipeAnimationEnd,
                    onTap: _onTapDetail,
                    onSwipeCancel: widget.onSwipeCancel != null ? (item) => widget.onSwipeCancel!(item, 0) : null,
                    onRegisterSwipeTriggers: (VoidCallback? left, VoidCallback? right, bool Function()? isAnimating) {
                      _triggerSwipeLeft = left;
                      _triggerSwipeRight = right;
                      _isAnimatingGetter = isAnimating;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
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
                    onPressed: _onSwipeLeftButton,
                  ),
                  const SizedBox(width: AppTheme.spacingUnit * 2),
                  _ControlButton(
                    icon: Icons.favorite,
                    color: AppTheme.positiveLike,
                    onPressed: _onSwipeRightButton,
                  ),
                  const SizedBox(width: AppTheme.spacingUnit * 2),
                  _ControlButton(
                    icon: Icons.undo,
                    color: AppTheme.textSecondary,
                    onPressed: widget.onSwipeUndo != null && _lastSwipedItem != null
                        ? () {
                            final item = _lastSwipedItem!;
                            final direction = _lastSwipeDirection ?? 'right';
                            _lastSwipedItem = null;
                            _lastSwipeDirection = null;
                            widget.onSwipeUndo!(item, direction);
                          }
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

/// Empty deck state widget with contextual messaging based on filter state.
class _EmptyDeckWidget extends StatelessWidget {
  const _EmptyDeckWidget({
    this.hasFiltersApplied = false,
    this.onClearFilters,
    this.onRefresh,
  });

  final bool hasFiltersApplied;
  final VoidCallback? onClearFilters;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon based on context
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.textCaption.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(
                hasFiltersApplied ? Icons.filter_alt_off : Icons.inventory_2_outlined,
                size: 40,
                color: AppTheme.textCaption,
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit * 2),
            // Message
            Text(
              hasFiltersApplied
                  ? 'No items match your filters'
                  : 'No more items to show',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            Text(
              hasFiltersApplied
                  ? 'Try adjusting your filters or clearing them to see more sofas.'
                  : 'Great job! Check back later for new arrivals.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingUnit * 3),
            // Action buttons
            if (hasFiltersApplied && onClearFilters != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear Filters'),
                ),
              ),
            if (hasFiltersApplied && onClearFilters != null)
              const SizedBox(height: AppTheme.spacingUnit),
            if (onRefresh != null)
              SizedBox(
                width: double.infinity,
                child: hasFiltersApplied
                    ? OutlinedButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Deck'),
                      )
                    : ElevatedButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Deck'),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
