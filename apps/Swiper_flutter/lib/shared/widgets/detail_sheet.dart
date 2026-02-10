import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models/item.dart';

/// Human-readable labels for sofa sub-categories.
const _subCatLabels = {
  '2_seater': '2-sitssoffa',
  '3_seater': '3-sitssoffa',
  '4_seater': '4-sitssoffa',
  'corner_sofa': 'Hörnsoffa',
  'u_sofa': 'U-soffa',
  'chaise_sofa': 'Divansoffa',
  'modular_sofa': 'Modulsoffa',
  'sleeper_sofa': 'Bäddsoffa',
};

/// Human-readable labels for room types.
const _roomTypeLabels = {
  'living_room': 'Vardagsrum',
  'bedroom': 'Sovrum',
  'outdoor': 'Utomhus',
  'office': 'Kontor',
  'hallway': 'Hall',
  'kids_room': 'Barnrum',
};

const _primaryCategoryLabels = {
  'sofa': 'Sofa',
  'armchair': 'Armchair',
  'dining_table': 'Dining table',
  'coffee_table': 'Coffee table',
  'bed': 'Bed',
  'chair': 'Chair',
  'rug': 'Rug',
  'lamp': 'Lamp',
  'storage': 'Storage',
  'desk': 'Desk',
  'decor': 'Decor',
  'textile': 'Textile',
};

const _sofaShapeLabels = {
  'straight': 'Straight',
  'corner': 'Corner',
  'u_shaped': 'U-shaped',
  'chaise': 'Chaise',
  'modular': 'Modular',
};

const _sofaFunctionLabels = {
  'standard': 'Standard',
  'sleeper': 'Sleeper',
};

const _seatBucketLabels = {
  '2': '2 seats',
  '3': '3 seats',
  '4_plus': '4+ seats',
};

const _environmentLabels = {
  'indoor': 'Indoor',
  'outdoor': 'Outdoor',
  'both': 'Indoor + Outdoor',
};

String _subCatDisplayLabel(String id) =>
    _subCatLabels[id] ?? id.replaceAll('_', ' ');

String _roomTypeDisplayLabel(String id) =>
    _roomTypeLabels[id] ?? id.replaceAll('_', ' ');

String _primaryCategoryDisplayLabel(String id) =>
    _primaryCategoryLabels[id] ?? id.replaceAll('_', ' ');

String _sofaShapeDisplayLabel(String id) =>
    _sofaShapeLabels[id] ?? id.replaceAll('_', ' ');

String _sofaFunctionDisplayLabel(String id) =>
    _sofaFunctionLabels[id] ?? id.replaceAll('_', ' ');

String _seatBucketDisplayLabel(String id) =>
    _seatBucketLabels[id] ?? id.replaceAll('_', ' ');

String _environmentDisplayLabel(String id) =>
    _environmentLabels[id] ?? id.replaceAll('_', ' ');

String _decodeHtmlEntities(String input) {
  var out = input;
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&ouml;': 'ö',
    '&Ouml;': 'Ö',
    '&auml;': 'ä',
    '&Auml;': 'Ä',
    '&aring;': 'å',
    '&Aring;': 'Å',
  };
  entities.forEach((key, value) {
    out = out.replaceAll(key, value);
  });

  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1) ?? '');
    if (code == null) return m.group(0) ?? '';
    return String.fromCharCode(code);
  });
  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1) ?? '', radix: 16);
    if (code == null) return m.group(0) ?? '';
    return String.fromCharCode(code);
  });
  return out;
}

String? _cleanDescription(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Multi-pass entity decoding to handle double/triple-encoded HTML.
  var text = trimmed;
  for (var i = 0; i < 3; i++) {
    final decoded = _decodeHtmlEntities(text);
    if (decoded == text) break;
    text = decoded;
  }

  text = text.replaceAll(
    RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false),
    '\n',
  );
  // Run tag stripping twice to catch nested/malformed tags.
  text = text.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
  text = text.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');

  // Final entity decode to catch anything that was inside tags.
  text = _decodeHtmlEntities(text);

  final lines = text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;
  return lines.join('\n\n');
}

