import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_strings.dart';
import '../../../data/onboarding_v2_provider.dart';

enum GoldenV2Step {
  intro,
  roomVibes,
  sofaVibes,
  constraints,
  summary,
}

class GoldenV2Submission {
  const GoldenV2Submission({
    required this.sceneArchetypes,
    required this.sofaVibes,
    this.budgetBand,
    this.seatCount,
    this.modularOnly,
    this.kidsPets,
    this.smallSpace,
  });

  final List<String> sceneArchetypes;
  final List<String> sofaVibes;
  final String? budgetBand;
  final String? seatCount;
  final bool? modularOnly;
  final bool? kidsPets;
  final bool? smallSpace;

  Map<String, dynamic> toJson() {
    return {
      'sceneArchetypes': sceneArchetypes,
      'sofaVibes': sofaVibes,
      'constraints': {
        if (budgetBand != null) 'budgetBand': budgetBand,
        if (seatCount != null) 'seatCount': seatCount,
        if (modularOnly != null) 'modularOnly': modularOnly,
        if (kidsPets != null) 'kidsPets': kidsPets,
        if (smallSpace != null) 'smallSpace': smallSpace,
      },
    };
  }
}

class GoldenRoomVibeOption {
  const GoldenRoomVibeOption({
    required this.id,
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
    required this.gradient,
  });

  final String id;
  final String titleKey;
  final String subtitleKey;
  final IconData icon;
  final List<Color> gradient;
}

class GoldenSofaVibeOption {
  const GoldenSofaVibeOption({
    required this.id,
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
    required this.gradient,
  });

  final String id;
  final String titleKey;
  final String subtitleKey;
  final IconData icon;
  final List<Color> gradient;
}

class GoldenCardV2Flow extends StatefulWidget {
  const GoldenCardV2Flow({
    super.key,
    required this.strings,
    required this.initialState,
    required this.onMarkInProgress,
    required this.onSceneArchetypesChanged,
    required this.onSofaVibesChanged,
    required this.onConstraintsChanged,
    required this.onOptionToggled,
    required this.onStepChanged,
    required this.onSkip,
    required this.onComplete,
    required this.onStartFresh,
    required this.onAdjust,
  });

  final AppStrings strings;
  final OnboardingV2State initialState;
  final Future<void> Function() onMarkInProgress;
  final Future<void> Function(List<String> values) onSceneArchetypesChanged;
  final Future<void> Function(List<String> values) onSofaVibesChanged;
  final Future<void> Function({
    String? budgetBand,
    bool clearBudgetBand,
    String? seatCount,
    bool clearSeatCount,
    bool? modularOnly,
    bool clearModularOnly,
    bool? kidsPets,
    bool clearKidsPets,
    bool? smallSpace,
    bool clearSmallSpace,
  }) onConstraintsChanged;
  final Future<void> Function(String stepName, String optionId, bool selected)
      onOptionToggled;
  final Future<void> Function(int step) onStepChanged;
  final Future<void> Function() onSkip;
  final Future<void> Function(GoldenV2Submission submission) onComplete;
  final Future<void> Function() onStartFresh;
  final Future<void> Function() onAdjust;

  @override
  State<GoldenCardV2Flow> createState() => _GoldenCardV2FlowState();
}

class _GoldenCardV2FlowState extends State<GoldenCardV2Flow> {
  GoldenV2Step _step = GoldenV2Step.intro;
  late List<String> _sceneArchetypes;
  late List<String> _sofaVibes;
  String? _budgetBand;
  String? _seatCount;
  bool _modularOnly = false;
  bool _kidsPets = false;
  bool _smallSpace = false;
  bool _isSubmitting = false;

