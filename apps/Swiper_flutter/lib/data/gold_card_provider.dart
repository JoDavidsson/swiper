import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'api_providers.dart';

/// Keys for gold card state in Hive
const String kGoldCardVisualCompleted = 'gold_card_visual_completed';
const String kGoldCardVisualSkipCount = 'gold_card_visual_skip_count';
const String kGoldCardVisualLastSkipSwipe = 'gold_card_visual_last_skip_swipe';
const String kGoldCardBudgetCompleted = 'gold_card_budget_completed';
const String kGoldCardBudgetSkipCount = 'gold_card_budget_skip_count';
const String kGoldCardBudgetLastSkipSwipe = 'gold_card_budget_last_skip_swipe';
const String kGoldCardPickedItemIds = 'gold_card_picked_item_ids';
const String kGoldCardBudgetMin = 'gold_card_budget_min';
const String kGoldCardBudgetMax = 'gold_card_budget_max';
const String kTotalRightSwipes = 'gold_card_total_right_swipes';

/// Gold card state for progressive onboarding
class GoldCardState {
  const GoldCardState({
    this.visualCompleted = false,
    this.visualSkipCount = 0,
    this.visualLastSkipSwipe = 0,
    this.budgetCompleted = false,
    this.budgetSkipCount = 0,
    this.budgetLastSkipSwipe = 0,
    this.pickedItemIds = const [],
    this.budgetMin = 0,
    this.budgetMax = 50000,
    this.totalRightSwipes = 0,
  });

  final bool visualCompleted;
  final int visualSkipCount;
  final int visualLastSkipSwipe;
  final bool budgetCompleted;
  final int budgetSkipCount;
  final int budgetLastSkipSwipe;
  final List<String> pickedItemIds;
  final double budgetMin;
  final double budgetMax;
  final int totalRightSwipes;

  /// Should we show the visual gold card?
  /// Show after first right swipe, unless completed or skipped 2+ times
  bool get shouldShowVisualCard {
    if (visualCompleted) return false;
    if (visualSkipCount >= 2) return false;
    // Show after first right swipe
    if (totalRightSwipes < 1) return false;
    // If skipped, wait 20 swipes before showing again
    if (visualSkipCount > 0 && totalRightSwipes < visualLastSkipSwipe + 20) return false;
    return true;
  }

  /// Should we show the budget gold card?
  /// Show immediately after visual card is completed
  bool get shouldShowBudgetCard {
    if (!visualCompleted) return false;
    if (budgetCompleted) return false;
    if (budgetSkipCount >= 2) return false;
    // If skipped, wait 20 swipes before showing again
    if (budgetSkipCount > 0 && totalRightSwipes < budgetLastSkipSwipe + 20) return false;
    return true;
  }

  GoldCardState copyWith({
    bool? visualCompleted,
    int? visualSkipCount,
    int? visualLastSkipSwipe,
    bool? budgetCompleted,
    int? budgetSkipCount,
    int? budgetLastSkipSwipe,
    List<String>? pickedItemIds,
    double? budgetMin,
    double? budgetMax,
    int? totalRightSwipes,
  }) {
    return GoldCardState(
      visualCompleted: visualCompleted ?? this.visualCompleted,
      visualSkipCount: visualSkipCount ?? this.visualSkipCount,
      visualLastSkipSwipe: visualLastSkipSwipe ?? this.visualLastSkipSwipe,
      budgetCompleted: budgetCompleted ?? this.budgetCompleted,
      budgetSkipCount: budgetSkipCount ?? this.budgetSkipCount,
      budgetLastSkipSwipe: budgetLastSkipSwipe ?? this.budgetLastSkipSwipe,
      pickedItemIds: pickedItemIds ?? this.pickedItemIds,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      totalRightSwipes: totalRightSwipes ?? this.totalRightSwipes,
    );
  }
}

/// Provider for gold card state
final goldCardProvider = StateNotifierProvider<GoldCardNotifier, GoldCardState>((ref) {
  return GoldCardNotifier();
});