String _formatPrice(double amount, String currency) {
  if (amount <= 0) return 'Price unavailable';
  return '${amount.toStringAsFixed(0)} $currency';
}

String _formatDimensionValue(num? value) {
  if (value == null) return '-';
  final asDouble = value.toDouble();
  if (asDouble % 1 == 0) return asDouble.toStringAsFixed(0);
  return asDouble.toStringAsFixed(1);
}

List<String> _extractGalleryUrls(Item item) {
  final urls = item.images
      .map((e) => e.url.trim())
      .where((u) => u.isNotEmpty)
      .toSet()
      .toList();
  if (urls.isNotEmpty) return urls;
  final first = item.firstImageUrl?.trim();
  if (first != null && first.isNotEmpty) return [first];
  return const <String>[];
}

Future<void> showDetailSheet(
  BuildContext context,
  Item item, {
  String? goBaseUrl,
  void Function(Item item)? onOutboundClick,
  void Function(Item item)? onShare,
  void Function()? onScroll,
  void Function(int imageIndex)? onGalleryPageChange,
  void Function(Item item)? onOutboundRedirectStart,
  void Function(Item item)? onOutboundRedirectSuccess,
  void Function(Item item, Object error)? onOutboundRedirectFail,

  /// Whether this item is currently liked (shows filled heart if true)
  bool isLiked = false,

  /// Callback when user toggles like status. Returns new liked state.
  Future<bool> Function(Item item)? onToggleLike,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.96,
      minChildSize: 0.6,
      maxChildSize: 1,
      expand: false,
      builder: (context, scrollController) => DetailSheetContent(
        item: item,
        scrollController: scrollController,
        goBaseUrl: goBaseUrl,
        onOutboundClick: onOutboundClick,
        onShare: onShare,
        onScroll: onScroll,
        onGalleryPageChange: onGalleryPageChange,
        onOutboundRedirectStart: onOutboundRedirectStart,
        onOutboundRedirectSuccess: onOutboundRedirectSuccess,
        onOutboundRedirectFail: onOutboundRedirectFail,
        isLiked: isLiked,
        onToggleLike: onToggleLike,
      ),
    ),
  );
}

class DetailSheetContent extends StatefulWidget {
  const DetailSheetContent({
    super.key,
    required this.item,
    required this.scrollController,
    this.goBaseUrl,
    this.onOutboundClick,
    this.onShare,
    this.onScroll,
    this.onGalleryPageChange,
    this.onOutboundRedirectStart,
    this.onOutboundRedirectSuccess,
    this.onOutboundRedirectFail,
    this.isLiked = false,
    this.onToggleLike,
  });

  final Item item;
  final ScrollController scrollController;
  final String? goBaseUrl;
  final void Function(Item item)? onOutboundClick;
  final void Function(Item item)? onShare;
  final void Function()? onScroll;
  final void Function(int imageIndex)? onGalleryPageChange;
  final void Function(Item item)? onOutboundRedirectStart;
  final void Function(Item item)? onOutboundRedirectSuccess;
  final void Function(Item item, Object error)? onOutboundRedirectFail;
  final bool isLiked;
  final Future<bool> Function(Item item)? onToggleLike;

  @override
  State<DetailSheetContent> createState() => _DetailSheetContentState();
}

class _DetailSheetContentState extends State<DetailSheetContent> {
  bool _animateIn = false;
  int _lastScrollEmitMs = 0;
  static const _scrollThrottleMs = 500;
  late PageController _pageController;
  late bool _isLiked;
  bool _isTogglingLike = false;
  bool _showFullDescription = false;
  int _currentPage = 0;
  late List<String> _galleryUrls;

