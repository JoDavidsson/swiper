import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models/item.dart';

Future<void> showDetailSheet(
  BuildContext context,
  Item item, {
  String? goBaseUrl,
  void Function(Item item)? onOutboundClick,
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _isLiked = widget.isLiked;
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _animateIn = true);
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
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
    List<String> imageUrls = widget.item.images.isNotEmpty
        ? widget.item.images.map((e) => e.url).toList()
        : (widget.item.firstImageUrl != null ? [widget.item.firstImageUrl!] : <String>[]);
    if (imageUrls.isEmpty) imageUrls = [''];
    final screenHeight = MediaQuery.of(context).size.height;
    final imageHeight = (screenHeight * 0.45).clamp(240.0, 420.0);

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
              SizedBox(
                height: imageHeight,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: imageUrls.length,
                  onPageChanged: widget.onGalleryPageChange,
                  itemBuilder: (context, i) {
                    final url = imageUrls[i];
                    if (url.isEmpty) {
                      return Container(
                        color: AppTheme.textCaption.withValues(alpha: 0.2),
                        child: Icon(Icons.image_not_supported, size: 64, color: AppTheme.textCaption),
                      );
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      child: CachedNetworkImage(
                        imageUrl: ApiClient.proxyImageUrl(url),
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                        errorWidget: (_, __, ___) => Icon(Icons.broken_image, size: 64, color: AppTheme.textCaption),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              Text(widget.item.title, style: Theme.of(context).textTheme.titleLarge),
              if (widget.item.brand != null) Text(widget.item.brand!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppTheme.spacingUnit),
              Text(
                '${widget.item.priceAmount.toStringAsFixed(0)} ${widget.item.priceCurrency}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.primaryAction),
              ),
              if (widget.item.dimensionsCm != null) ...[
                const SizedBox(height: AppTheme.spacingUnit),
                Text(
                  'Dimensions: ${widget.item.dimensionsCm!['w']} × ${widget.item.dimensionsCm!['h']} × ${widget.item.dimensionsCm!['d']} cm',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (widget.item.material != null) Text('Material: ${widget.item.material}', style: Theme.of(context).textTheme.bodyMedium),
              if (widget.item.deliveryComplexity != null) Text('Delivery: ${widget.item.deliveryComplexity}', style: Theme.of(context).textTheme.bodyMedium),
              if (widget.item.lastUpdatedAt != null)
                Text('Last updated: ${widget.item.lastUpdatedAt!.toIso8601String().split('T').first}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppTheme.spacingUnit * 2),
              Row(
                children: [
                  if (widget.onToggleLike != null)
                    Padding(
                      padding: const EdgeInsets.only(right: AppTheme.spacingUnit),
                      child: IconButton.filled(
                        onPressed: _isTogglingLike ? null : _toggleLike,
                        icon: _isTogglingLike
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _isLiked ? Icons.favorite : Icons.favorite_border,
                                color: _isLiked ? AppTheme.positiveLike : null,
                              ),
                        tooltip: _isLiked ? 'Remove from likes' : 'Add to likes',
                        style: IconButton.styleFrom(
                          backgroundColor: _isLiked
                              ? AppTheme.positiveLike.withValues(alpha: 0.15)
                              : AppTheme.surface,
                          side: BorderSide(
                            color: _isLiked ? AppTheme.positiveLike : AppTheme.textCaption.withValues(alpha: 0.3),
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
    final base = widget.goBaseUrl ?? Uri.base.origin;
    final url = Uri.parse('$base/go/${widget.item.id}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        widget.onOutboundRedirectSuccess?.call(widget.item);
      } else {
        widget.onOutboundRedirectFail?.call(widget.item, 'canLaunchUrl returned false');
      }
    } catch (e) {
      widget.onOutboundRedirectFail?.call(widget.item, e);
    }
  }
}
