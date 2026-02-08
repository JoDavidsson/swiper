import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String kOnboardingV2Version = 'onboarding_v2_version';
const String kOnboardingV2Status = 'onboarding_v2_status';
const String kOnboardingV2SceneArchetypes = 'onboarding_v2_scene_archetypes';
const String kOnboardingV2SofaVibes = 'onboarding_v2_sofa_vibes';
const String kOnboardingV2BudgetBand = 'onboarding_v2_budget_band';
const String kOnboardingV2SeatCount = 'onboarding_v2_seat_count';
const String kOnboardingV2ModularOnly = 'onboarding_v2_modular_only';
const String kOnboardingV2KidsPets = 'onboarding_v2_kids_pets';
const String kOnboardingV2SmallSpace = 'onboarding_v2_small_space';
const String kOnboardingV2LastSkipSwipe = 'onboarding_v2_last_skip_swipe';
const String kOnboardingV2HardSkipCount = 'onboarding_v2_hard_skip_count';
const String kOnboardingV2TotalRightSwipes = 'onboarding_v2_total_right_swipes';
const String kOnboardingV2CompletedAt = 'onboarding_v2_completed_at';
const String kOnboardingV2CurrentStep = 'onboarding_v2_current_step';
const String kOnboardingV2PendingSubmission =
    'onboarding_v2_pending_submission';

const int onboardingV2SchemaVersion = 2;
const int onboardingV2RepromptAfterRightSwipes = 15;
const int onboardingV2MaxHardSkips = 2;

enum OnboardingV2Status {
  notStarted,
  inProgress,
  completed,
  skipped,
}

OnboardingV2Status _statusFromString(String? value) {
  switch (value) {
    case 'in_progress':
      return OnboardingV2Status.inProgress;
    case 'completed':
      return OnboardingV2Status.completed;
    case 'skipped':
      return OnboardingV2Status.skipped;
    default:
      return OnboardingV2Status.notStarted;
  }
}

String _statusToString(OnboardingV2Status status) {
  switch (status) {
    case OnboardingV2Status.inProgress:
      return 'in_progress';
    case OnboardingV2Status.completed:
      return 'completed';
    case OnboardingV2Status.skipped:
      return 'skipped';
    case OnboardingV2Status.notStarted:
      return 'not_started';
  }
}

class OnboardingV2State {
  const OnboardingV2State({
    this.version = onboardingV2SchemaVersion,
    this.status = OnboardingV2Status.notStarted,
    this.sceneArchetypes = const [],
    this.sofaVibes = const [],
    this.budgetBand,
    this.seatCount,
    this.modularOnly,
    this.kidsPets,
    this.smallSpace,
    this.lastSkipSwipe = 0,
    this.hardSkipCount = 0,
    this.totalRightSwipes = 0,
    this.completedAt,
    this.currentStep = 0,
    this.pendingSubmission,
  });

  final int version;
  final OnboardingV2Status status;
  final List<String> sceneArchetypes;
  final List<String> sofaVibes;
  final String? budgetBand;
  final String? seatCount;
  final bool? modularOnly;
  final bool? kidsPets;
  final bool? smallSpace;
  final int lastSkipSwipe;
  final int hardSkipCount;
  final int totalRightSwipes;
  final int? completedAt;
  final int currentStep;
  final OnboardingV2PendingSubmission? pendingSubmission;

  bool get isCompleted => status == OnboardingV2Status.completed;

  bool get shouldPrompt {
    if (isCompleted) return false;
    if (hardSkipCount >= onboardingV2MaxHardSkips) return false;
    if (status == OnboardingV2Status.notStarted ||
        status == OnboardingV2Status.inProgress) {
      return true;
    }
    if (status == OnboardingV2Status.skipped) {
      return totalRightSwipes >=
          (lastSkipSwipe + onboardingV2RepromptAfterRightSwipes);
    }
    return false;
  }

  OnboardingV2State copyWith({
    int? version,
    OnboardingV2Status? status,
    List<String>? sceneArchetypes,
    List<String>? sofaVibes,
    String? budgetBand,
    bool clearBudgetBand = false,
    String? seatCount,
    bool clearSeatCount = false,
    bool? modularOnly,
    bool clearModularOnly = false,
    bool? kidsPets,
    bool clearKidsPets = false,
    bool? smallSpace,
    bool clearSmallSpace = false,
    int? lastSkipSwipe,
    int? hardSkipCount,
    int? totalRightSwipes,
    int? completedAt,
    bool clearCompletedAt = false,
    int? currentStep,
    OnboardingV2PendingSubmission? pendingSubmission,
    bool clearPendingSubmission = false,
  }) {
    return OnboardingV2State(
      version: version ?? this.version,
      status: status ?? this.status,
      sceneArchetypes: sceneArchetypes ?? this.sceneArchetypes,
      sofaVibes: sofaVibes ?? this.sofaVibes,
      budgetBand: clearBudgetBand ? null : (budgetBand ?? this.budgetBand),
      seatCount: clearSeatCount ? null : (seatCount ?? this.seatCount),
      modularOnly: clearModularOnly ? null : (modularOnly ?? this.modularOnly),
      kidsPets: clearKidsPets ? null : (kidsPets ?? this.kidsPets),
      smallSpace: clearSmallSpace ? null : (smallSpace ?? this.smallSpace),
      lastSkipSwipe: lastSkipSwipe ?? this.lastSkipSwipe,
      hardSkipCount: hardSkipCount ?? this.hardSkipCount,
      totalRightSwipes: totalRightSwipes ?? this.totalRightSwipes,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      currentStep: currentStep ?? this.currentStep,
      pendingSubmission: clearPendingSubmission
          ? null
          : (pendingSubmission ?? this.pendingSubmission),
    );
  }
}

