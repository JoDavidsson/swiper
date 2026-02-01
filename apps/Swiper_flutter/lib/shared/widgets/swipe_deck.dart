import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/models/item.dart';
import 'draggable_swipe_card.dart';
import 'detail_sheet.dart';

/// Full-screen swipe deck: stack of cards with stack peek.
class SwipeDeck extends StatelessWidget {
  const SwipeDeck({
    super.key,
    required this.items,
    required this.sessionId,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    this.goBaseUrl,
    this.onTapDetail,
  });

  final List<Item> items;
  final String? sessionId;
  final void Function(Item item, int position) onSwipeLeft;
  final void Function(Item item, int position) onSwipeRight;
  final String? goBaseUrl;
  /// If set, called when user taps card (e.g. to log open_detail, show sheet, log detail_dismiss).
  final Future<void> Function(Item item)? onTapDetail;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
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

    final top = items.first;
    final rest = items.sublist(1);

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
                  onSwipeLeft: () => onSwipeLeft(top, 0),
                  onSwipeRight: () => onSwipeRight(top, 0),
                  onTap: () async {
                    if (onTapDetail != null) {
                      await onTapDetail!(top);
                    } else {
                      showDetailSheet(context, top, goBaseUrl: goBaseUrl);
                    }
                  },
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
                onPressed: () => onSwipeLeft(top, 0),
              ),
              const SizedBox(width: AppTheme.spacingUnit * 2),
              _ControlButton(
                icon: Icons.favorite,
                color: AppTheme.positiveLike,
                onPressed: () => onSwipeRight(top, 0),
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
