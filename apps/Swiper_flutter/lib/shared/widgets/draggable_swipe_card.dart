import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/models/item.dart';
import 'deck_card.dart';

const double _swipeThreshold = 100;
const double _rotationFactor = 0.0003;
const int _animationDurationMs = 200;
const _kAgentIngestUrl = 'http://127.0.0.1:7245/ingest/ddc9e3c2-ad47-4244-9d77-ce2efa8256ba';

void _swipeAnimationLog(String location, String message, Map<String, dynamic> data) {
  if (!kDebugMode) return;
  try {
    final payload = {
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sessionId': 'debug-session',
      'hypothesisId': 'flow',
    };
    Dio().post(_kAgentIngestUrl, data: payload).catchError((_) => Future.value(Response(requestOptions: RequestOptions(path: _kAgentIngestUrl))));
  } catch (_) {}
}

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
  double _lastLoggedFrameValue = -1;

  static const _frameThresholds = [0.25, 0.5, 0.75, 1.0];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: _animationDurationMs),
      vsync: this,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // #region agent log
        _swipeAnimationLog(
          'draggable_swipe_card.dart',
          'animation_completed',
          {'itemId': widget.item.id},
        );
        // #endregion
        _lastLoggedFrameValue = -1;
        widget.onSwipeAnimationEnd?.call(widget.item);
        _controller.reset();
      }
    });
    _controller.addListener(_onAnimationTick);
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

  void _onAnimationTick() {
    if (!kDebugMode) return;
    final value = _controller.value;
    double? newLastLogged;
    for (final t in _frameThresholds) {
      if (value >= t && _lastLoggedFrameValue < t) {
        final curveT = Curves.easeOut.transform(t);
        final offset = Offset.lerp(
          Offset(_dragDx, 0),
          _exitEnd,
          curveT,
        ) ?? Offset.zero;
        final rotationRad = offset.dx * _rotationFactor;
        _swipeAnimationLog(
          'draggable_swipe_card.dart:_onAnimationTick',
          'swipe_animation_frame',
          {
            'itemId': widget.item.id,
            'value': t,
            'offsetPx': offset.dx,
            'rotationRad': rotationRad,
          },
        );
        if (newLastLogged == null || t > newLastLogged) newLastLogged = t;
      }
    }
    if (newLastLogged != null) _lastLoggedFrameValue = newLastLogged;
  }

  void _emitSwipeAnimationStart(String direction, String trigger) {
    _swipeAnimationLog(
      'draggable_swipe_card.dart',
      'swipe_animation_start',
      {
        'itemId': widget.item.id,
        'direction': direction,
        'startPx': _dragDx,
        'endPx': _exitEnd.dx,
        'durationMs': _animationDurationMs,
        'trigger': trigger,
      },
    );
  }

  void triggerSwipeLeft() {
    if (_controller.isAnimating) return;
    _exitEnd = const Offset(-500, 0);
    _emitSwipeAnimationStart('left', 'button');
    _controller.forward();
  }

  void triggerSwipeRight() {
    if (_controller.isAnimating) return;
    _exitEnd = const Offset(500, 0);
    _emitSwipeAnimationStart('right', 'button');
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
      // #region agent log
      _swipeAnimationLog(
        'draggable_swipe_card.dart:_onDragEnd',
        'commit_and_forward',
        {'itemId': widget.item.id, 'direction': 'right', 'dragDx': _dragDx, 'trigger': 'gesture'},
      );
      // #endregion
      widget.onSwipeRight();
      _exitEnd = const Offset(500, 0);
      _emitSwipeAnimationStart('right', 'gesture');
      _controller.forward();
    } else if (shouldSwipeLeft) {
      // #region agent log
      _swipeAnimationLog(
        'draggable_swipe_card.dart:_onDragEnd',
        'commit_and_forward',
        {'itemId': widget.item.id, 'direction': 'left', 'dragDx': _dragDx, 'trigger': 'gesture'},
      );
      // #endregion
      widget.onSwipeLeft();
      _exitEnd = const Offset(-500, 0);
      _emitSwipeAnimationStart('left', 'gesture');
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
