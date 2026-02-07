import 'package:flutter/material.dart';
import '../../data/models/item.dart';
import 'deck_card.dart';

const double _swipeThreshold = 100;
const double _rotationFactor = 0.0003;
const int _animationDurationMs = 200;

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
  /// If set, called in initState with (triggerLeft, triggerRight, isAnimating) and in dispose with (null, null, null).
  final RegisterSwipeTriggers? onRegisterSwipeTriggers;

  @override
  State<DraggableSwipeCard> createState() => DraggableSwipeCardState();
}

class DraggableSwipeCardState extends State<DraggableSwipeCard> with SingleTickerProviderStateMixin {
  double _dragDx = 0;
  late AnimationController _controller;
  Offset _exitEnd = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: _animationDurationMs),
      vsync: this,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onSwipeAnimationEnd?.call(widget.item);
        _controller.reset();
      }
    });
    if (widget.onRegisterSwipeTriggers != null) {
      widget.onRegisterSwipeTriggers!(triggerSwipeLeft, triggerSwipeRight, () => _controller.isAnimating);
    }
  }

  @override
  void dispose() {
    if (widget.onRegisterSwipeTriggers != null) {
      widget.onRegisterSwipeTriggers!(null, null, null);
    }
    _controller.dispose();
    super.dispose();
  }

  void triggerSwipeLeft() {
    if (_controller.isAnimating) return;
    _exitEnd = const Offset(-500, 0);
    _controller.forward();
  }

  void triggerSwipeRight() {
    if (_controller.isAnimating) return;
    _exitEnd = const Offset(500, 0);
    _controller.forward();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) return;
    setState(() {
      _dragDx += details.delta.dx;
      _dragDx = _dragDx.clamp(-400.0, 400.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_controller.isAnimating) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldSwipeRight = _dragDx > _swipeThreshold || (_dragDx > 20 && velocity > 200);
    final shouldSwipeLeft = _dragDx < -_swipeThreshold || (_dragDx < -20 && velocity < -200);

    if (shouldSwipeRight) {
      widget.onSwipeRight();
      _exitEnd = const Offset(500, 0);
      _controller.forward();
    } else if (shouldSwipeLeft) {
      widget.onSwipeLeft();
      _exitEnd = const Offset(-500, 0);
      _controller.forward();
    } else {
      widget.onSwipeCancel?.call(widget.item);
      setState(() => _dragDx = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offset = _controller.isAnimating
        ? Offset.lerp(Offset(_dragDx, 0), _exitEnd, Curves.easeOut.transform(_controller.value)) ?? Offset.zero
        : Offset(_dragDx, 0);
    final rotation = ( _controller.isAnimating ? offset.dx : _dragDx) * _rotationFactor;

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
        child: DeckCard(
          item: widget.item,
          elevation: 4,
          compact: false,
        ),
      ),
    );
  }
}
