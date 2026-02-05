import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Premium image display with contain + blurred background.
///
/// This widget displays product images without distortion by using two layers:
/// 1. Background: Same image scaled to cover, heavily blurred
/// 2. Foreground: Same image scaled to contain (shows full product)
///
/// This ensures furniture images always look premium regardless of aspect ratio.
class PremiumImageCard extends StatelessWidget {
  const PremiumImageCard({
    super.key,
    required this.imageUrl,
    this.aspectRatio = 4 / 5,
    this.borderRadius = AppTheme.radiusCard,
    this.blurSigma = 18.0,
    this.backgroundScale = 1.1,
    this.placeholder,
    this.errorWidget,
  });

  /// The image URL to display.
  final String imageUrl;

  /// Aspect ratio of the card (width / height). Default is 4:5 (portrait).
  final double aspectRatio;

  /// Border radius for the card corners.
  final double borderRadius;

  /// Blur intensity for the background layer.
  final double blurSigma;

  /// Scale factor for background to avoid edge artifacts.
  final double backgroundScale;

  /// Optional custom placeholder widget.
  final Widget? placeholder;

  /// Optional custom error widget.
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background layer: blurred, scaled to cover entire card
            _BlurredBackground(
              imageUrl: imageUrl,
              blurSigma: blurSigma,
              scale: backgroundScale,
            ),
            // Foreground layer: full product, contained and centered
            _ContainedImage(
              imageUrl: imageUrl,
              placeholder: placeholder,
              errorWidget: errorWidget,
            ),
          ],
        ),
      ),
    );
  }
}

/// Blurred background layer that fills the card.
class _BlurredBackground extends StatelessWidget {
  const _BlurredBackground({
    required this.imageUrl,
    required this.blurSigma,
    required this.scale,
  });

  final String imageUrl;
  final double blurSigma;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.decal,
        ),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          // Use lower quality for background since it's blurred
          memCacheWidth: 400,
          placeholder: (_, __) => const _ImagePlaceholder(),
          errorWidget: (_, __, ___) => const _ImagePlaceholder(),
        ),
      ),
    );
  }
}

/// Foreground image layer that shows the full product.
class _ContainedImage extends StatelessWidget {
  const _ContainedImage({
    required this.imageUrl,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        placeholder: (_, __) =>
            placeholder ?? const SizedBox.shrink(),
        errorWidget: (_, __, ___) =>
            errorWidget ?? const _ImageErrorWidget(),
      ),
    );
  }
}

/// Default placeholder during image loading.
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceVariant,
    );
  }
}

/// Default error widget when image fails to load.
class _ImageErrorWidget extends StatelessWidget {
  const _ImageErrorWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceVariant,
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: AppTheme.textCaption,
        ),
      ),
    );
  }
}

/// Shimmer placeholder for premium loading effect.
class PremiumImageShimmer extends StatefulWidget {
  const PremiumImageShimmer({
    super.key,
    this.aspectRatio = 4 / 5,
    this.borderRadius = AppTheme.radiusCard,
  });

  final double aspectRatio;
  final double borderRadius;

  @override
  State<PremiumImageShimmer> createState() => _PremiumImageShimmerState();
}

class _PremiumImageShimmerState extends State<PremiumImageShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(_animation.value - 1, 0),
                  end: Alignment(_animation.value, 0),
                  colors: const [
                    AppTheme.surfaceVariant,
                    AppTheme.surface,
                    AppTheme.surfaceVariant,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