class GoldCardNotifier extends StateNotifier<GoldCardState> {
  GoldCardNotifier() : super(const GoldCardState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      state = GoldCardState(
        visualCompleted: box.get(kGoldCardVisualCompleted, defaultValue: false) as bool,
        visualSkipCount: box.get(kGoldCardVisualSkipCount, defaultValue: 0) as int,
        visualLastSkipSwipe: box.get(kGoldCardVisualLastSkipSwipe, defaultValue: 0) as int,
        budgetCompleted: box.get(kGoldCardBudgetCompleted, defaultValue: false) as bool,
        budgetSkipCount: box.get(kGoldCardBudgetSkipCount, defaultValue: 0) as int,
        budgetLastSkipSwipe: box.get(kGoldCardBudgetLastSkipSwipe, defaultValue: 0) as int,
        pickedItemIds: (box.get(kGoldCardPickedItemIds) as List?)?.cast<String>() ?? [],
        budgetMin: (box.get(kGoldCardBudgetMin, defaultValue: 0.0) as num).toDouble(),
        budgetMax: (box.get(kGoldCardBudgetMax, defaultValue: 50000.0) as num).toDouble(),
        totalRightSwipes: box.get(kTotalRightSwipes, defaultValue: 0) as int,
      );
    } catch (_) {
      state = const GoldCardState();
    }
  }

  /// Called when user swipes right on a regular item
  Future<void> incrementRightSwipes() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      final newCount = state.totalRightSwipes + 1;
      await box.put(kTotalRightSwipes, newCount);
      state = state.copyWith(totalRightSwipes: newCount);
    } catch (_) {}
  }

  /// Called when user completes the visual gold card
  Future<void> completeVisualCard(List<String> pickedItemIds) async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      await box.put(kGoldCardVisualCompleted, true);
      await box.put(kGoldCardPickedItemIds, pickedItemIds);
      state = state.copyWith(
        visualCompleted: true,
        pickedItemIds: pickedItemIds,
      );
    } catch (_) {}
  }

  /// Called when user skips the visual gold card
  Future<void> skipVisualCard() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      final newSkipCount = state.visualSkipCount + 1;
      await box.put(kGoldCardVisualSkipCount, newSkipCount);
      await box.put(kGoldCardVisualLastSkipSwipe, state.totalRightSwipes);
      state = state.copyWith(
        visualSkipCount: newSkipCount,
        visualLastSkipSwipe: state.totalRightSwipes,
      );
    } catch (_) {}
  }

  /// Called when user completes the budget gold card
  Future<void> completeBudgetCard(double budgetMin, double budgetMax) async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      await box.put(kGoldCardBudgetCompleted, true);
      await box.put(kGoldCardBudgetMin, budgetMin);
      await box.put(kGoldCardBudgetMax, budgetMax);
      state = state.copyWith(
        budgetCompleted: true,
        budgetMin: budgetMin,
        budgetMax: budgetMax,
      );
    } catch (_) {}
  }

  /// Called when user skips the budget gold card
  Future<void> skipBudgetCard() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      final newSkipCount = state.budgetSkipCount + 1;
      await box.put(kGoldCardBudgetSkipCount, newSkipCount);
      await box.put(kGoldCardBudgetLastSkipSwipe, state.totalRightSwipes);
      state = state.copyWith(
        budgetSkipCount: newSkipCount,
        budgetLastSkipSwipe: state.totalRightSwipes,
      );
    } catch (_) {}
  }

  /// Reset gold card state (for testing or "start over")
  Future<void> reset() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      await box.delete(kGoldCardVisualCompleted);
      await box.delete(kGoldCardVisualSkipCount);
      await box.delete(kGoldCardVisualLastSkipSwipe);
      await box.delete(kGoldCardBudgetCompleted);
      await box.delete(kGoldCardBudgetSkipCount);
      await box.delete(kGoldCardBudgetLastSkipSwipe);
      await box.delete(kGoldCardPickedItemIds);
      await box.delete(kGoldCardBudgetMin);
      await box.delete(kGoldCardBudgetMax);
      await box.delete(kTotalRightSwipes);
      state = const GoldCardState();
    } catch (_) {}
  }
}

/// Curated sofa for the visual gold card
class CuratedSofa {
  const CuratedSofa({
    required this.id,
    required this.imageUrl,
    this.styleTags = const [],
  });

  final String id;
  final String imageUrl;
  final List<String> styleTags;

  factory CuratedSofa.fromJson(Map<String, dynamic> json) {
    return CuratedSofa(
      id: json['id'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      styleTags: (json['styleTags'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// Provider for curated sofas from API
final curatedSofasProvider = FutureProvider<List<CuratedSofa>>((ref) async {
  final client = ref.watch(apiClientProvider);
  try {
    final data = await client.getCuratedSofas();
    return data.map((e) => CuratedSofa.fromJson(e)).toList();
  } catch (_) {
    // Return empty list on error - UI will handle gracefully
    return [];
  }
});
