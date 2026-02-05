import 'item.dart';
import '../gold_card_provider.dart';

/// Type of deck item
enum DeckItemType {
  product,
  goldCardVisual,
  goldCardBudget,
}

/// A unified model for items in the swipe deck.
/// Can be either a regular product item or a gold card.
class DeckItem {
  const DeckItem._({
    required this.type,
    this.item,
    this.curatedSofas,
  });

  /// Create a product deck item
  factory DeckItem.product(Item item) {
    return DeckItem._(type: DeckItemType.product, item: item);
  }

  /// Create a visual gold card deck item
  factory DeckItem.goldCardVisual(List<CuratedSofa> sofas) {
    return DeckItem._(type: DeckItemType.goldCardVisual, curatedSofas: sofas);
  }

  /// Create a budget gold card deck item
  factory DeckItem.goldCardBudget() {
    return const DeckItem._(type: DeckItemType.goldCardBudget);
  }

  final DeckItemType type;
  final Item? item;
  final List<CuratedSofa>? curatedSofas;

  /// Unique ID for this deck item
  String get id {
    switch (type) {
      case DeckItemType.product:
        return item!.id;
      case DeckItemType.goldCardVisual:
        return '__gold_card_visual__';
      case DeckItemType.goldCardBudget:
        return '__gold_card_budget__';
    }
  }

  /// Whether this is a gold card
  bool get isGoldCard =>
      type == DeckItemType.goldCardVisual || type == DeckItemType.goldCardBudget;

  /// Whether this is a product
  bool get isProduct => type == DeckItemType.product;
}
