import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/auth_provider.dart';
import '../../data/deck_provider.dart';
import '../../data/event_tracker.dart';
import '../../data/session_provider.dart' show sessionIdProvider, currentSurfaceProvider;
import '../../data/models/item.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/detail_sheet.dart';

// #region agent log
void _agentLogLikes(String location, String message, Map<String, dynamic> data) {
  if (!kDebugMode) return;
  try {
    final payload = {'location': location, 'message': message, 'data': data, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'sessionId': 'debug-session', 'hypothesisId': 'H7'};
    Dio()
        .post(
          'http://127.0.0.1:7245/ingest/ddc9e3c2-ad47-4244-9d77-ce2efa8256ba',
          data: payload,
          options: Options(sendTimeout: const Duration(milliseconds: 500), receiveTimeout: const Duration(milliseconds: 500)),
        )
        .catchError((_) => Future.value(Response(requestOptions: RequestOptions(path: 'agent_ingest'))));
  } catch (_) {}
}
// #endregion

class LikesScreen extends ConsumerStatefulWidget {
  const LikesScreen({super.key});

  @override
  ConsumerState<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends ConsumerState<LikesScreen> {
  bool _gridView = true;
  final Set<String> _selectedIds = {};
  bool _didEmitLikesOpen = false;

  Future<void> _openDetailWithLogging(BuildContext context, Item item) async {
    final tracker = ref.read(eventTrackerProvider);
    final sessionId = ref.read(sessionIdProvider);
    tracker.track('detail_open', {
      'item': {'itemId': item.id, 'source': 'likes'},
      'surface': {'name': 'detail'},
    });
    final started = DateTime.now();
    await showDetailSheet(
      context,
      item,
      goBaseUrl: Uri.base.origin,
      onOutboundClick: (i) => _trackOutbound(tracker, i),
      onScroll: () => tracker.track('detail_scroll', {'item': {'itemId': item.id}}),
      onGalleryPageChange: (i) => tracker.track('detail_gallery_interaction', {
        'item': {'itemId': item.id},
        'ext': {'imageIndex': i},
      }),
      onOutboundRedirectStart: (i) {
        final domain = i.outboundUrl != null ? Uri.tryParse(i.outboundUrl!)?.host : null;
        tracker.track('outbound_redirect_start', {
          'item': {'itemId': i.id},
          'outbound': {'destinationDomain': domain ?? 'unknown'},
        });
      },
      onOutboundRedirectSuccess: (i) {
        final domain = i.outboundUrl != null ? Uri.tryParse(i.outboundUrl!)?.host : null;
        tracker.track('outbound_redirect_success', {
          'item': {'itemId': i.id},
          'outbound': {'destinationDomain': domain ?? 'unknown'},
        });
      },
      onOutboundRedirectFail: (i, e) {
        final domain = i.outboundUrl != null ? Uri.tryParse(i.outboundUrl!)?.host : null;
        tracker.track('outbound_redirect_fail', {
          'item': {'itemId': i.id},
          'outbound': {'destinationDomain': domain ?? 'unknown'},
          'error': {'errorType': e.runtimeType.toString()},
        });
      },
      // Items in likes screen are already liked
      isLiked: true,
      onToggleLike: sessionId != null
          ? (i) async {
              final liked = await toggleLikeWithTracking(
                ref,
                sessionId: sessionId,
                itemId: i.id,
              );
              // Refresh likes list after toggle
              ref.invalidate(likesListProvider);
              // Remove from selection if unliked
              if (!liked && _selectedIds.contains(i.id)) {
                setState(() => _selectedIds.remove(i.id));
              }
              return liked;
            }
          : null,
    );
    final timeViewedMs = DateTime.now().difference(started).inMilliseconds;
    if (context.mounted) {
      tracker.track('detail_close', {
        'item': {'itemId': item.id},
        'ext': {'durationMs': timeViewedMs},
      });
    }
  }

  void _trackOutbound(EventTracker tracker, Item item) {
    final domain = item.outboundUrl != null ? Uri.tryParse(item.outboundUrl!)?.host : null;
    tracker.track('outbound_click', {
      'item': {'itemId': item.id},
      'outbound': {'destinationDomain': domain ?? 'unknown'},
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(currentSurfaceProvider.notifier).state = {'name': 'likes'};
    });
    final likesAsync = ref.watch(likesListProvider);
    final sessionId = ref.watch(sessionIdProvider);

    if (sessionId != null && !_didEmitLikesOpen) {
      _didEmitLikesOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // #region agent log
          _agentLogLikes('likes_screen.dart:build', 'likes_open_emitting', {});
          // #endregion
          ref.read(eventTrackerProvider).track('likes_open', {});
        }
      });
    }

    return AppShell(
      title: 'Likes',
      body: likesAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: AppTheme.textCaption),
                  const SizedBox(height: AppTheme.spacingUnit),
                  Text('No likes yet', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppTheme.spacingUnit),
                  Text('Swipe right to save items here.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
                  const SizedBox(height: AppTheme.spacingUnit * 2),
                  ElevatedButton(
                    onPressed: () => context.go('/deck'),
                    child: const Text('Back to deck'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(_gridView ? Icons.view_list : Icons.grid_view),
                    onPressed: () => setState(() => _gridView = !_gridView),
                    tooltip: _gridView ? 'List view' : 'Grid view',
                  ),
                ],
              ),
              Expanded(
                child: _gridView
                    ? GridView.builder(
                        padding: const EdgeInsets.all(AppTheme.spacingUnit),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: AppTheme.spacingUnit,
                          mainAxisSpacing: AppTheme.spacingUnit,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) => _LikeCard(
                          item: items[i],
                          selected: _selectedIds.contains(items[i].id),
                          onTap: () => _openDetailWithLogging(context, items[i]),
                          onLongPress: () => setState(() {
                            if (_selectedIds.contains(items[i].id)) {
                              _selectedIds.remove(items[i].id);
                            } else {
                              _selectedIds.add(items[i].id);
                            }
                          }),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppTheme.spacingUnit),
                        itemCount: items.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
                          child: _LikeListTile(
                            item: items[i],
                            selected: _selectedIds.contains(items[i].id),
                            onTap: () => _openDetailWithLogging(context, items[i]),
                            onLongPress: () => setState(() {
                              if (_selectedIds.contains(items[i].id)) {
                                _selectedIds.remove(items[i].id);
                              } else {
                                _selectedIds.add(items[i].id);
                              }
                            }),
                          ),
                        ),
                      ),
              ),
              if (_selectedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  child: Row(
                    children: [
                      if (_selectedIds.length >= 2 && _selectedIds.length <= 4)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: AppTheme.spacingUnit / 2),
                            child: OutlinedButton.icon(
                              onPressed: () => context.push('/compare?ids=${_selectedIds.join(",")}'),
                              icon: const Icon(Icons.compare_arrows),
                              label: const Text('Compare'),
                            ),
                          ),
                        ),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _createDecisionRoom(context, _selectedIds.toList()),
                          icon: const Icon(Icons.people),
                          label: const Text('Decision Room'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _createDecisionRoom(BuildContext context, List<String> itemIds) async {
    final authState = ref.read(authProvider);
    final tracker = ref.read(eventTrackerProvider);

    // Check if user is authenticated
    if (!authState.isAuthenticated) {
      final shouldSignIn = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in required'),
          content: const Text('You need to sign in to create a Decision Room and collaborate with others.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );

      if (shouldSignIn == true && context.mounted) {
        context.go('/auth/login', extra: '/likes');
      }
      return;
    }

    // Get the auth token
    final token = await ref.read(authProvider.notifier).getIdToken();
    if (token == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get authentication token')),
        );
      }
      return;
    }

    // Ask for optional room title
    String? title;
    if (context.mounted) {
      final titleController = TextEditingController();
      title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Name your Decision Room'),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(
              hintText: 'e.g., "Our new sofa" (optional)',
              labelText: 'Room name',
            ),
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, titleController.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      );
    }

    if (!context.mounted) return;

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Creating Decision Room...')),
    );

    try {
      final client = ref.read(apiClientProvider);
      final res = await client.createDecisionRoom(
        token: token,
        itemIds: itemIds,
        title: title?.isNotEmpty == true ? title : null,
      );

      final roomId = res['id'] as String?;
      final shareUrl = res['shareUrl'] as String?;

      if (roomId == null) {
        throw Exception('Failed to create room');
      }

      // Track event
      tracker.track('decisionroom_create', {
        'items': {'itemIds': itemIds, 'count': itemIds.length},
        'room': {'roomId': roomId},
      });

      // Clear selection
      setState(() => _selectedIds.clear());

      // Share the room
      final url = shareUrl ?? '${Uri.base.origin}/r/$roomId';
      await Share.share(
        'Help me decide! Vote on sofas here: $url',
        subject: 'Swiper Decision Room',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Decision Room created!'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => context.go('/r/$roomId'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create room: $e')),
        );
      }
    }
  }
}

