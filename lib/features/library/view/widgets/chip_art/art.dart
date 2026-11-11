part of '../chip_art.dart';

class _Art {
  _Art(this.bounds, this.picture, this.image);

  final Rect bounds;
  final ui.Picture picture;
  final ui.Image? image;

  void paint(Canvas canvas, [Paint? paint]) {
    final img = image;
    if (img == null) {
      canvas.drawPicture(picture);
      return;
    }
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      bounds,
      paint ?? (Paint()..filterQuality = FilterQuality.medium),
    );
  }

  /// Only the part of the picture inside [region] (sheet coordinates), drawn where it belongs:
  /// much cheaper than drawing all of it under a clip when only a small part is wanted.
  void paintRegion(Canvas canvas, Rect region, Paint paint) {
    final r = region.intersect(bounds);
    if (r.isEmpty) return;
    final img = image;
    if (img == null) {
      canvas.save();
      canvas.clipRect(r);
      canvas.drawPicture(picture);
      canvas.restore();
      return;
    }
    final sx = img.width / bounds.width, sy = img.height / bounds.height;
    canvas.drawImageRect(
      img,
      Rect.fromLTRB((r.left - bounds.left) * sx, (r.top - bounds.top) * sy, (r.right - bounds.left) * sx, (r.bottom - bounds.top) * sy),
      r,
      paint,
    );
  }

  void dispose() => image?.dispose();
}