  @override
  void initState() {
    super.initState();
    _galleryUrls = _extractGalleryUrls(widget.item);
    _pageController = PageController();
    _isLiked = widget.isLiked;
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchGalleryImages();
      setState(() => _animateIn = true);
    });
  }

  @override
  void didUpdateWidget(covariant DetailSheetContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _galleryUrls = _extractGalleryUrls(widget.item);
      _currentPage = 0;
      _showFullDescription = false;
      _pageController.dispose();
      _pageController = PageController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prefetchGalleryImages();
      });
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  void _prefetchGalleryImages() {
    if (!mounted) return;
    for (final rawUrl in _galleryUrls.take(4)) {
      final thumbUrl =
          ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.thumbnail);
      final detailUrl =
          ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.detail);
      for (final url in [thumbUrl, detailUrl]) {
        precacheImage(CachedNetworkImageProvider(url), context)
            .catchError((_) {});
      }
    }
  }

  void _onScroll() {
    if (widget.onScroll == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastScrollEmitMs >= _scrollThrottleMs) {
      _lastScrollEmitMs = now;
      widget.onScroll!();
    }
  }

  Future<void> _toggleLike() async {
    if (widget.onToggleLike == null || _isTogglingLike) return;
    setState(() => _isTogglingLike = true);
    try {
      final newState = await widget.onToggleLike!(widget.item);
      if (mounted) {
        setState(() => _isLiked = newState);
      }
    } finally {
      if (mounted) {
        setState(() => _isTogglingLike = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final imageHeight = (screenHeight * 0.42).clamp(240.0, 460.0);
    final cleanedDescription = _cleanDescription(widget.item.descriptionShort);
    final hasLongDescription =
        cleanedDescription != null && cleanedDescription.length > 500;
    final visibleDescription = cleanedDescription == null
        ? null
        : (hasLongDescription && !_showFullDescription
            ? '${cleanedDescription.substring(0, 500).trimRight()}...'
            : cleanedDescription);

    return AnimatedScale(
      scale: _animateIn ? 1.0 : 0.98,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                  decoration: BoxDecoration(
                    color: AppTheme.textCaption.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _DetailGallery(
                imageUrls: _galleryUrls,
                imageHeight: imageHeight,
                pageController: _pageController,
                currentPage: _currentPage,
                onPageChanged: (index) {
                  if (!mounted) return;
                  setState(() => _currentPage = index);
                  widget.onGalleryPageChange?.call(index);
                },
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              Text(
                widget.item.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (widget.item.brand != null &&
                  widget.item.brand!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    widget.item.brand!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                ),
              const SizedBox(height: AppTheme.spacingUnit / 2),
              Text(
                _formatPrice(
                    widget.item.priceAmount, widget.item.priceCurrency),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.primaryAction,
                    ),
              ),
              if (visibleDescription != null) ...[
                const SizedBox(height: AppTheme.spacingUnit),
                Text(
                  visibleDescription,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.45,
                      ),
                ),
                if (hasLongDescription)
                  TextButton(
                    onPressed: () => setState(
                        () => _showFullDescription = !_showFullDescription),
                    child:
                        Text(_showFullDescription ? 'Show less' : 'Show more'),
                  ),
              ],
              if (widget.item.dimensionsCm != null) ...[
                const SizedBox(height: AppTheme.spacingUnit / 2),
                Text(
                  'Dimensions: '
                  '${_formatDimensionValue(widget.item.dimensionsCm!['w'])} x '
                  '${_formatDimensionValue(widget.item.dimensionsCm!['h'])} x '
                  '${_formatDimensionValue(widget.item.dimensionsCm!['d'])} cm',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (widget.item.material != null)
                Text(
                  'Material: ${widget.item.material}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              if (widget.item.deliveryComplexity != null)
                Text(
                  'Delivery: ${widget.item.deliveryComplexity}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              // Rich furniture specifications section
              if (widget.item.hasSpecs) ...[
                const SizedBox(height: AppTheme.spacingUnit * 1.5),
                Text(
                  'Specifikationer',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppTheme.spacingUnit / 2),
                _SpecificationsTable(item: widget.item),
              ],
              if (widget.item.primaryCategory != null ||
                  widget.item.sofaTypeShape != null ||
                  widget.item.sofaFunction != null ||
                  widget.item.seatCountBucket != null ||
                  (widget.item.environment != null &&
                      widget.item.environment != 'unknown') ||
                  widget.item.subCategory != null ||
                  widget.item.roomTypes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spacingUnit),
                  child: Wrap(
                    spacing: AppTheme.spacingUnit / 2,
                    runSpacing: AppTheme.spacingUnit / 2,
                    children: [
                      if (widget.item.primaryCategory != null)
                        Chip(
                          label: Text(_primaryCategoryDisplayLabel(
                              widget.item.primaryCategory!)),
                          backgroundColor:
                              AppTheme.primaryAction.withValues(alpha: 0.12),
                          labelStyle:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.primaryAction,
                                  ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      if (widget.item.sofaTypeShape != null)
                        Chip(
                          label: Text(_sofaShapeDisplayLabel(
                              widget.item.sofaTypeShape!)),
                          backgroundColor:
                              AppTheme.surfaceVariant.withValues(alpha: 0.9),
                          labelStyle:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      if (widget.item.sofaFunction != null)
                        Chip(
                          label: Text(_sofaFunctionDisplayLabel(
                              widget.item.sofaFunction!)),
                          backgroundColor:
                              AppTheme.surfaceVariant.withValues(alpha: 0.9),
                          labelStyle:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      if (widget.item.seatCountBucket != null)
                        Chip(
                          label: Text(_seatBucketDisplayLabel(
                              widget.item.seatCountBucket!)),
                          backgroundColor:
                              AppTheme.surfaceVariant.withValues(alpha: 0.9),
                          labelStyle:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      if (widget.item.environment != null &&
                          widget.item.environment != 'unknown')
                        Chip(
                          label: Text(_environmentDisplayLabel(
                              widget.item.environment!)),
                          backgroundColor:
                              AppTheme.surfaceVariant.withValues(alpha: 0.9),
                          labelStyle:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      if (widget.item.subCategory != null)
                        Chip(
                          label: Text(
                              _subCatDisplayLabel(widget.item.subCategory!)),
                          backgroundColor:
                              AppTheme.primaryAction.withValues(alpha: 0.1),
                          labelStyle:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.primaryAction,
                                  ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ...widget.item.roomTypes.map(
                        (roomType) => Chip(
                          label: Text(_roomTypeDisplayLabel(roomType)),
                          backgroundColor:
                              AppTheme.textSecondary.withValues(alpha: 0.1),
                          labelStyle:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.item.lastUpdatedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spacingUnit / 2),
                  child: Text(
                    'Last updated: '
                    '${widget.item.lastUpdatedAt!.toIso8601String().split('T').first}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: AppTheme.spacingUnit * 2),
              Row(
                children: [
                  if (widget.onToggleLike != null)
                    Padding(
                      padding:
                          const EdgeInsets.only(right: AppTheme.spacingUnit),
                      child: IconButton.filled(
                        onPressed: _isTogglingLike ? null : _toggleLike,
                        icon: _isTogglingLike
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: _isLiked ? AppTheme.positiveLike : null,
                              ),
                        tooltip:
                            _isLiked ? 'Remove from likes' : 'Add to likes',
                        style: IconButton.styleFrom(
                          backgroundColor: _isLiked
                              ? AppTheme.positiveLike.withValues(alpha: 0.15)
                              : AppTheme.surface,
                          side: BorderSide(
                            color: _isLiked
                                ? AppTheme.positiveLike
                                : AppTheme.textCaption.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: AppTheme.spacingUnit),
                    child: IconButton.filled(
                      onPressed: _shareItem,
                      icon: const Icon(Icons.share_outlined),
                      tooltip: 'Share',
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.surface,
                        side: BorderSide(
                          color: AppTheme.textCaption.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        widget.onOutboundClick?.call(widget.item);
                        _openOutbound(context);
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('View on site'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOutbound(BuildContext context) async {
    Navigator.of(context).pop();
    widget.onOutboundRedirectStart?.call(widget.item);
    final url = Uri.parse(ApiClient.goUrl(widget.item.id));
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        widget.onOutboundRedirectSuccess?.call(widget.item);
      } else {
        widget.onOutboundRedirectFail
            ?.call(widget.item, 'canLaunchUrl returned false');
      }
    } catch (e) {
      widget.onOutboundRedirectFail?.call(widget.item, e);
    }
  }

  Future<void> _shareItem() async {
    widget.onShare?.call(widget.item);
    final shareUrl = ApiClient.goUrl(widget.item.id);
    await Share.share(
      '${widget.item.title}\n$shareUrl',
      subject: widget.item.title,
    );
  }
}

class _DetailGallery extends StatelessWidget {
  const _DetailGallery({
    required this.imageUrls,
    required this.imageHeight,
    required this.pageController,
    required this.currentPage,
    required this.onPageChanged,
  });

  final List<String> imageUrls;
  final double imageHeight;
  final PageController pageController;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) {
      return _GalleryPlaceholder(imageHeight: imageHeight);
    }

    if (imageUrls.length == 1) {
      return _DetailGalleryImage(
        imageHeight: imageHeight,
        rawUrl: imageUrls.first,
      );
    }

    return Column(
      children: [
        SizedBox(
          height: imageHeight,
          child: PageView.builder(
            controller: pageController,
            allowImplicitScrolling: true,
            itemCount: imageUrls.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) => _DetailGalleryImage(
              imageHeight: imageHeight,
              rawUrl: imageUrls[index],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingUnit / 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            imageUrls.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: index == currentPage ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: index == currentPage
                    ? AppTheme.primaryAction.withValues(alpha: 0.9)
                    : AppTheme.textCaption.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailGalleryImage extends StatelessWidget {
  const _DetailGalleryImage({
    required this.imageHeight,
    required this.rawUrl,
  });

  final double imageHeight;
  final String rawUrl;

  @override
  Widget build(BuildContext context) {
    final backgroundUrl =
        ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.thumbnail);
    final detailUrl = ApiClient.proxyImageUrl(rawUrl, width: ImageWidth.detail);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: SizedBox(
        height: imageHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.scale(
              scale: 1.08,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 16,
                  sigmaY: 16,
                  tileMode: TileMode.decal,
                ),
                child: CachedNetworkImage(
                  imageUrl: backgroundUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  placeholder: (_, __) =>
                      _GalleryPlaceholder(imageHeight: imageHeight),
                  errorWidget: (_, __, ___) =>
                      _GalleryPlaceholder(imageHeight: imageHeight),
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
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit / 2),
              child: CachedNetworkImage(
                imageUrl: detailUrl,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                memCacheWidth: 1200,
                placeholder: (_, __) =>
                    _GalleryPlaceholder(imageHeight: imageHeight),
                errorWidget: (_, __, ___) =>
                    _GalleryPlaceholder(imageHeight: imageHeight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryPlaceholder extends StatelessWidget {
  const _GalleryPlaceholder({required this.imageHeight});

  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: imageHeight,
      color: AppTheme.surfaceVariant,
      child: const Center(
        child: Icon(
          Icons.image_not_supported,
          size: 64,
          color: AppTheme.textCaption,
        ),
      ),
    );
  }
}

/// Clean key-value table showing rich furniture specifications.
class _SpecificationsTable extends StatelessWidget {
  const _SpecificationsTable({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final specs = <String, String>{};
    if (item.seatCount != null) specs['Antal sitsar'] = '${item.seatCount}';
    if (item.seatHeightCm != null) {
      specs['Sitthöjd'] = '${item.seatHeightCm!.toStringAsFixed(0)} cm';
    }
    if (item.seatDepthCm != null) {
      specs['Sittdjup'] = '${item.seatDepthCm!.toStringAsFixed(0)} cm';
    }
    if (item.seatWidthCm != null) {
      specs['Sittbredd'] = '${item.seatWidthCm!.toStringAsFixed(0)} cm';
    }
    if (item.weightKg != null) {
      specs['Vikt'] = '${item.weightKg!.toStringAsFixed(1)} kg';
    }
    if (item.frameMaterial != null) specs['Stomme'] = item.frameMaterial!;
    if (item.coverMaterial != null) specs['Klädsel'] = item.coverMaterial!;
    if (item.legMaterial != null) specs['Ben'] = item.legMaterial!;
    if (item.cushionFilling != null) {
      specs['Kuddfyllning'] = item.cushionFilling!;
    }

    if (specs.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.spacingUnit),
      ),
      padding: const EdgeInsets.all(AppTheme.spacingUnit),
      child: Column(
        children: specs.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textCaption,
                        ),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
