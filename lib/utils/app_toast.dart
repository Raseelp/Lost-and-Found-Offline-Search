import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/floating_bar.dart';
import 'package:lost_and_found/utils/motion.dart';

/// The one way the app says something for a moment ("Copied.", "Merged two people." with an Undo). Every toast
/// comes from here, so they all look the same: a light frosted card that sits clear of the floating bar. A new one
/// replaces the one on screen. It needs no BuildContext, so it is safe to call after a screen has gone.
///
/// Wording: a sentence that ends with a full stop, in the app's plain voice ("Couldn't copy.", not "Error").
///
/// A toast with a button (Undo, View) shows how much time is left as a thin line along its lower edge that
/// shrinks. With the phone's "Remove animations" on nothing slides or shrinks: the toast just appears and goes.
class AppToast {
  const AppToast._();

  static OverlayEntry? _entry;

  /// Shows [message]. With [actionLabel] and [onAction] it has a button, and the time left is drawn as a line.
  static void show(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final navigator = Get.key.currentState;
    final overlay = navigator?.overlay;
    if (navigator == null || overlay == null) return;
    // The floating bar is only there on the home screen, with nothing on top of it: anywhere else the message
    // sits at the bottom of the screen.
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
      // An entry whose overlay is already gone (the app restarted, say) has nothing left to take away.
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
  // The slide in and out.
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 280),
    animationBehavior: AnimationBehavior.preserve,
  );

  // The time the toast stays: 0 when it appears, 1 when it goes (the line shrinks with it).
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: widget.duration,
    animationBehavior: AnimationBehavior.preserve,
  );

  bool _started = false;
  bool _gone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Someone using a screen reader or switch access needs longer to get to a button.
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // Just above the keyboard when it is up; clear of the floating bar when that is there; else near the bottom.
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
      // On a wide screen the card stays a readable width, in the middle.
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
            // Swiped sideways, it goes.
            child: Dismissible(
              key: const ValueKey('app-toast'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) {
                _gone = true;
                widget.onGone();
              },
              // Read out when it appears, for a screen reader.
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
