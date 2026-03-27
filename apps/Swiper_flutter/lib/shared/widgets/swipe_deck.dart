import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models/item.dart';
import '../../l10n/app_strings.dart';
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
  final void Function(String impressionId, int visibleDurationMs,
      String endReason, String itemId)? onCardImpressionEnd;

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

class _SwipeDeckState extends State<SwipeDeck> {
  String? _currentTopId;
  String? _impressionId;
  DateTime? _impressionStartedAt;
  VoidCallback? _triggerSwipeLeft;
  VoidCallback? _triggerSwipeRight;
  bool Function()? _isAnimatingGetter;
  bool _buttonSwipeInFlight = false;

  // Undo support: track last swiped item and direction
  Item? _lastSwipedItem;
  String? _lastSwipeDirection;

  bool get _isDeckAnimating =>
      _buttonSwipeInFlight || (_isAnimatingGetter?.call() ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeStartImpression());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _prefetchUpcomingImages());
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
        _buttonSwipeInFlight = false;
      }
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeStartImpression());
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _prefetchUpcomingImages());
    }
  }

  void _prefetchUpcomingImages() {
    if (!mounted) return;
    // Prefetch top + next 7 to reduce image pop-in with larger deck batches.
    final toPrefetch = widget.items.take(8);
    for (final item in toPrefetch) {
      final rawUrl = item.firstImageUrl;
      if (rawUrl == null || rawUrl.isEmpty) continue;
      final urls = <String>{
        ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.card),
        ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.thumbnail),
      };
      // Best-effort prefetch — silently ignore all failures (offline, CORS,
      // domain not proxied, non-image response, etc.).
      for (final url in urls) {
        try {
          precacheImage(
            CachedNetworkImageProvider(url),
            context,
            onError: (_, __) {
              // Swallow — logged once via errorWidget in the card itself.
            },
          ).catchError((_) {});
        } catch (_) {
          // Swallow synchronous errors (e.g. context not mounted).
        }
      }
    }
  }

  void _endImpressionIfAny(String endReason) {
    if (_impressionId == null ||
        _impressionStartedAt == null ||
        widget.onCardImpressionEnd == null) {
      return;
    }
    final itemId = _currentTopId ?? '';
    final durationMs =
        DateTime.now().difference(_impressionStartedAt!).inMilliseconds;
    if (durationMs >= _minImpressionDurationMs) {
      widget.onCardImpressionEnd!(
          _impressionId!, durationMs, endReason, itemId);
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
    if (_buttonSwipeInFlight) {
      setState(() => _buttonSwipeInFlight = false);
    }
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

  void _triggerButtonSwipe(String direction) {
    if (widget.items.isEmpty || _isDeckAnimating) return;
    final top = widget.items.first;
    _lastSwipedItem = top;
    _lastSwipeDirection = direction;
    _endImpressionIfAny('swipe');
    if (direction == 'left') {
      widget.onSwipeLeft(top, 0, gesture: 'button');
    } else {
      widget.onSwipeRight(top, 0, gesture: 'button');
    }
    final trigger =
        direction == 'left' ? _triggerSwipeLeft : _triggerSwipeRight;
    if (trigger == null) {
      widget.onSwipeAnimationEnd?.call(top);
      return;
    }
    setState(() => _buttonSwipeInFlight = true);
    trigger();
  }

  Future<void> _onTapDetail() async {
    if (widget.items.isEmpty || _isDeckAnimating) return;
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
    final strings = AppStrings(Localizations.localeOf(context));
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
                          elevation:
                              1.0 + (rest.length - 1 - i).clamp(0, 3) * 0.5,
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
                    onSwipeCancel: widget.onSwipeCancel != null
                        ? (item) => widget.onSwipeCancel!(item, 0)
                        : null,
                    onRegisterSwipeTriggers: (VoidCallback? left,
                        VoidCallback? right, bool Function()? isAnimating) {
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
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingUnit,
            AppTheme.spacingUnit / 2,
            AppTheme.spacingUnit,
            AppTheme.spacingUnit,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingUnit,
                  vertical: AppTheme.spacingUnit * 0.75,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  border: Border.all(
                    color: AppTheme.outlineSoft.withOpacity(0.8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _DeckActionButton(
                      icon: Icons.close_rounded,
                      color: AppTheme.negativeDislike,
                      tooltip: strings.skip,
                      onPressed: _isDeckAnimating
                          ? null
                          : () => _triggerButtonSwipe('left'),
                    ),
                    _DeckActionButton(
                      icon: Icons.info_outline_rounded,
                      color: AppTheme.secondaryAction,
                      tooltip: strings.details,
                      onPressed: _isDeckAnimating ? null : _onTapDetail,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DeckPrimaryActionButton(
                        icon: Icons.favorite_rounded,
                        label: strings.save,
                        onPressed: _isDeckAnimating
                            ? null
                            : () => _triggerButtonSwipe('right'),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onSwipeUndo != null && _lastSwipedItem != null)
                Positioned(
                  left: 18,
                  top: -18,
                  child: _UndoActionButton(
                    tooltip: strings.undo,
                    onPressed: _isDeckAnimating
                        ? null
                        : () {
                            final item = _lastSwipedItem!;
                            final direction = _lastSwipeDirection ?? 'right';
                            _lastSwipedItem = null;
                            _lastSwipeDirection = null;
                            widget.onSwipeUndo!(item, direction);
                            setState(() {});
                          },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeckActionButton extends StatefulWidget {
  const _DeckActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<_DeckActionButton> createState() => _DeckActionButtonState();
}

class _DeckActionButtonState extends State<_DeckActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: Material(
            color: widget.color.withOpacity(enabled ? 0.15 : 0.08),
            shape: const CircleBorder(),
            child: IconButton(
              icon: Icon(
                widget.icon,
                size: 30,
                color: enabled ? widget.color : AppTheme.textCaption,
              ),
              tooltip: widget.tooltip,
              onPressed: widget.onPressed,
              splashRadius: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeckPrimaryActionButton extends StatefulWidget {
  const _DeckPrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<_DeckPrimaryActionButton> createState() =>
      _DeckPrimaryActionButtonState();
}

class _DeckPrimaryActionButtonState extends State<_DeckPrimaryActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: FilledButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon, size: 20),
            label: Text(widget.label),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.positiveLike,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UndoActionButton extends StatelessWidget {
  const _UndoActionButton({
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: IconButton.filledTonal(
        icon: Icon(
          Icons.undo_rounded,
          color:
              onPressed != null ? AppTheme.textSecondary : AppTheme.textCaption,
        ),
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.surface.withOpacity(0.95),
          side: BorderSide(color: AppTheme.outlineSoft.withOpacity(0.8)),
        ),
      ),
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
    final strings = AppStrings(Localizations.localeOf(context));
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
                color: AppTheme.textCaption.withOpacity(0.1),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(
                hasFiltersApplied
                    ? Icons.filter_alt_off
                    : Icons.inventory_2_outlined,
                size: 40,
                color: AppTheme.textCaption,
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit * 2),
            // Message
            Text(
              hasFiltersApplied
                  ? strings.noItemsMatchFilters
                  : strings.noMoreItemsToShow,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            Text(
              hasFiltersApplied
                  ? strings.adjustFiltersOrClear
                  : strings.checkBackLater,
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
                  label: Text(strings.clearFilters),
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
                        label: Text(strings.refreshDeck),
                      )
                    : ElevatedButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(strings.refreshDeck),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
