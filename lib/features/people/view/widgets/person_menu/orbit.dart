part of '../person_menu.dart';

class _Orbit {
  const _Orbit({
    required this.icon,
    required this.label,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.demo,
    required this.onTap,
    this.danger = false,
    this.fix = false,
  });

  final IconData icon;
  /// The short caption under the button: the situation it is for.
  final String label;
  /// The bubble's heading, asked as a question about the person.
  final String title;
  /// One short line under the demo.
  final String message;
  /// The bubble's action button.
  final String confirmLabel;
  /// The little film the bubble plays of what it does.
  final PersonDemoKind demo;
  /// One of the three that fix the app's mistakes, kept behind "Fix mistakes".
  final bool fix;
  final VoidCallback onTap;
  final bool danger;
}
