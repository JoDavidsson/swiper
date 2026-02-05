import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme.dart';
import '../../../data/api_client.dart';
import '../../../data/gold_card_provider.dart';

/// Gold card for visual style selection - "Pick 3 sofas you love"
/// Displayed as a special card in the deck after first right swipe.
class GoldCardVisual extends StatefulWidget {
  const GoldCardVisual({
    super.key,
    required this.sofas,
    required this.onComplete,
    required this.onSkip,
  });

  final List<CuratedSofa> sofas;
  final void Function(List<String> pickedItemIds) onComplete;
  final VoidCallback onSkip;

  @override
  GoldCardVisualState createState() => GoldCardVisualState();
}

class GoldCardVisualState extends State<GoldCardVisual> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final canSubmit = _selectedIds.length == 3;
    
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
            padding: const EdgeInsets.all(AppTheme.spacingUnit),
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
                  'Help us find your style',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingUnit / 2),
                Text(
                  'Tap 3 sofas you would put in your dream home',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          // Selection counter
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingUnit,
              vertical: AppTheme.spacingUnit / 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _selectedIds.length
                            ? AppTheme.positiveLike
                            : AppTheme.textCaption.withValues(alpha: 0.3),
                        border: Border.all(
                          color: i < _selectedIds.length
                              ? AppTheme.positiveLike
                              : AppTheme.textCaption.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: AppTheme.spacingUnit / 2),
                Text(
                  '${_selectedIds.length}/3 selected',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          // Sofa grid (2x3)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppTheme.spacingUnit / 2,
                  mainAxisSpacing: AppTheme.spacingUnit / 2,
                  childAspectRatio: 1.0,
                ),
                itemCount: widget.sofas.length.clamp(0, 6),
                itemBuilder: (context, index) {
                  final sofa = widget.sofas[index];
                  final isSelected = _selectedIds.contains(sofa.id);
                  
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedIds.remove(sofa.id);
                        } else if (_selectedIds.length < 3) {
                          _selectedIds.add(sofa.id);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.positiveLike
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.positiveLike.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusChip - 2),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: ApiClient.proxyImageUrl(sofa.imageUrl),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: AppTheme.background,
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppTheme.background,
                                child: const Icon(Icons.image_not_supported),
                              ),
                            ),
                            // Selection overlay
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: isSelected ? 1.0 : 0.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.positiveLike.withValues(alpha: 0.2),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.check_circle,
                                    color: AppTheme.positiveLike,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
                    Icon(
                      canSubmit ? Icons.swipe_right : Icons.touch_app,
                      color: canSubmit ? AppTheme.positiveLike : AppTheme.textCaption,
                      size: 20,
                    ),
                    const SizedBox(width: AppTheme.spacingUnit / 2),
                    Text(
                      canSubmit
                          ? 'Swipe right to continue'
                          : 'Tap sofas to select',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: canSubmit ? AppTheme.positiveLike : AppTheme.textCaption,
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

  /// Call this when the card is swiped right
  void submitSelection() {
    if (_selectedIds.length == 3) {
      widget.onComplete(_selectedIds.toList());
    }
  }

  /// Whether the selection is complete (3 items selected)
  bool get isSelectionComplete => _selectedIds.length == 3;

  /// Get the selected item IDs
  List<String> get selectedIds => _selectedIds.toList();
}
