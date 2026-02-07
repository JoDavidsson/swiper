import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models/item.dart';
import '../../l10n/app_strings.dart';

/// Card displaying a product with premium image rendering.
///
/// Uses the contain + blurred background pattern:
/// 1. Background: Same image scaled to cover, heavily blurred
/// 2. Foreground: Same image scaled to contain (shows full product)
class DeckCard extends StatelessWidget {
  const DeckCard({
    super.key,
    required this.item,
    this.elevation,
    this.compact = false,
    this.usePremiumImage = true,
  });

  final Item item;
  final double? elevation;
  final bool compact;

  /// When true, uses premium image rendering (contain + blurred bg).
  /// When false, uses simple cover fit (legacy behavior).
  final bool usePremiumImage;

  @override
  Widget build(BuildContext context) {
    final rawImageUrl = item.firstImageUrl;
    // Use optimized image URLs with appropriate widths
    final cardImageUrl = rawImageUrl != null
        ? ApiClient.proxyImageUrl(rawImageUrl, width: ImageWidth.card)
        : null;
    final bgImageUrl = rawImageUrl != null
        ? ApiClient.proxyImageUrl(rawImageUrl, width: ImageWidth.thumbnail)
        : null;

    return Card(
      elevation: elevation,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image layer (premium or legacy)
          if (cardImageUrl != null && cardImageUrl.isNotEmpty)
            usePremiumImage
                ? _PremiumImageLayer(
                    imageUrl: cardImageUrl,
                    backgroundUrl: bgImageUrl ?? cardImageUrl,
                  )
                : _LegacyImageLayer(imageUrl: cardImageUrl)
          else
            const _DeckImagePlaceholder(isError: true),

          // Info overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _InfoOverlay(
              item: item,
              compact: compact,
            ),
          ),
          if (item.isFeatured)
            Positioned(
              top: 12,
              left: 12,
              child: _FeaturedBadge(label: item.featuredLabel),
            ),
        ],
      ),
    );
  }
}

class _FeaturedBadge extends StatelessWidget {
  const _FeaturedBadge({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(Localizations.localeOf(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label ?? strings.featured,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Premium image layer with contain + blurred background.
class _PremiumImageLayer extends StatelessWidget {
  const _PremiumImageLayer({
    required this.imageUrl,
    required this.backgroundUrl,
  });

  /// URL for the foreground (contained) image - higher quality.
  final String imageUrl;

  /// URL for the background (blurred) image - can be lower quality.
  final String backgroundUrl;

  static const double _blurSigma = 18.0;
  static const double _backgroundScale = 1.1;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background: blurred, scaled to cover (uses lower quality image)
        Transform.scale(
          scale: _backgroundScale,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: _blurSigma,
              sigmaY: _blurSigma,
              tileMode: TileMode.decal,
            ),
            child: CachedNetworkImage(
              imageUrl: backgroundUrl,
              fit: BoxFit.cover,
              memCacheWidth: 400, // Match thumbnail size
              placeholder: (_, __) => const _DeckImagePlaceholder(),
              errorWidget: (_, __, ___) => const _DeckImagePlaceholder(),
            ),
          ),
        ),
        // Foreground: contained, full product visible (uses higher quality)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingUnit / 2),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              memCacheWidth: 800, // Match card size
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) =>
                  const _DeckImagePlaceholder(isError: true),
            ),
          ),
        ),
      ],
    );
  }
}

/// Legacy image layer with simple cover fit.
class _LegacyImageLayer extends StatelessWidget {
  const _LegacyImageLayer({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => const _DeckImagePlaceholder(),
      errorWidget: (_, __, ___) => const _DeckImagePlaceholder(isError: true),
    );
  }
}

/// Info overlay showing title, price, and optional attributes.
class _InfoOverlay extends StatelessWidget {
  const _InfoOverlay({
    required this.item,
    required this.compact,
  });

  final Item item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              shadows: [
                const Shadow(
                  blurRadius: 4,
                  color: Colors.black38,
                ),
              ],
            ),
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
          ),
          if (!compact && item.sizeClass != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item.sizeClass!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ],
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
