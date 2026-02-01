import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../data/deck_provider.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/swipe_deck.dart';

class DeckScreen extends ConsumerWidget {
  const DeckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deckState = ref.watch(deckItemsProvider);
    final sessionId = ref.watch(sessionIdProvider);

    return AppShell(
      title: AppConstants.appName,
      showBottomNav: true,
      body: deckState.when(
        data: (items) {
          final notifier = ref.read(deckItemsProvider.notifier);
          return SwipeDeck(
            items: items,
            sessionId: sessionId,
            goBaseUrl: Uri.base.origin,
            onSwipeLeft: (item, position) => notifier.swipe(item.id, 'left', position),
            onSwipeRight: (item, position) => notifier.swipe(item.id, 'right', position),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $e', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppTheme.spacingUnit),
              ElevatedButton(
                onPressed: () => ref.read(deckItemsProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: () => _showFiltersSheet(context),
          tooltip: 'Filters',
        ),
        IconButton(
          icon: const Icon(Icons.favorite_border),
          onPressed: () => context.push('/likes'),
          tooltip: 'Likes',
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push('/profile'),
          tooltip: 'Profile',
        ),
      ],
    );
  }

  void _showFiltersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppTheme.spacingUnit),
            const Text('Price, size, style – apply without leaving deck. (Stub)'),
          ],
        ),
      ),
    );
  }
}