class OnboardingV2PendingSubmission {
  const OnboardingV2PendingSubmission({
    required this.sceneArchetypes,
    required this.sofaVibes,
    this.budgetBand,
    this.seatCount,
    this.modularOnly,
    this.kidsPets,
    this.smallSpace,
    required this.queuedAt,
  });

  final List<String> sceneArchetypes;
  final List<String> sofaVibes;
  final String? budgetBand;
  final String? seatCount;
  final bool? modularOnly;
  final bool? kidsPets;
  final bool? smallSpace;
  final int queuedAt;

  Map<String, dynamic> toJson() {
    return {
      'sceneArchetypes': sceneArchetypes,
      'sofaVibes': sofaVibes,
      if (budgetBand != null) 'budgetBand': budgetBand,
      if (seatCount != null) 'seatCount': seatCount,
      if (modularOnly != null) 'modularOnly': modularOnly,
      if (kidsPets != null) 'kidsPets': kidsPets,
      if (smallSpace != null) 'smallSpace': smallSpace,
      'queuedAt': queuedAt,
    };
  }

  static OnboardingV2PendingSubmission? fromJson(dynamic value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final sceneArchetypes = (map['sceneArchetypes'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final sofaVibes = (map['sofaVibes'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    if (sceneArchetypes.isEmpty && sofaVibes.isEmpty) return null;
    final queuedAtRaw = map['queuedAt'];
    final queuedAt = queuedAtRaw is num
        ? queuedAtRaw.toInt()
        : DateTime.now().millisecondsSinceEpoch;

    return OnboardingV2PendingSubmission(
      sceneArchetypes: sceneArchetypes,
      sofaVibes: sofaVibes,
      budgetBand: map['budgetBand'] as String?,
      seatCount: map['seatCount'] as String?,
      modularOnly: map['modularOnly'] as bool?,
      kidsPets: map['kidsPets'] as bool?,
      smallSpace: map['smallSpace'] as bool?,
      queuedAt: queuedAt,
    );
  }
}

final onboardingV2Provider =
    StateNotifierProvider<OnboardingV2Notifier, OnboardingV2State>((ref) {
  return OnboardingV2Notifier();
});

class OnboardingV2Notifier extends StateNotifier<OnboardingV2State> {
  OnboardingV2Notifier() : super(const OnboardingV2State()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      final loaded = OnboardingV2State(
        version: (box.get(kOnboardingV2Version,
                defaultValue: onboardingV2SchemaVersion) as num)
            .toInt(),
        status: _statusFromString(
          box.get(kOnboardingV2Status, defaultValue: 'not_started') as String?,
        ),
        sceneArchetypes:
            (box.get(kOnboardingV2SceneArchetypes) as List?)?.cast<String>() ??
                const [],
        sofaVibes: (box.get(kOnboardingV2SofaVibes) as List?)?.cast<String>() ??
            const [],
        budgetBand: box.get(kOnboardingV2BudgetBand) as String?,
        seatCount: box.get(kOnboardingV2SeatCount) as String?,
        modularOnly: box.get(kOnboardingV2ModularOnly) as bool?,
        kidsPets: box.get(kOnboardingV2KidsPets) as bool?,
        smallSpace: box.get(kOnboardingV2SmallSpace) as bool?,
        lastSkipSwipe:
            (box.get(kOnboardingV2LastSkipSwipe, defaultValue: 0) as num)
                .toInt(),
        hardSkipCount:
            (box.get(kOnboardingV2HardSkipCount, defaultValue: 0) as num)
                .toInt(),
        totalRightSwipes:
            (box.get(kOnboardingV2TotalRightSwipes, defaultValue: 0) as num)
                .toInt(),
        completedAt: (box.get(kOnboardingV2CompletedAt) as num?)?.toInt(),
        currentStep:
            (box.get(kOnboardingV2CurrentStep, defaultValue: 0) as num).toInt(),
        pendingSubmission: OnboardingV2PendingSubmission.fromJson(
          box.get(kOnboardingV2PendingSubmission),
        ),
      );
      state = loaded;
    } catch (_) {
      state = const OnboardingV2State();
    }
  }

  Future<void> _persist(OnboardingV2State next) async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      await box.put(kOnboardingV2Version, next.version);
      await box.put(kOnboardingV2Status, _statusToString(next.status));
      await box.put(kOnboardingV2SceneArchetypes, next.sceneArchetypes);
      await box.put(kOnboardingV2SofaVibes, next.sofaVibes);
      if (next.budgetBand != null) {
        await box.put(kOnboardingV2BudgetBand, next.budgetBand);
      } else {
        await box.delete(kOnboardingV2BudgetBand);
      }
      if (next.seatCount != null) {
        await box.put(kOnboardingV2SeatCount, next.seatCount);
      } else {
        await box.delete(kOnboardingV2SeatCount);
      }
      if (next.modularOnly != null) {
        await box.put(kOnboardingV2ModularOnly, next.modularOnly);
      } else {
        await box.delete(kOnboardingV2ModularOnly);
      }
      if (next.kidsPets != null) {
        await box.put(kOnboardingV2KidsPets, next.kidsPets);
      } else {
        await box.delete(kOnboardingV2KidsPets);
      }
      if (next.smallSpace != null) {
        await box.put(kOnboardingV2SmallSpace, next.smallSpace);
      } else {
        await box.delete(kOnboardingV2SmallSpace);
      }
      await box.put(kOnboardingV2LastSkipSwipe, next.lastSkipSwipe);
      await box.put(kOnboardingV2HardSkipCount, next.hardSkipCount);
      await box.put(kOnboardingV2TotalRightSwipes, next.totalRightSwipes);
      if (next.completedAt != null) {
        await box.put(kOnboardingV2CompletedAt, next.completedAt);
      } else {
        await box.delete(kOnboardingV2CompletedAt);
      }
      await box.put(kOnboardingV2CurrentStep, next.currentStep);
      if (next.pendingSubmission != null) {
        await box.put(
          kOnboardingV2PendingSubmission,
          next.pendingSubmission!.toJson(),
        );
      } else {
        await box.delete(kOnboardingV2PendingSubmission);
      }
      state = next;
    } catch (_) {
      state = next;
    }
  }

  Future<void> markInProgress() async {
    if (state.status == OnboardingV2Status.inProgress) return;
    await _persist(
        state.copyWith(status: OnboardingV2Status.inProgress, currentStep: 1));
  }

  Future<void> setSceneArchetypes(List<String> values) async {
    await _persist(state.copyWith(sceneArchetypes: List<String>.from(values)));
  }

  Future<void> setSofaVibes(List<String> values) async {
    await _persist(state.copyWith(sofaVibes: List<String>.from(values)));
  }

  Future<void> setConstraints({
    String? budgetBand,
    bool clearBudgetBand = false,
    String? seatCount,
    bool clearSeatCount = false,
    bool? modularOnly,
    bool clearModularOnly = false,
    bool? kidsPets,
    bool clearKidsPets = false,
    bool? smallSpace,
    bool clearSmallSpace = false,
  }) async {
    await _persist(
      state.copyWith(
        budgetBand: budgetBand,
        clearBudgetBand: clearBudgetBand,
        seatCount: seatCount,
        clearSeatCount: clearSeatCount,
        modularOnly: modularOnly,
        clearModularOnly: clearModularOnly,
        kidsPets: kidsPets,
        clearKidsPets: clearKidsPets,
        smallSpace: smallSpace,
        clearSmallSpace: clearSmallSpace,
      ),
    );
  }

  Future<void> incrementRightSwipes() async {
    await _persist(
      state.copyWith(totalRightSwipes: state.totalRightSwipes + 1),
    );
  }

  Future<void> softSkip() async {
    await _persist(
      state.copyWith(
        status: OnboardingV2Status.skipped,
        hardSkipCount: state.hardSkipCount + 1,
        lastSkipSwipe: state.totalRightSwipes,
        currentStep: 0,
        clearPendingSubmission: true,
      ),
    );
  }

  Future<void> complete() async {
    await _persist(
      state.copyWith(
        status: OnboardingV2Status.completed,
        completedAt: DateTime.now().millisecondsSinceEpoch,
        currentStep: 4,
      ),
    );
  }

  Future<void> resetToStepOne() async {
    await _persist(
      state.copyWith(
        status: OnboardingV2Status.inProgress,
        currentStep: 1,
      ),
    );
  }

  Future<void> startFresh() async {
    await _persist(
      state.copyWith(
        status: OnboardingV2Status.inProgress,
        sceneArchetypes: const [],
        sofaVibes: const [],
        clearBudgetBand: true,
        clearSeatCount: true,
        clearModularOnly: true,
        clearKidsPets: true,
        clearSmallSpace: true,
        currentStep: 1,
        clearPendingSubmission: true,
      ),
    );
  }

  Future<void> setCurrentStep(int step) async {
    final bounded = step.clamp(0, 4).toInt();
    if (bounded == state.currentStep) return;
    await _persist(state.copyWith(currentStep: bounded));
  }

  Future<void> queuePendingSubmission(
      OnboardingV2PendingSubmission pending) async {
    await _persist(state.copyWith(pendingSubmission: pending));
  }

  Future<void> clearPendingSubmission() async {
    if (state.pendingSubmission == null) return;
    await _persist(state.copyWith(clearPendingSubmission: true));
  }
}
