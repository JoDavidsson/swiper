import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';
import '../../data/session_provider.dart';
import '../../shared/widgets/filter_chip.dart' show AppFilterChip;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 3;

  final List<String> _selectedStyles = [];
  double _budgetMin = 0, _budgetMax = 50000;
  bool _ecoOnly = false;
  bool _newOnly = true;
  bool _sizeConstraint = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    } else {
      final sessionId = ref.read(sessionIdProvider);
      if (sessionId != null && !ref.read(analyticsOptOutProvider)) {
        ref.read(apiClientProvider).logEvent(
          sessionId: sessionId,
          eventType: 'onboarding_complete',
          metadata: {
            'styles': _selectedStyles,
            'budgetMin': _budgetMin.round(),
            'budgetMax': _budgetMax.round(),
            'ecoOnly': _ecoOnly,
            'newOnly': _newOnly,
            'sizeConstraint': _sizeConstraint,
          },
        ).ignore();
      }
      context.go('/deck');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Step ${_currentStep + 1} of $_totalSteps'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_currentStep + 1) / _totalSteps,
              backgroundColor: AppTheme.textCaption.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryAction),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1(),
                  _buildStep2(),
                  _buildStep3(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(_currentStep == _totalSteps - 1 ? 'Building your deck…' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    const styleTags = ['Scandinavian', 'Modern', 'Vintage', 'Minimal', 'Industrial', 'Classic'];
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Text('Choose your style', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppTheme.spacingUnit),
          Wrap(
            spacing: AppTheme.spacingUnit,
            runSpacing: AppTheme.spacingUnit,
            children: styleTags.map((tag) {
              final selected = _selectedStyles.contains(tag);
              return AppFilterChip(
                label: Text(tag),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) _selectedStyles.add(tag);
                    else _selectedStyles.remove(tag);
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Text('Budget range (SEK)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppTheme.spacingUnit),
          Text('${_budgetMin.round()} – ${_budgetMax.round()} SEK', style: Theme.of(context).textTheme.bodyLarge),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: AppTheme.primaryAction),
            child: RangeSlider(
              values: RangeValues(_budgetMin, _budgetMax),
              min: 0,
              max: 50000,
              divisions: 50,
              onChanged: (v) => setState(() {
                _budgetMin = v.start;
                _budgetMax = v.end;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppTheme.spacingUnit * 2),
          Text('Preferences', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppTheme.spacingUnit * 2),
          SwitchListTile(
            title: const Text('Eco-friendly only'),
            value: _ecoOnly,
            onChanged: (v) => setState(() => _ecoOnly = v),
          ),
          SwitchListTile(
            title: const Text('New only'),
            value: _newOnly,
            onChanged: (v) => setState(() => _newOnly = v),
          ),
          SwitchListTile(
            title: const Text('Size constraint (small space)'),
            value: _sizeConstraint,
            onChanged: (v) => setState(() => _sizeConstraint = v),
          ),
        ],
      ),
    );
  }
}
