import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/deck_provider.dart';
import '../../data/event_tracker.dart';
import '../../data/locale_provider.dart';
import '../../data/session_provider.dart' show currentSurfaceProvider;
import '../../data/models/item.dart';
import '../../shared/widgets/detail_sheet.dart';

class SharedShortlistScreen extends ConsumerStatefulWidget {
  const SharedShortlistScreen({super.key, required this.shareToken});

  final String shareToken;

  @override
  ConsumerState<SharedShortlistScreen> createState() =>
      _SharedShortlistScreenState();
}

class _SharedShortlistScreenState extends ConsumerState<SharedShortlistScreen> {
  bool _didEmitShareLinkLandingView = false;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final client = ref.watch(apiClientProvider);
    return FutureBuilder<Map<String, dynamic>>(
      future: client.getShortlistByToken(widget.shareToken),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(title: Text(strings.sharedShortlist)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        final itemsRaw = data['items'] as List? ?? [];
        final items = itemsRaw
            .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        if (items.isEmpty) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(title: Text(strings.sharedShortlist)),
            body: Center(child: Text(strings.shortlistEmpty)),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted)
            ref.read(currentSurfaceProvider.notifier).state = {
              'name': 'shortlist'
            };
        });
        if (!_didEmitShareLinkLandingView) {
          _didEmitShareLinkLandingView = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final tracker = ref.read(eventTrackerProvider);
              tracker.track('share_link_landing_view', {
                'share': {'linkType': 'shortlist', 'linkId': widget.shareToken},
              });
              tracker.track('deep_link_open', {
                'surface': {'name': 'share'},
                'ext': {'linkType': 'shortlist', 'linkId': widget.shareToken},
              });
            }
          });
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(title: Text(strings.sharedShortlist)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${items.length} items',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppTheme.spacingUnit),
                ...items.map((item) => Card(
                      margin:
                          const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusCard)),
                      child: InkWell(
                        onTap: () async {
                          final tracker = ref.read(eventTrackerProvider);
                          tracker.track('detail_open', {
                            'item': {'itemId': item.id, 'source': 'shortlist'},
                            'surface': {'name': 'detail'},
                          });
                          final started = DateTime.now();
                          await showDetailSheet(
                            context,
                            item,
                            goBaseUrl: Uri.base.origin,
                            onOutboundClick: (i) {
                              final domain = i.outboundUrl != null
                                  ? Uri.tryParse(i.outboundUrl!)?.host
                                  : null;
                              tracker.track('outbound_click', {
                                'item': {'itemId': i.id},
                                'outbound': {
                                  'destinationDomain': domain ?? 'unknown'
                                },
                              });
                            },
                            onScroll: () => tracker.track('detail_scroll', {
                              'item': {'itemId': item.id}
                            }),
                            onGalleryPageChange: (i) =>
                                tracker.track('detail_gallery_interaction', {
                              'item': {'itemId': item.id},
                              'ext': {'imageIndex': i},
                            }),
                            onOutboundRedirectStart: (i) {
                              final domain = i.outboundUrl != null
                                  ? Uri.tryParse(i.outboundUrl!)?.host
                                  : null;
                              tracker.track('outbound_redirect_start', {
                                'item': {'itemId': i.id},
                                'outbound': {
                                  'destinationDomain': domain ?? 'unknown'
                                },
                              });
                            },
                            onOutboundRedirectSuccess: (i) {
                              final domain = i.outboundUrl != null
                                  ? Uri.tryParse(i.outboundUrl!)?.host
                                  : null;
                              tracker.track('outbound_redirect_success', {
                                'item': {'itemId': i.id},
                                'outbound': {
                                  'destinationDomain': domain ?? 'unknown'
                                },
                              });
                            },
                            onOutboundRedirectFail: (i, e) {
                              final domain = i.outboundUrl != null
                                  ? Uri.tryParse(i.outboundUrl!)?.host
                                  : null;
                              tracker.track('outbound_redirect_fail', {
                                'item': {'itemId': i.id},
                                'outbound': {
                                  'destinationDomain': domain ?? 'unknown'
                                },
                                'error': {
                                  'errorType': e.runtimeType.toString()
                                },
                              });
                            },
                          );
                          final timeViewedMs =
                              DateTime.now().difference(started).inMilliseconds;
                          if (context.mounted) {
                            tracker.track('detail_close', {
                              'item': {'itemId': item.id},
                              'ext': {'durationMs': timeViewedMs},
                            });
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spacingUnit),
                          child: Row(
                            children: [
                              if (item.firstImageUrl != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.radiusChip),
                                  child: CachedNetworkImage(
                                    imageUrl: ApiClient.proxyImageUrl(
                                        item.firstImageUrl!,
                                        width: ImageWidth.thumbnail),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: AppTheme.background,
                                      alignment: Alignment.center,
                                      child: const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) =>
                                        const Icon(Icons.image_not_supported),
                                  ),
                                )
                              else
                                const SizedBox(
                                    width: 80,
                                    height: 80,
                                    child: Icon(Icons.image_not_supported)),
                              const SizedBox(width: AppTheme.spacingUnit),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                        '${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                color: AppTheme.primaryAction)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_new),
                                onPressed: () => _openOutbound(context, item),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
                const SizedBox(height: AppTheme.spacingUnit),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/'),
                    child: Text(strings.startSwiping),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _openOutbound(BuildContext context, Item item) async {
  final url = Uri.parse(ApiClient.goUrl(item.id));
  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
