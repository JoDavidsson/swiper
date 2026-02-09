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
    this.desaturation = 0,
  });

  final Item item;
  final double? elevation;
  final bool compact;

  /// When true, uses premium image rendering (contain + blurred bg).
  /// When false, uses simple cover fit (legacy behavior).
  final bool usePremiumImage;

  /// 0 = no change, 1 = strongest desaturation used for reject feedback.
  final double desaturation;

  @override
  Widget build(BuildContext context) {
    final imageUrls = item.images
        .map((e) => e.url.trim())
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final brandLabel = _brandLabel(item);

    final card = Card(
      elevation: elevation,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image layer (premium or legacy).
          if (imageUrls.isNotEmpty)
            usePremiumImage
                ? _PremiumImageLayer(
                    imageUrls: imageUrls,
                  )
                : _LegacyImageLayer(imageUrls: imageUrls)
          else
            const _DeckImagePlaceholder(isError: true),

          if (brandLabel != null && brandLabel.isNotEmpty)
            Positioned(
              top: 14,
              left: 14,
              child: _BrandChip(label: brandLabel),
            ),
          if (item.isFeatured)
            Positioned(
              top: 14,
              right: 14,
              child: _FeaturedBadge(label: item.featuredLabel),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _InfoPill(
              item: item,
              compact: compact,
            ),
          ),
        ],
      ),
    );

    final clampedDesaturation = desaturation.clamp(0.0, 1.0);
    if (clampedDesaturation <= 0) return card;
    final saturation = (1 - (clampedDesaturation * 0.5)).clamp(0.5, 1.0);
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
      child: card,
    );
  }
}

String? _brandLabel(Item item) {
  final brand = item.brand?.trim();
  if (brand != null && brand.isNotEmpty) return brand;
  if (item.styleTags.isNotEmpty) {
    final tag = item.styleTags.first.trim();
    if (tag.isNotEmpty) return tag;
  }
  return null;
}

List<double> _saturationMatrix(double saturation) {
  final inv = 1 - saturation;
  final r = 0.213 * inv;
  final g = 0.715 * inv;
  final b = 0.072 * inv;
  return <double>[
    r + saturation,
    g,
    b,
    0,
    0,
    r,
    g + saturation,
    b,
    0,
    0,
    r,
    g,
    b + saturation,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

class _BrandChip extends StatelessWidget {
  const _BrandChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.outlineSoft.withValues(alpha: 0.9)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.textSecondary,
              letterSpacing: 0.2,
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.priceHighlight.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? strings.featured,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Premium image layer with contain + blurred background.
class _PremiumImageLayer extends StatelessWidget {
  const _PremiumImageLayer({
    required this.imageUrls,
  });

  /// Candidate image URLs ordered by preference.
  final List<String> imageUrls;

  static const double _blurSigma = 20.0;
  static const double _backgroundScale = 1.14;

  @override
  Widget build(BuildContext context) {
    return _ResilientImageSwitcher(
      imageUrls: imageUrls,
      builder: (context, rawUrl, onImageError) {
        final bgUrl =
            ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.thumbnail);
        final fgUrl = ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.card);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Background: blurred, scaled to cover (uses lower quality image).
            Transform.scale(
              scale: _backgroundScale,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: _blurSigma,
                  sigmaY: _blurSigma,
                  tileMode: TileMode.decal,
                ),
                child: CachedNetworkImage(
                  imageUrl: bgUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 400, // Match thumbnail size.
                  placeholder: (_, __) => const _DeckImagePlaceholder(),
                  errorWidget: (_, __, ___) {
                    onImageError();
                    return const _DeckImagePlaceholder();
                  },
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x12000000),
                    Color(0x0A000000),
                  ],
                ),
              ),
            ),
            // Foreground: contained, full product visible (uses higher quality).
            // Centered vertically so white-background images don't cluster
            // at the bottom with a large blurred void above.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingUnit / 2,
                vertical: AppTheme.spacingUnit,
              ),
              child: CachedNetworkImage(
                imageUrl: fgUrl,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                memCacheWidth: 800, // Match card size.
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) {
                  onImageError();
                  return const _DeckImagePlaceholder(isError: true);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Legacy image layer with simple cover fit.
class _LegacyImageLayer extends StatelessWidget {
  const _LegacyImageLayer({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    return _ResilientImageSwitcher(
      imageUrls: imageUrls,
      builder: (context, rawUrl, onImageError) {
        final imageUrl =
            ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.card);
        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => const _DeckImagePlaceholder(),
          errorWidget: (_, __, ___) {
            onImageError();
            return const _DeckImagePlaceholder(isError: true);
          },
        );
      },
    );
  }
}

/// Floating information panel that protects image composition.
class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.item,
    required this.compact,
  });

  final Item item;
  final bool compact;

  String get _price => item.priceLabel();

  @override
  Widget build(BuildContext context) {
    final sizeMaterial = [
      if (item.sizeClass != null && item.sizeClass!.isNotEmpty) item.sizeClass!,
      if (item.material != null && item.material!.isNotEmpty) item.material!,
    ].join(' • ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!compact && sizeMaterial.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sizeMaterial,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.priceHighlight.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.priceHighlight.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _price,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.priceHighlight,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResilientImageSwitcher extends StatefulWidget {
  const _ResilientImageSwitcher({
    required this.imageUrls,
    required this.builder,
  });

  final List<String> imageUrls;
  final Widget Function(
    BuildContext context,
    String rawUrl,
    VoidCallback onImageError,
  ) builder;

  @override
  State<_ResilientImageSwitcher> createState() =>
      _ResilientImageSwitcherState();
}

class _ResilientImageSwitcherState extends State<_ResilientImageSwitcher> {
  int _index = 0;
  bool _queuedAdvance = false;

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return const _DeckImagePlaceholder(isError: true);
    }
    return widget.builder(context, widget.imageUrls[_index], _tryAdvance);
  }

  void _tryAdvance() {
    if (_queuedAdvance) return;
    if (_index >= widget.imageUrls.length - 1) return;
    _queuedAdvance = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queuedAdvance = false;
      if (_index < widget.imageUrls.length - 1) {
        setState(() => _index += 1);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ResilientImageSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls != widget.imageUrls) {
      _index = 0;
      _queuedAdvance = false;
    }
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
                  Color(0xFFF1EBE2),
                  Color(0xFFF9F6F0),
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
