import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiper_flutter/data/models/item.dart';
import 'package:swiper_flutter/shared/widgets/swipe_deck.dart';

void main() {
  testWidgets('SwipeDeck shows empty state when no items', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SwipeDeck(
              items: const [],
              sessionId: null,
              onSwipeLeft: (_, __, {gesture = 'swipe'}) {},
              onSwipeRight: (_, __, {gesture = 'swipe'}) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('No more items'), findsOneWidget);
  });

  testWidgets('SwipeDeck shows card when items provided', (tester) async {
    final items = [
      Item(id: '1', title: 'Sofa', priceAmount: 9990, images: []),
    ];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SwipeDeck(
              items: items,
              sessionId: 's1',
              onSwipeLeft: (_, __, {gesture = 'swipe'}) {},
              onSwipeRight: (_, __, {gesture = 'swipe'}) {},
            ),
          ),
        ),
      ),
    );
    // Allow any animations/timers to settle
    await tester.pump();
    expect(find.text('Sofa'), findsOneWidget);
    // Clean up any pending timers (e.g., from image prefetching)
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
