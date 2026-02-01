import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../data/models/item.dart';

void showDetailSheet(BuildContext context, Item item, {String? goBaseUrl}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 1,
      expand: false,
      builder: (context, scrollController) => DetailSheetContent(
        item: item,
        scrollController: scrollController,
        goBaseUrl: goBaseUrl,
      ),
    ),
  );
}

class DetailSheetContent extends StatelessWidget {
  const DetailSheetContent({
    super.key,
    required this.item,
    required this.scrollController,
    this.goBaseUrl,
  });

  final Item item;
  final ScrollController scrollController;
  final String? goBaseUrl;

  @override
  Widget build(BuildContext context) {
    List<String> imageUrls = item.images.isNotEmpty
        ? item.images.map((e) => e.url).toList()
        : (item.firstImageUrl != null ? [item.firstImageUrl!] : <String>[]);
    if (imageUrls.isEmpty) imageUrls = [''];

    return SingleChildScrollView(
      controller: scrollController,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 280,
              child: PageView.builder(
                itemCount: imageUrls.length,
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
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                      errorWidget: (_, __, ___) => Icon(Icons.broken_image, size: 64, color: AppTheme.textCaption),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            Text(item.title, style: Theme.of(context).textTheme.titleLarge),
            if (item.brand != null) Text(item.brand!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.spacingUnit),
            Text('${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.primaryAction)),
            if (item.dimensionsCm != null) ...[
              const SizedBox(height: AppTheme.spacingUnit),
              Text('Dimensions: ${item.dimensionsCm!['w']} × ${item.dimensionsCm!['h']} × ${item.dimensionsCm!['d']} cm', style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (item.material != null) Text('Material: ${item.material}', style: Theme.of(context).textTheme.bodyMedium),
            if (item.deliveryComplexity != null) Text('Delivery: ${item.deliveryComplexity}', style: Theme.of(context).textTheme.bodyMedium),
            if (item.lastUpdatedAt != null) Text('Last updated: ${item.lastUpdatedAt!.toIso8601String().split('T').first}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.spacingUnit * 2),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openOutbound(context),
                icon: const Icon(Icons.open_in_new),
                label: const Text('View on site'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOutbound(BuildContext context) async {
    Navigator.of(context).pop();
    final base = goBaseUrl ?? Uri.base.origin;
    final url = Uri.parse('$base/go/${item.id}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
