part of '../video_full_screen.dart';

class _ToastData {
  const _ToastData(this.title, this.subtitle, this.faces);

  final String title;
  final String? subtitle;

  /// Faces to show at the left (a scan's result): up to three, overlapping.
  final List<int> faces;
}