/// Card widget for grid view in Likes screen
class _LikeCard extends StatelessWidget {
  const _LikeCard({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Item item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: selected ? const BorderSide(color: AppTheme.primaryAction, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: item.firstImageUrl != null
                  ? Image.network(ApiClient.proxyImageUrl(item.firstImageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported, color: AppTheme.textCaption))
                  : Container(color: AppTheme.background, child: Icon(Icons.image_not_supported, color: AppTheme.textCaption)),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit / 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.primaryAction)),
                  if (item.brand != null) Text(item.brand!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// List tile widget for list view in Likes screen (uses fixed height, not Expanded)
class _LikeListTile extends StatelessWidget {
  const _LikeListTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Item item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: selected ? const BorderSide(color: AppTheme.primaryAction, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 100,
                child: item.firstImageUrl != null
                    ? Image.network(
                        ApiClient.proxyImageUrl(item.firstImageUrl!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppTheme.background,
                          child: Icon(Icons.image_not_supported, color: AppTheme.textCaption),
                        ),
                      )
                    : Container(
                        color: AppTheme.background,
                        child: Icon(Icons.image_not_supported, color: AppTheme.textCaption),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.primaryAction),
                      ),
                      if (item.brand != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.brand!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: const Icon(Icons.check_circle, color: AppTheme.primaryAction),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
