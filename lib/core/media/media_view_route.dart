import 'package:flutter/material.dart';

/// The transition for opening and closing the photo and video viewers: the whole screen fades in while growing very
/// slightly, and the same animation plays backwards when it closes. It is a plain [PageRouteBuilder] and not a Hero.
/// A Hero flight from the tapped tile to the full screen flickered and barely played on modest phones, because the
/// grid's tile animations and the video player starting all wanted the same frame.
Route<T> mediaViewRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
