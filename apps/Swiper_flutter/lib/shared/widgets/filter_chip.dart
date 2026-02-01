import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Themed filter chip: 10dp radius per design tokens.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: label,
      selected: selected,
      onSelected: onSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusChip)),
      selectedColor: AppTheme.primaryAction.withValues(alpha: 0.2),
    );
  }
}
