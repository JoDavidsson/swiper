import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../../core/theme.dart';
import '../../data/models/item.dart';
import 'deck_card.dart';

const double _swipeThreshold = 110;
const double _maxDragDx = 420;
const double _rotationFactor = 0.00035;
const int _exitAnimationDurationMs = 220;
const double _overlayFadeDistance = 140;
const SpringDescription _snapBackSpring = SpringDescription(
  mass: 1.2,
  stiffness: 220,
  damping: 20,
);

/// Optional: parent can register trigger callbacks and isAnimating getter (for button-triggered swipe).
typedef RegisterSwipeTriggers = void Function(
  VoidCallback? triggerLeft,
  VoidCallback? triggerRight,
  bool Function()? isAnimating,
);

/// Single card that can be swiped left/right with drag + animation.
/// Commit (onSwipeLeft/Right) is called when the user commits; removal from list
/// happens when onSwipeAnimationEnd is called after the exit animation completes.
class DraggableSwipeCard extends StatefulWidget {
  const DraggableSwipeCard({
    super.key,
    required this.item,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onTap,
    this.onSwipeAnimationEnd,
    this.onSwipeCancel,
    this.onRegisterSwipeTriggers,
  });

  final Item item;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final VoidCallback onTap;
  final void Function(Item item)? onSwipeAnimationEnd;

  /// Called when user releases without crossing swipe threshold (swipe_cancel).
  final void Function(Item item)? onSwipeCancel;

  /// If set, called in initState with (triggerLeft, triggerRight, isAnimating)
  /// and in dispose with (null, null, null).
  final RegisterSwipeTriggers? onRegisterSwipeTriggers;

  @override
  State<DraggableSwipeCard> createState() => DraggableSwipeCardState();
}

class DraggableSwipeCardState extends State<DraggableSwipeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _positionController;
  bool _isExiting = false;

  bool get _isAnimating => _isExiting || _positionController.isAnimating;
  double get _dragDx =>
      _positionController.value.clamp(-_maxDragDx, _maxDragDx).toDouble();

  @override
  void initState() {
    super.initState();
    _positionController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });

    if (widget.onRegisterSwipeTriggers != null) {
      widget.onRegisterSwipeTriggers!(
        triggerSwipeLeft,
        triggerSwipeRight,
        () => _isAnimating,
      );
    }
  }

  @override
  void dispose() {
    if (widget.onRegisterSwipeTriggers != null) {
      widget.onRegisterSwipeTriggers!(null, null, null);
    }
    _positionController.dispose();
    super.dispose();
  }

  void triggerSwipeLeft() => _animateExit(-560);

  void triggerSwipeRight() => _animateExit(560);

  void _onDragStart(DragStartDetails details) {
    if (_isExiting) return;
    if (_positionController.isAnimating) {
      _positionController.stop();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isExiting) return;
    _positionController.value = (_positionController.value + details.delta.dx)
        .clamp(-_maxDragDx, _maxDragDx);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isExiting) return;
    final dx = _dragDx;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldSwipeRight =
        dx > _swipeThreshold || (dx > 26 && velocity > 260);
    final shouldSwipeLeft =
        dx < -_swipeThreshold || (dx < -26 && velocity < -260);

    if (shouldSwipeRight) {
      widget.onSwipeRight();
      _animateExit(560);
      return;
    }
    if (shouldSwipeLeft) {
      widget.onSwipeLeft();
      _animateExit(-560);
      return;
    }

    widget.onSwipeCancel?.call(widget.item);
    final simulation = SpringSimulation(
      _snapBackSpring,
      _positionController.value,
      0,
      velocity / 1000,
    );
    _positionController.animateWith(simulation);
  }

  Future<void> _animateExit(double targetDx) async {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _positionController.stop();
    try {
      await _positionController.animateTo(
        targetDx,
        duration: const Duration(milliseconds: _exitAnimationDurationMs),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;
      widget.onSwipeAnimationEnd?.call(widget.item);
    } finally {
      if (mounted) {
        _positionController.value = 0;
        setState(() => _isExiting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dx = _dragDx;
    final rightProgress =
        dx > 0 ? (dx / _overlayFadeDistance).clamp(0.0, 1.0) : 0.0;
    final leftProgress =
        dx < 0 ? (-dx / _overlayFadeDistance).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: _isAnimating ? null : widget.onTap,
      onPanStart: _onDragStart,
      onPanUpdate: _onDragUpdate,
      onPanEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.rotate(
          angle: dx * _rotationFactor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DeckCard(
                item: widget.item,
                elevation: 4,
                compact: false,
                desaturation: leftProgress,
              ),
              Positioned(
                left: 20,
                top: 40,
                child: Transform.rotate(
                  angle: -0.22,
                  child: Opacity(
                    opacity: rightProgress,
                    child: const _FeedbackStamp(
                      label: 'SAVE',
                      icon: Icons.favorite_rounded,
                      color: AppTheme.positiveLike,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                top: 40,
                child: Transform.rotate(
                  angle: 0.22,
                  child: Opacity(
                    opacity: leftProgress,
                    child: const _FeedbackStamp(
                      label: 'PASS',
                      icon: Icons.close_rounded,
                      color: AppTheme.negativeDislike,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackStamp extends StatelessWidget {
  const _FeedbackStamp({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
