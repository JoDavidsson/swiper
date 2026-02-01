import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiper_flutter/data/models/item.dart';
import 'package:swiper_flutter/shared/widgets/swipe_deck.dart';

void main() {
  testWidgets('SwipeDeck shows empty state when no items', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SwipeDeck(
              items: [],
              sessionId: null,
              onSwipeLeft: (_, __) {},
              onSwipeRight: (_, __) {},
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
              onSwipeLeft: (_, __) {},
              onSwipeRight: (_, __) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Sofa'), findsOneWidget);
  });
}
