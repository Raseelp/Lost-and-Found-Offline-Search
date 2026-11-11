part of '../story_viewer_screen.dart';

/// What a picture looks like from far away: its colours at the top, the middle, the bottom and the two sides (worked
/// out from a picture of 3 by 3 pixels, so it is smooth however large it is drawn), and its shape. It paints the
/// screen round the picture.
class _Look {
  const _Look({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.left,
    required this.right,
    required this.glow,
    required this.aspect,
  });

  final Color top, middle, bottom, left, right, glow;

  /// Width over height of the picture.
  final double aspect;

  static Future<_Look?> of(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 || descriptor.height <= 0) return null;
      codec = await descriptor.instantiateCodec(targetWidth: 3, targetHeight: 3);
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      Color at(int row, int col) {
        final i = (row * 3 + col) * 4;
        return Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
      }

      Color mean(List<Color> colors) {
        var r = 0, g = 0, b = 0;
        for (final c in colors) {
          r += (c.r * 255).round();
          g += (c.g * 255).round();
          b += (c.b * 255).round();
        }
        return Color.fromARGB(255, r ~/ colors.length, g ~/ colors.length, b ~/ colors.length);
      }

      final centre = mean([
        for (var r = 0; r < 3; r++)
          for (var c = 0; c < 3; c++) at(r, c),
      ]);
      return _Look(
        top: _deepen(mean([at(0, 0), at(0, 1), at(0, 2)])),
        middle: _deepen(mean([at(1, 0), at(1, 1), at(1, 2)])),
        bottom: _deepen(mean([at(2, 0), at(2, 1), at(2, 2)])),
        left: _deepen(mean([at(0, 0), at(1, 0), at(2, 0)])),
        right: _deepen(mean([at(0, 2), at(1, 2), at(2, 2)])),
        glow: HSLColor.fromColor(centre).withLightness(0.5).withSaturation(0.7).toColor(),
        aspect: descriptor.width / descriptor.height,
      );
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// The colour made darker and a little richer, so white writing on it can be read whatever the picture is.
  static Color _deepen(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness * 0.55).clamp(0.1, 0.32))
        .withSaturation((hsl.saturation * 1.1).clamp(0.0, 0.85))
        .toColor();
  }
}
