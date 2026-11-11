import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';

/// A bottom sheet that follows the finger while its handle is dragged and flings open or closed by the speed at
/// release.
/// [visible] says from outside whether the sheet is open, and a drag that closes it is reported through [onDismissed]
/// so the caller's state stays in sync. Only the handle bar listens for the drag, because a drag recognizer around the
/// whole content loses in the gesture arena to the vertical scroll view of the metadata list.
class DraggableMetadataSheet extends StatefulWidget {
  const DraggableMetadataSheet({
    super.key,
    required this.visible,
    required this.onDismissed,
    required this.heightFactor,
    required this.child,
  });

  final bool visible;
  final VoidCallback onDismissed;
  final double heightFactor;
  final Widget child;

  @override
  State<DraggableMetadataSheet> createState() => _DraggableMetadataSheetState();
}

class _DraggableMetadataSheetState extends State<DraggableMetadataSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant DraggableMetadataSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _controller.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _controller.animateTo(0, curve: Curves.easeIn);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double sheetHeight) {
    final delta = details.primaryDelta ?? 0;
    _controller.value = (_controller.value - delta / sheetHeight).clamp(0.0, 1.0);
  }

  /// A flick faster than 300 decides the direction whatever the distance. A slower release goes to the side of
  /// halfway it landed on.
  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen = velocity < -300
        ? true
        : velocity > 300
        ? false
        : _controller.value > 0.5;

    if (shouldOpen) {
      _controller.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _controller.animateTo(0, curve: Curves.easeIn).whenComplete(widget.onDismissed);
    }
  }

  /// The child is mounted only while the sheet is at least partly open. An entrance animation inside it, such as the
  /// match-strength bars, then plays every time the sheet opens.
  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * widget.heightFactor;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: -sheetHeight * (1 - _controller.value),
          child: Container(
            height: sheetHeight,
            decoration: const BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) => _onDragUpdate(d, sheetHeight),
                  onVerticalDragEnd: _onDragEnd,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Center(child: _DragHandle()),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(child: _controller.value > 0 ? widget.child : const SizedBox.shrink()),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.hairline,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}