  static const List<GoldenRoomVibeOption> _roomOptions = [
    GoldenRoomVibeOption(
      id: 'calm_minimal',
      titleKey: 'goldV2RoomCalmTitle',
      subtitleKey: 'goldV2RoomCalmSubtitle',
      icon: Icons.self_improvement,
      gradient: [Color(0xFFECE8DE), Color(0xFFD8D2C8)],
    ),
    GoldenRoomVibeOption(
      id: 'warm_organic',
      titleKey: 'goldV2RoomWarmTitle',
      subtitleKey: 'goldV2RoomWarmSubtitle',
      icon: Icons.spa,
      gradient: [Color(0xFFF2D9BF), Color(0xFFE4C6A5)],
    ),
    GoldenRoomVibeOption(
      id: 'bold_eclectic',
      titleKey: 'goldV2RoomBoldTitle',
      subtitleKey: 'goldV2RoomBoldSubtitle',
      icon: Icons.palette,
      gradient: [Color(0xFFDBC9E6), Color(0xFFC4AED8)],
    ),
    GoldenRoomVibeOption(
      id: 'urban_industrial',
      titleKey: 'goldV2RoomUrbanTitle',
      subtitleKey: 'goldV2RoomUrbanSubtitle',
      icon: Icons.apartment,
      gradient: [Color(0xFFD1D5DB), Color(0xFFB0B5BF)],
    ),
  ];

