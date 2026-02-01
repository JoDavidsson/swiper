import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme.dart';
import '../../data/models/item.dart';
import 'draggable_swipe_card.dart';
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
    this.goBaseUrl,
    this.onTapDetail,
    this.onCardImpressionStart,
    this.onCardImpressionEnd,
  });

  final List<Item> items;
  final String? sessionId;
  final void Function(Item item, int position, {String gesture}) onSwipeLeft;
  final void Function(Item item, int position, {String gesture}) onSwipeRight;
  final String? goBaseUrl;
  /// If set, called when user taps card (e.g. to log open_detail, show sheet, log detail_dismiss).
  final Future<void> Function(Item item)? onTapDetail;
  /// Called when top card becomes visible (for card_impression_start).
  final void Function(Item item, String impressionId)? onCardImpressionStart;
  /// Called when top card leaves (for card_impression_end). Only called if visibleDurationMs >= 150. [itemId] is the card that left.
  final void Function(String impressionId, int visibleDurationMs, String endReason, String itemId)? onCardImpressionEnd;

  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<SwipeDeck> {
  String? _currentTopId;
  String? _impressionId;
  DateTime? _impressionStartedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartImpression());
  }

  @override
  void didUpdateWidget(SwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartImpression());
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

  void _onSwipeLeft() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _endImpressionIfAny('swipe');
    widget.onSwipeLeft(top, 0);
  }

  void _onSwipeRight() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _endImpressionIfAny('swipe');
    widget.onSwipeRight(top, 0);
  }

  void _onSwipeLeftButton() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _endImpressionIfAny('swipe');
    widget.onSwipeLeft(top, 0, gesture: 'button');
  }

  void _onSwipeRightButton() {
    if (widget.items.isEmpty) return;
    final top = widget.items.first;
    _endImpressionIfAny('swipe');
    widget.onSwipeRight(top, 0, gesture: 'button');
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: AppTheme.textCaption),
            const SizedBox(height: AppTheme.spacingUnit),
            Text('No more items', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingUnit),
            Text('Check back later or adjust filters.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    final top = widget.items.first;
    final rest = widget.items.sublist(1);

    return Column(
      children: [
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = rest.length - 1; i >= 0; i--)
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 8.0 * (rest.length - 1 - i),
                      left: 8.0 * (rest.length - 1 - i),
                    ),
                    child: Transform.scale(
                      scale: 1.0 - 0.05 * (rest.length - 1 - i),
                      child: _CardContent(item: rest[i]),
                    ),
                  ),
                ),
              Positioned.fill(
                child: DraggableSwipeCard(
                  item: top,
                  onSwipeLeft: _onSwipeLeft,
                  onSwipeRight: _onSwipeRight,
                  onTap: _onTapDetail,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Row(
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
              _ControlButton(icon: Icons.undo, color: AppTheme.textSecondary, onPressed: null),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.firstImageUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported, size: 64, color: AppTheme.textCaption))
          else
            Container(color: AppTheme.background, child: Icon(Icons.image_not_supported, size: 64, color: AppTheme.textCaption)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
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
