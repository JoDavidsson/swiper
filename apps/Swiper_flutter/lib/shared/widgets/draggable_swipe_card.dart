import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../data/models/item.dart';
import 'swipe_card.dart';

const double _swipeThreshold = 100;
const double _rotationFactor = 0.0003;
const double _buttonNudge = 40;

enum SwipeDirection { left, right }

class SwipeCommand {
  const SwipeCommand(this.direction, this.gesture);

  final SwipeDirection direction;
  final String gesture;
}

class SwipeCardController extends ChangeNotifier {
  SwipeCommand? _pending;

  void swipeLeft({String gesture = 'button'}) {
    _pending = SwipeCommand(SwipeDirection.left, gesture);
    notifyListeners();
  }

  void swipeRight({String gesture = 'button'}) {
    _pending = SwipeCommand(SwipeDirection.right, gesture);
    notifyListeners();
  }

  SwipeCommand? consume() {
    final current = _pending;
    _pending = null;
    return current;
  }
}

/// Single card that can be swiped left/right with drag + animation.
class DraggableSwipeCard extends StatefulWidget {
  const DraggableSwipeCard({
    super.key,
    required this.item,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onTap,
    this.controller,
  });

  final Item item;
  final void Function(String gesture) onSwipeLeft;
  final void Function(String gesture) onSwipeRight;
  final VoidCallback onTap;
  final SwipeCardController? controller;

  @override
  State<DraggableSwipeCard> createState() => _DraggableSwipeCardState();
}

class _DraggableSwipeCardState extends State<DraggableSwipeCard> with SingleTickerProviderStateMixin {
  double _dragDx = 0;
  late AnimationController _controller;
  Offset _exitEnd = Offset.zero;
  bool _swipingRight = false;
  String _gesture = 'swipe';
  bool _thresholdHapticFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_swipingRight) {
          widget.onSwipeRight(_gesture);
        } else {
          widget.onSwipeLeft(_gesture);
        }
        if (mounted) {
          setState(() {
            _dragDx = _exitEnd.dx;
            _thresholdHapticFired = false;
          });
        }
        _controller.reset();
      }
    });
    widget.controller?.addListener(_handleController);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleController);
    _controller.dispose();
    super.dispose();
  }

  void _handleController() {
    final command = widget.controller?.consume();
    if (command == null || _controller.isAnimating) return;
    _gesture = command.gesture;
    _dragDx = command.direction == SwipeDirection.right ? _buttonNudge : -_buttonNudge;
    _startSwipe(command.direction);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) return;
    setState(() {
      _dragDx += details.delta.dx;
      _dragDx = _dragDx.clamp(-400.0, 400.0);
      final overThreshold = _dragDx.abs() >= _swipeThreshold;
      if (overThreshold && !_thresholdHapticFired) {
        HapticFeedback.lightImpact();
        _thresholdHapticFired = true;
      } else if (!overThreshold && _thresholdHapticFired) {
        _thresholdHapticFired = false;
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_controller.isAnimating) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldSwipeRight = _dragDx > _swipeThreshold || (_dragDx > 20 && velocity > 200);
    final shouldSwipeLeft = _dragDx < -_swipeThreshold || (_dragDx < -20 && velocity < -200);

    if (shouldSwipeRight) {
      _gesture = 'swipe';
      _startSwipe(SwipeDirection.right);
    } else if (shouldSwipeLeft) {
      _gesture = 'swipe';
      _startSwipe(SwipeDirection.left);
    } else {
      setState(() {
        _dragDx = 0;
        _thresholdHapticFired = false;
      });
    }
  }

  void _startSwipe(SwipeDirection direction) {
    _exitEnd = direction == SwipeDirection.right ? const Offset(500, 0) : const Offset(-500, 0);
    _swipingRight = direction == SwipeDirection.right;
    HapticFeedback.lightImpact();
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final offset = _controller.isAnimating
        ? Offset.lerp(Offset(_dragDx, 0), _exitEnd, Curves.easeOut.transform(_controller.value)) ?? Offset.zero
        : Offset(_dragDx, 0);
    final rotation = (_controller.isAnimating ? offset.dx : _dragDx) * _rotationFactor;
    final progress = (offset.dx / _swipeThreshold).clamp(-1.0, 1.0);
    final likeOpacity = progress > 0 ? progress : 0.0;
    final nopeOpacity = progress < 0 ? -progress : 0.0;
    final tintColor = progress > 0 ? AppTheme.positiveLike : progress < 0 ? AppTheme.negativeDislike : null;
    final tintOpacity = (progress.abs() * 0.12).clamp(0.0, 0.12);

    return GestureDetector(
      onTap: _controller.isAnimating ? null : widget.onTap,
      onPanUpdate: _onDragUpdate,
      onPanEnd: _onDragEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: offset,
            child: Transform.rotate(
              angle: rotation,
              child: child,
            ),
          );
        },
        child: SwipeCard(
          item: widget.item,
          overlay: Positioned.fill(
            child: Stack(
              children: [
                if (tintColor != null)
                  Container(
                    color: tintColor.withValues(alpha: tintOpacity),
                  ),
                Positioned(
                  top: AppTheme.spacingUnit,
                  left: AppTheme.spacingUnit,
                  child: Opacity(
                    opacity: nopeOpacity,
                    child: _SwipeLabel(
                      text: 'NOPE',
                      color: AppTheme.negativeDislike,
                      rotation: -0.2,
                    ),
                  ),
                ),
                Positioned(
                  top: AppTheme.spacingUnit,
                  right: AppTheme.spacingUnit,
                  child: Opacity(
                    opacity: likeOpacity,
                    child: _SwipeLabel(
                      text: 'LIKE',
                      color: AppTheme.positiveLike,
                      rotation: 0.2,
                    ),
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

class _SwipeLabel extends StatelessWidget {
  const _SwipeLabel({required this.text, required this.color, required this.rotation});

  final String text;
  final Color color;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(AppTheme.radiusChip),
          color: Colors.black.withValues(alpha: 0.12),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
        ),
      ),
    );
  }
}
