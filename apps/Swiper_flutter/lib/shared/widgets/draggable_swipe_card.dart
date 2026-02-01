import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../data/models/item.dart';

const double _swipeThreshold = 100;
const double _rotationFactor = 0.0003;

/// Single card that can be swiped left/right with drag + animation.
class DraggableSwipeCard extends StatefulWidget {
  const DraggableSwipeCard({
    super.key,
    required this.item,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onTap,
  });

  final Item item;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final VoidCallback onTap;

  @override
  State<DraggableSwipeCard> createState() => _DraggableSwipeCardState();
}

class _DraggableSwipeCardState extends State<DraggableSwipeCard> with SingleTickerProviderStateMixin {
  double _dragDx = 0;
  late AnimationController _controller;
  Offset _exitEnd = Offset.zero;
  bool _swipingRight = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_swipingRight) {
          widget.onSwipeRight();
        } else {
          widget.onSwipeLeft();
        }
        _controller.reset();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      _exitEnd = const Offset(500, 0);
      _swipingRight = true;
      _controller.forward();
    } else if (shouldSwipeLeft) {
      _exitEnd = const Offset(-500, 0);
      _swipingRight = false;
      _controller.forward();
    } else {
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
        child: _CardContent(item: widget.item),
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.firstImageUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) => Container(color: AppTheme.background, child: Icon(Icons.image_not_supported, size: 64, color: AppTheme.textCaption)),
            )
          else
            Container(color: AppTheme.background, child: Icon(Icons.image_not_supported, size: 64, color: AppTheme.textCaption)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${item.priceAmount.toStringAsFixed(0)} ${item.priceCurrency}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                  if (item.sizeClass != null) Chip(label: Text(item.sizeClass!, style: const TextStyle(fontSize: 12)), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