  static const List<GoldenSofaVibeOption> _sofaOptions = [
    GoldenSofaVibeOption(
      id: 'rounded_boucle',
      titleKey: 'goldV2SofaRoundedTitle',
      subtitleKey: 'goldV2SofaRoundedSubtitle',
      icon: Icons.bubble_chart,
      gradient: [Color(0xFFF1E9DF), Color(0xFFE2D5C5)],
    ),
    GoldenSofaVibeOption(
      id: 'low_profile_linen',
      titleKey: 'goldV2SofaLowTitle',
      subtitleKey: 'goldV2SofaLowSubtitle',
      icon: Icons.horizontal_rule,
      gradient: [Color(0xFFE7EAEF), Color(0xFFD2D9E3)],
    ),
    GoldenSofaVibeOption(
      id: 'structured_leather',
      titleKey: 'goldV2SofaStructuredTitle',
      subtitleKey: 'goldV2SofaStructuredSubtitle',
      icon: Icons.chair,
      gradient: [Color(0xFFD6C2AB), Color(0xFFC4AC91)],
    ),
    GoldenSofaVibeOption(
      id: 'modular_cloud',
      titleKey: 'goldV2SofaModularTitle',
      subtitleKey: 'goldV2SofaModularSubtitle',
      icon: Icons.grid_view,
      gradient: [Color(0xFFE8E8E8), Color(0xFFD7D7D7)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _sceneArchetypes = List<String>.from(widget.initialState.sceneArchetypes);
    _sofaVibes = List<String>.from(widget.initialState.sofaVibes);
    _budgetBand = widget.initialState.budgetBand;
    _seatCount = widget.initialState.seatCount;
    _modularOnly = widget.initialState.modularOnly ?? false;
    _kidsPets = widget.initialState.kidsPets ?? false;
    _smallSpace = widget.initialState.smallSpace ?? false;
    _step = _stepFromIndex(widget.initialState.currentStep);
  }

  GoldenV2Step _stepFromIndex(int index) {
    switch (index) {
      case 1:
        return GoldenV2Step.roomVibes;
      case 2:
        return GoldenV2Step.sofaVibes;
      case 3:
        return GoldenV2Step.constraints;
      case 4:
        return GoldenV2Step.summary;
      default:
        return GoldenV2Step.intro;
    }
  }

  int _stepToIndex(GoldenV2Step step) {
    switch (step) {
      case GoldenV2Step.intro:
        return 0;
      case GoldenV2Step.roomVibes:
        return 1;
      case GoldenV2Step.sofaVibes:
        return 2;
      case GoldenV2Step.constraints:
        return 3;
      case GoldenV2Step.summary:
        return 4;
    }
  }

  Future<void> _setStep(GoldenV2Step step) async {
    if (!mounted) return;
    setState(() => _step = step);
    await widget.onStepChanged(_stepToIndex(step));
  }

  Future<void> _handleSkip() async {
    await widget.onSkip();
  }

  Future<void> _handleContinue() async {
    if (_isSubmitting) return;

    switch (_step) {
      case GoldenV2Step.intro:
        await widget.onMarkInProgress();
        await _setStep(GoldenV2Step.roomVibes);
        break;
      case GoldenV2Step.roomVibes:
        if (_sceneArchetypes.length != 2) return;
        await widget.onSceneArchetypesChanged(_sceneArchetypes);
        await _setStep(GoldenV2Step.sofaVibes);
        break;
      case GoldenV2Step.sofaVibes:
        if (_sofaVibes.length != 2) return;
        await widget.onSofaVibesChanged(_sofaVibes);
        await _setStep(GoldenV2Step.constraints);
        break;
      case GoldenV2Step.constraints:
        await widget.onConstraintsChanged(
          budgetBand: _budgetBand,
          clearBudgetBand: _budgetBand == null,
          seatCount: _seatCount,
          clearSeatCount: _seatCount == null,
          modularOnly: _modularOnly,
          clearModularOnly: false,
          kidsPets: _kidsPets,
          clearKidsPets: false,
          smallSpace: _smallSpace,
          clearSmallSpace: false,
        );
        await _setStep(GoldenV2Step.summary);
        break;
      case GoldenV2Step.summary:
        setState(() => _isSubmitting = true);
        try {
          await widget.onComplete(
            GoldenV2Submission(
              sceneArchetypes: List<String>.from(_sceneArchetypes),
              sofaVibes: List<String>.from(_sofaVibes),
              budgetBand: _budgetBand,
              seatCount: _seatCount,
              modularOnly: _modularOnly,
              kidsPets: _kidsPets,
              smallSpace: _smallSpace,
            ),
          );
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
        break;
    }
  }

  Future<void> _handleBack() async {
    if (_isSubmitting) return;
    switch (_step) {
      case GoldenV2Step.intro:
        return;
      case GoldenV2Step.roomVibes:
        await _setStep(GoldenV2Step.intro);
        return;
      case GoldenV2Step.sofaVibes:
        await _setStep(GoldenV2Step.roomVibes);
        return;
      case GoldenV2Step.constraints:
        await _setStep(GoldenV2Step.sofaVibes);
        return;
      case GoldenV2Step.summary:
        await _setStep(GoldenV2Step.constraints);
        return;
    }
  }

  String _primaryButtonLabel(AppStrings strings) {
    switch (_step) {
      case GoldenV2Step.intro:
        return strings.goldV2Start;
      case GoldenV2Step.roomVibes:
      case GoldenV2Step.sofaVibes:
        return strings.goldV2Continue;
      case GoldenV2Step.constraints:
        return strings.goldV2SeeDeck;
      case GoldenV2Step.summary:
        return _isSubmitting ? strings.buildingDeck : strings.goldV2LooksRight;
    }
  }

  bool _canContinue() {
    switch (_step) {
      case GoldenV2Step.intro:
        return true;
      case GoldenV2Step.roomVibes:
        return _sceneArchetypes.length == 2;
      case GoldenV2Step.sofaVibes:
        return _sofaVibes.length == 2;
      case GoldenV2Step.constraints:
        return true;
      case GoldenV2Step.summary:
        return !_isSubmitting;
    }
  }

  String _stepTitle(AppStrings strings) {
    switch (_step) {
      case GoldenV2Step.intro:
        return strings.goldV2IntroTitle;
      case GoldenV2Step.roomVibes:
        return strings.goldV2RoomTitle;
      case GoldenV2Step.sofaVibes:
        return strings.goldV2SofaTitle;
      case GoldenV2Step.constraints:
        return strings.goldV2ConstraintsTitle;
      case GoldenV2Step.summary:
        return strings.goldV2SummaryTitle;
    }
  }

  String _summaryStyleLine(AppStrings strings) {
    final room = _sceneArchetypes
        .map((id) => _roomOptions.firstWhere((o) => o.id == id).titleKey)
        .map(strings.localize)
        .join(' + ');
    final sofa = _sofaVibes
        .map((id) => _sofaOptions.firstWhere((o) => o.id == id).titleKey)
        .map(strings.localize)
        .join(' + ');
    if (room.isEmpty && sofa.isEmpty) return strings.goldV2SummaryFallback;
    if (room.isEmpty) return strings.goldV2SummarySofaOnly(sofa);
    if (sofa.isEmpty) return strings.goldV2SummaryRoomOnly(room);
    return strings.goldV2SummaryLine(room, sofa);
  }

  String _summaryConstraintLine(AppStrings strings) {
    final parts = <String>[];
    if (_budgetBand != null) {
      parts.add(strings.goldV2BudgetLabel(_budgetBand!));
    }
    if (_seatCount != null) {
      parts.add(strings.goldV2SeatsLabel(_seatCount!));
    }
    if (_modularOnly) {
      parts.add(strings.goldV2ConstraintModularOnly);
    }
    if (_kidsPets) {
      parts.add(strings.goldV2ConstraintKidsPets);
    }
    if (_smallSpace) {
      parts.add(strings.goldV2ConstraintSmallSpace);
    }
    if (parts.isEmpty) return strings.goldV2SummaryNoConstraints;
    return strings.goldV2SummaryConstraintLine(parts.join(', '));
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final progress = () {
      switch (_step) {
        case GoldenV2Step.intro:
          return 0.0;
        case GoldenV2Step.roomVibes:
          return 0.25;
        case GoldenV2Step.sofaVibes:
          return 0.5;
        case GoldenV2Step.constraints:
          return 0.75;
        case GoldenV2Step.summary:
          return 1.0;
      }
    }();

    return ColoredBox(
      color: AppTheme.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          child: Column(
            children: [
              _TopBar(
                title: _stepTitle(strings),
                step: _step,
                progress: progress,
                onBack: _step == GoldenV2Step.intro ? null : _handleBack,
                onSkip: _isSubmitting ? null : _handleSkip,
                strings: strings,
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  child: _buildStepContent(strings),
                ),
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canContinue() ? _handleContinue : null,
                  child: Text(_primaryButtonLabel(strings)),
                ),
              ),
              if (_step == GoldenV2Step.summary) ...[
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          await widget.onAdjust();
                          if (!mounted) return;
                          await _setStep(GoldenV2Step.roomVibes);
                        },
                  child: Text(strings.goldV2AdjustPicks),
                ),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          await widget.onStartFresh();
                          if (!mounted) return;
                          setState(() {
                            _sceneArchetypes = [];
                            _sofaVibes = [];
                            _budgetBand = null;
                            _seatCount = null;
                            _modularOnly = false;
                            _kidsPets = false;
                            _smallSpace = false;
                          });
                          await _setStep(GoldenV2Step.roomVibes);
                        },
                  child: Text(strings.goldV2StartFresh),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(AppStrings strings) {
    switch (_step) {
      case GoldenV2Step.intro:
        return _IntroStep(strings: strings, key: const ValueKey('intro'));
      case GoldenV2Step.roomVibes:
        return _SelectionGridStep(
          key: const ValueKey('room_vibes'),
          stepName: 'room_vibes',
          title: strings.goldV2RoomSubtitle,
          helper: strings.goldV2PickTwoRequired,
          selectedCount: _sceneArchetypes.length,
          options: _roomOptions
              .map(
                (o) => _SelectionOption(
                  id: o.id,
                  title: strings.localize(o.titleKey),
                  subtitle: strings.localize(o.subtitleKey),
                  icon: o.icon,
                  gradient: o.gradient,
                ),
              )
              .toList(),
          selectedIds: _sceneArchetypes,
          maxSelected: 2,
          onOptionToggled: widget.onOptionToggled,
          onSelectionChanged: (ids) => setState(() => _sceneArchetypes = ids),
        );
      case GoldenV2Step.sofaVibes:
        return _SelectionGridStep(
          key: const ValueKey('sofa_vibes'),
          stepName: 'sofa_vibes',
          title: strings.goldV2SofaSubtitle,
          helper: strings.goldV2PickTwoRequired,
          selectedCount: _sofaVibes.length,
          options: _sofaOptions
              .map(
                (o) => _SelectionOption(
                  id: o.id,
                  title: strings.localize(o.titleKey),
                  subtitle: strings.localize(o.subtitleKey),
                  icon: o.icon,
                  gradient: o.gradient,
                ),
              )
              .toList(),
          selectedIds: _sofaVibes,
          maxSelected: 2,
          onOptionToggled: widget.onOptionToggled,
          onSelectionChanged: (ids) => setState(() => _sofaVibes = ids),
        );
      case GoldenV2Step.constraints:
        return _ConstraintsStep(
          key: const ValueKey('constraints'),
          strings: strings,
          budgetBand: _budgetBand,
          seatCount: _seatCount,
          modularOnly: _modularOnly,
          kidsPets: _kidsPets,
          smallSpace: _smallSpace,
          onBudgetChanged: (v) => setState(() => _budgetBand = v),
          onSeatCountChanged: (v) => setState(() => _seatCount = v),
          onModularChanged: (v) => setState(() => _modularOnly = v),
          onKidsPetsChanged: (v) => setState(() => _kidsPets = v),
          onSmallSpaceChanged: (v) => setState(() => _smallSpace = v),
        );
      case GoldenV2Step.summary:
        return _SummaryStep(
          key: const ValueKey('summary'),
          strings: strings,
          styleLine: _summaryStyleLine(strings),
          constraintsLine: _summaryConstraintLine(strings),
          confidenceLabel: _sceneArchetypes.isNotEmpty && _sofaVibes.isNotEmpty
              ? strings.goldV2ConfidenceHigh
              : strings.goldV2ConfidenceMedium,
        );
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.step,
    required this.progress,
    required this.onBack,
    required this.onSkip,
    required this.strings,
  });

  final String title;
  final GoldenV2Step step;
  final double progress;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final stepIndex = switch (step) {
      GoldenV2Step.intro => 0,
      GoldenV2Step.roomVibes => 1,
      GoldenV2Step.sofaVibes => 2,
      GoldenV2Step.constraints => 3,
      GoldenV2Step.summary => 4,
    };

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            TextButton(
              onPressed: onSkip,
              child: Text(strings.skip),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingUnit / 2),
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: AppTheme.textCaption.withOpacity(0.2),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE4C755)),
        ),
        const SizedBox(height: AppTheme.spacingUnit / 2),
        Text(
          strings.goldV2StepProgress(stepIndex, 4),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _IntroStep extends StatelessWidget {
  const _IntroStep({super.key, required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3E8),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: const Color(0xFFE4C755), width: 2),
      ),
      padding: const EdgeInsets.all(AppTheme.spacingUnit * 1.5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFFE4C755), size: 42),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(
            strings.goldV2IntroSubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(
            strings.goldV2IntroTrust,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SelectionOption {
  const _SelectionOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
}

class _SelectionGridStep extends StatelessWidget {
  const _SelectionGridStep({
    super.key,
    required this.stepName,
    required this.title,
    required this.helper,
    required this.selectedCount,
    required this.options,
    required this.selectedIds,
    required this.maxSelected,
    required this.onOptionToggled,
    required this.onSelectionChanged,
  });

  final String stepName;
  final String title;
  final String helper;
  final int selectedCount;
  final List<_SelectionOption> options;
  final List<String> selectedIds;
  final int maxSelected;
  final Future<void> Function(String stepName, String optionId, bool selected)
      onOptionToggled;
  final ValueChanged<List<String>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spacingUnit / 2),
        Text(
          '$selectedCount/$maxSelected - $helper',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppTheme.textCaption),
        ),
        const SizedBox(height: AppTheme.spacingUnit),
        Expanded(
          child: GridView.builder(
            itemCount: options.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppTheme.spacingUnit,
              crossAxisSpacing: AppTheme.spacingUnit,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final option = options[index];
              final selected = selectedIds.contains(option.id);
              return _SelectionTile(
                option: option,
                selected: selected,
                onTap: () {
                  final next = List<String>.from(selectedIds);
                  bool becameSelected = false;
                  if (selected) {
                    next.remove(option.id);
                  } else if (next.length < maxSelected) {
                    next.add(option.id);
                    becameSelected = true;
                  }
                  if (selected || becameSelected) {
                    onOptionToggled(stepName, option.id, becameSelected);
                  }
                  onSelectionChanged(next);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _SelectionOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            gradient: LinearGradient(
              colors: option.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: selected ? AppTheme.positiveLike : Colors.transparent,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(option.icon, color: AppTheme.textPrimary),
                    const Spacer(),
                    if (selected)
                      const Icon(
                        Icons.check_circle,
                        color: AppTheme.positiveLike,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  option.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  option.subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConstraintsStep extends StatelessWidget {
  const _ConstraintsStep({
    super.key,
    required this.strings,
    required this.budgetBand,
    required this.seatCount,
    required this.modularOnly,
    required this.kidsPets,
    required this.smallSpace,
    required this.onBudgetChanged,
    required this.onSeatCountChanged,
    required this.onModularChanged,
    required this.onKidsPetsChanged,
    required this.onSmallSpaceChanged,
  });

  final AppStrings strings;
  final String? budgetBand;
  final String? seatCount;
  final bool modularOnly;
  final bool kidsPets;
  final bool smallSpace;
  final ValueChanged<String?> onBudgetChanged;
  final ValueChanged<String?> onSeatCountChanged;
  final ValueChanged<bool> onModularChanged;
  final ValueChanged<bool> onKidsPetsChanged;
  final ValueChanged<bool> onSmallSpaceChanged;

  static const List<String> _budgetBands = [
    'lt_5k',
    '5k_15k',
    '15k_30k',
    '30k_plus',
  ];

  static const List<String> _seatCounts = ['2', '3', '4_plus'];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.goldV2ConstraintsSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(strings.goldV2BudgetHeading,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.spacingUnit / 2),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _budgetBands
                .map(
                  (band) => ChoiceChip(
                    label: Text(strings.goldV2BudgetLabel(band)),
                    selected: budgetBand == band,
                    onSelected: (selected) =>
                        onBudgetChanged(selected ? band : null),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppTheme.spacingUnit),
          Text(strings.goldV2SeatsHeading,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.spacingUnit / 2),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _seatCounts
                .map(
                  (seats) => ChoiceChip(
                    label: Text(strings.goldV2SeatsLabel(seats)),
                    selected: seatCount == seats,
                    onSelected: (selected) =>
                        onSeatCountChanged(selected ? seats : null),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppTheme.spacingUnit),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.goldV2ConstraintModularOnly),
            value: modularOnly,
            onChanged: onModularChanged,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.goldV2ConstraintKidsPets),
            value: kidsPets,
            onChanged: onKidsPetsChanged,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.goldV2ConstraintSmallSpace),
            value: smallSpace,
            onChanged: onSmallSpaceChanged,
          ),
        ],
      ),
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep({
    super.key,
    required this.strings,
    required this.styleLine,
    required this.constraintsLine,
    required this.confidenceLabel,
  });

  final AppStrings strings;
  final String styleLine;
  final String constraintsLine;
  final String confidenceLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F3E8),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: const Color(0xFFE4C755), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.goldV2SummaryWeGotYou,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppTheme.spacingUnit / 2),
              Text(
                styleLine,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppTheme.spacingUnit / 2),
              Text(
                constraintsLine,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingUnit),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.spacingUnit),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.surfaceVariant),
          ),
          child: Row(
            children: [
              const Icon(Icons.insights, color: AppTheme.primaryAction),
              const SizedBox(width: 8),
              Text(
                strings.goldV2ConfidenceLabel(confidenceLabel),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
