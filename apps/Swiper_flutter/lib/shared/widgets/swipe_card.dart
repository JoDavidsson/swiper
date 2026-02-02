import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../data/models/item.dart';

/// Shared swipe card view (top card + stack cards).
class SwipeCard extends StatelessWidget {
  const SwipeCard({
    super.key,
    required this.item,
    this.overlay,
  });

  final Item item;
  final Widget? overlay;

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
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) => Container(
                color: AppTheme.background,
                child: Icon(Icons.image_not_supported, size: 64, color: AppTheme.textCaption),
              ),
            )
          else
            Container(
              color: AppTheme.background,
              child: Icon(Icons.image_not_supported, size: 64, color: AppTheme.textCaption),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          if (overlay != null) overlay!,
        ],
      ),
    );
  }
}
