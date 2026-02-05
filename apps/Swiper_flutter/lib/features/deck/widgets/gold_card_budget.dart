import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Gold card for budget selection - "What's your budget?"
/// Displayed immediately after the visual gold card is completed.
class GoldCardBudget extends StatefulWidget {
  const GoldCardBudget({
    super.key,
    required this.onComplete,
    required this.onSkip,
    this.initialMin = 0,
    this.initialMax = 50000,
  });

  final void Function(double budgetMin, double budgetMax) onComplete;
  final VoidCallback onSkip;
  final double initialMin;
  final double initialMax;

  @override
  GoldCardBudgetState createState() => GoldCardBudgetState();
}

class GoldCardBudgetState extends State<GoldCardBudget> {
  late double _budgetMin;
  late double _budgetMax;

  @override
  void initState() {
    super.initState();
    _budgetMin = widget.initialMin;
    _budgetMax = widget.initialMax;
  }

  String _formatPrice(double value) {
    if (value >= 1000) {
      final k = (value / 1000).round();
      return '${k}k SEK';
    }
    return '${value.round()} SEK';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppTheme.spacingUnit),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: const Color(0xFFFFD700), // Gold color
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingUnit * 1.5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFD700).withValues(alpha: 0.2),
                  const Color(0xFFFFD700).withValues(alpha: 0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusCard - 3),
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFFFFD700),
                  size: 32,
                ),
                const SizedBox(height: AppTheme.spacingUnit / 2),
                Text(
                  'One more thing...',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingUnit / 2),
                Text(
                  "What's your budget?",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          // Budget content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Current range display
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingUnit * 2,
                      vertical: AppTheme.spacingUnit,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAction.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                    ),
                    child: Text(
                      '${_formatPrice(_budgetMin)} - ${_formatPrice(_budgetMax)}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.primaryAction,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: AppTheme.spacingUnit * 3),
                  
                  // Range slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppTheme.primaryAction,
                      inactiveTrackColor: AppTheme.textCaption.withValues(alpha: 0.2),
                      thumbColor: AppTheme.primaryAction,
                      overlayColor: AppTheme.primaryAction.withValues(alpha: 0.2),
                      trackHeight: 6,
                      rangeThumbShape: const RoundRangeSliderThumbShape(
                        enabledThumbRadius: 12,
                        elevation: 4,
                      ),
                    ),
                    child: RangeSlider(
                      values: RangeValues(_budgetMin, _budgetMax),
                      min: 0,
                      max: 50000,
                      divisions: 50,
                      onChanged: (values) {
                        setState(() {
                          _budgetMin = values.start;
                          _budgetMax = values.end;
                        });
                      },
                    ),
                  ),
                  
                  // Min/Max labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '0 SEK',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textCaption,
                          ),
                        ),
                        Text(
                          '50k+ SEK',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: AppTheme.spacingUnit * 2),
                  
                  // Quick select buttons
                  Wrap(
                    spacing: AppTheme.spacingUnit / 2,
                    runSpacing: AppTheme.spacingUnit / 2,
                    alignment: WrapAlignment.center,
                    children: [
                      _QuickSelectChip(
                        label: 'Budget',
                        subtitle: '< 5k',
                        isSelected: _budgetMin == 0 && _budgetMax == 5000,
                        onTap: () => setState(() {
                          _budgetMin = 0;
                          _budgetMax = 5000;
                        }),
                      ),
                      _QuickSelectChip(
                        label: 'Mid-range',
                        subtitle: '5-15k',
                        isSelected: _budgetMin == 5000 && _budgetMax == 15000,
                        onTap: () => setState(() {
                          _budgetMin = 5000;
                          _budgetMax = 15000;
                        }),
                      ),
                      _QuickSelectChip(
                        label: 'Premium',
                        subtitle: '15-30k',
                        isSelected: _budgetMin == 15000 && _budgetMax == 30000,
                        onTap: () => setState(() {
                          _budgetMin = 15000;
                          _budgetMax = 30000;
                        }),
                      ),
                      _QuickSelectChip(
                        label: 'Luxury',
                        subtitle: '30k+',
                        isSelected: _budgetMin == 30000 && _budgetMax == 50000,
                        onTap: () => setState(() {
                          _budgetMin = 30000;
                          _budgetMax = 50000;
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Footer with instructions
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppTheme.radiusCard - 3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.swipe_right,
                      color: AppTheme.positiveLike,
                      size: 20,
                    ),
                    const SizedBox(width: AppTheme.spacingUnit / 2),
                    Text(
                      'Swipe right to continue',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.positiveLike,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingUnit / 2),
                Text(
                  'Swipe left to skip',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textCaption.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Get current budget range
  double get budgetMin => _budgetMin;
  double get budgetMax => _budgetMax;
}

class _QuickSelectChip extends StatelessWidget {
  const _QuickSelectChip({
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingUnit,
          vertical: AppTheme.spacingUnit / 2,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryAction.withValues(alpha: 0.15)
              : AppTheme.background,
          borderRadius: BorderRadius.circular(AppTheme.radiusChip),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryAction
                : AppTheme.textCaption.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected ? AppTheme.primaryAction : AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? AppTheme.primaryAction.withValues(alpha: 0.8)
                    : AppTheme.textCaption,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
