import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/floating_bar.dart';
import 'package:lost_and_found/utils/motion.dart';

/// Shows every short message in the app ("Copied.", "Merged two people." with an Undo) as one light frosted card. A
/// message replaces the one on screen. It needs no BuildContext, so it can be called after a screen has gone. A
/// message with a button shows the time left as a thin line that shrinks, and with "Remove animations" on nothing
/// slides or shrinks.
class AppToast {
  const AppToast._();

  static OverlayEntry? _entry;

  /// Shows [message]. With [actionLabel] and [onAction] it has a button and the time left is drawn as a line. The
  /// card sits above the floating bar when the home screen shows with nothing on top of it, and at the bottom of the
  /// screen anywhere else.
  static void show(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final navigator = Get.key.currentState;
    final overlay = navigator?.overlay;
    if (navigator == null || overlay == null) return;
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final aboveBar = FloatingBarPresence.shown && (top?.isFirst ?? false);
    _remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastCard(
        message: message,
        aboveBar: aboveBar,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        onGone: () {
          if (_entry == entry) _entry = null;
          _dispose(entry);
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// Takes the toast on screen away at once.
  static void _remove() {
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    _dispose(entry);
  }

  static void _dispose(OverlayEntry entry) {
    try {
      entry.remove();
      entry.dispose();
    } catch (_) {
      // The entry's overlay is already gone, so there is nothing to remove.
    }
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.message,
    required this.aboveBar,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onGone,
  });

  final String message;

  /// The floating bar is under it: it sits above the bar rather than at the bottom of the screen.
  final bool aboveBar;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onGone;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with TickerProviderStateMixin {
  /// The slide in and out.
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 280),
    animationBehavior: AnimationBehavior.preserve,
  );

  /// How much of its time the toast has used: 0 when it appears, 1 when it goes. The line shrinks with it.
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: widget.duration,
    animationBehavior: AnimationBehavior.preserve,
  );

  bool _started = false;
  bool _gone = false;

  /// Starts the slide in. A toast with a button stays twice as long when a screen reader or switch access is on,
  /// since reaching a button takes longer.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final slow = MediaQuery.accessibleNavigationOf(context) && widget.actionLabel != null;
    if (slow) _life.duration = widget.duration * 2;
    if (calm(context)) {
      _in.value = 1;
      _life.forward().whenComplete(_leave);
    } else {
      _in.forward().whenComplete(() {
        if (mounted) _life.forward().whenComplete(_leave);
      });
    }
  }

  void _leave() {
    if (!mounted || _gone) return;
    _gone = true;
    if (calm(context)) {
      widget.onGone();
    } else {
      _in.reverse().whenComplete(widget.onGone);
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _life.dispose();
    super.dispose();
  }

  /// Places the card just above the keyboard when it is up, above the floating bar when that is showing, and near the
  /// bottom of the screen otherwise. On a wide screen it stays 520 wide and centred. Swiping it sideways dismisses
  /// it, and a screen reader reads it out when it appears.
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final bottom = keyboard > 0
        ? keyboard + 16
        : widget.aboveBar
            ? media.viewPadding.bottom + kFloatingBarBottomGap + kFloatingBarHeight + 32
            : media.viewPadding.bottom + 24;
    final textTheme = Theme.of(context).textTheme;
    final showLine = widget.actionLabel != null && !calm(context);

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.16), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(18, 12, widget.actionLabel == null ? 18 : 10, showLine ? 18 : 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.message,
                        style: textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.35, color: AppColors.ink),
                      ),
                    ),
                    if (widget.actionLabel != null)
                      TextButton(
                        onPressed: () {
                          if (_gone) return;
                          _gone = true;
                          widget.onGone();
                          widget.onAction?.call();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: const Size(48, 40),
                        ),
                        child: Text(widget.actionLabel!),
                      ),
                  ],
                ),
              ),
              if (showLine)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 7,
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _life,
                      builder: (context, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (1 - _life.value).clamp(0.0, 1.0),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Positioned(
      left: 20 + media.viewPadding.left,
      right: 20 + media.viewPadding.right,
      bottom: bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AnimatedBuilder(
            animation: _in,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_in.value);
              return Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
              );
            },
            child: Dismissible(
              key: const ValueKey('app-toast'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) {
                _gone = true;
                widget.onGone();
              },
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Material(type: MaterialType.transparency, child: card),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
