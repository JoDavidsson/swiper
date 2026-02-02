import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/models/item.dart';

class DeckCard extends StatelessWidget {
  const DeckCard({
    super.key,
    required this.item,
    this.elevation,
    this.compact = false,
  });

  final Item item;
  final double? elevation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.firstImageUrl;
    return Card(
      elevation: elevation,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              // No spinner: designed placeholder to avoid "loading flash"
              placeholder: (_, __) => const _DeckImagePlaceholder(),
              errorWidget: (_, __, ___) => const _DeckImagePlaceholder(isError: true),
            )
          else
            const _DeckImagePlaceholder(isError: true),
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
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  if (!compact && item.sizeClass != null)
                    Chip(
                      label: Text(item.sizeClass!, style: const TextStyle(fontSize: 12)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckImagePlaceholder extends StatelessWidget {
  const _DeckImagePlaceholder({this.isError = false});

  final bool isError;

  @override
  Widget build(BuildContext context) {
    // Stable, non-white placeholder surface to avoid flash.
    const base = AppTheme.background;
    return Container(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFEFEFEF),
                  Color(0xFFF8F8F8),
                ],
              ),
            ),
          ),
          Center(
            child: Icon(
              isError ? Icons.image_not_supported : Icons.image,
              size: 56,
              color: AppTheme.textCaption,
            ),
          ),
        ],
      ),
    );
  }
}

