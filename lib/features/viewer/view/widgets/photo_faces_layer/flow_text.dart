part of '../photo_faces_layer.dart';

/// The line of text under the photo ("Tap a face to see who", "Found 12 faces · identifying"). No box around it: the
/// words carry the effect. A soft highlight in the app's colours keeps drifting through the letters, and whenever the
/// words change the next ones rise into place letter by letter. It stays legible over any photo through a gentle
/// shadow, not a container.
class _FlowText extends StatefulWidget {
  const _FlowText(this.text, {this.leading});

  final String text;
  final Widget? leading;

  @override
  State<_FlowText> createState() => _FlowTextState();
}

class _FlowTextState extends State<_FlowText> with TickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))..forward();

  /// With motion off the highlight stays put.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessCalm(context, _shine);
  }

  @override
  void didUpdateWidget(covariant _FlowText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _in.forward(from: 0);
  }

  @override
  void dispose() {
    _shine.dispose();
    _in.dispose();
    super.dispose();
  }

  /// The text is tinted by the moving highlight, and beneath it the same letters are in nothing but a soft shadow,
  /// because a shadow put on the tinted text would be tinted too. Each letter starts a little after the one before it.
  /// The letters are rebuilt only while the words rise in, and afterwards just the highlight moves, instead of about
  /// 80 widgets a frame. The highlight slides from fully off the left edge to fully off the right, once per loop.
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.labelLarge;
    final size = (base?.fontSize ?? 14) + 1;
    final fill = base?.copyWith(color: FacePalette.white, fontSize: size, fontWeight: FontWeight.w600);
    final shade = base?.copyWith(
      color: AppColors.transparent,
      fontSize: size,
      fontWeight: FontWeight.w600,
      shadows: [
        Shadow(color: FacePalette.black.withValues(alpha: 0.6), blurRadius: 9),
        Shadow(color: FacePalette.black.withValues(alpha: 0.4), blurRadius: 2, offset: const Offset(0, 1)),
      ],
    );
    final letters = widget.text.split('');

    Widget row(TextStyle? style) {
      final n = letters.length;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var k = 0; k < n; k++)
            () {
              final start = n <= 1 ? 0.0 : k / (n - 1) * 0.55;
              final o = Curves.easeOut.transform(Interval(start, start + 0.45).transform(_in.value));
              return Opacity(
                opacity: o,
                child: Transform.translate(offset: Offset(0, 8 * (1 - o)), child: Text(letters[k], style: style)),
              );
            }(),
        ],
      );
    }

    return AnimatedBuilder(
      animation: _in,
      builder: (context, _) {
        final shadeRow = row(shade);
        final fillRow = row(fill);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.leading != null) ...[widget.leading!, const SizedBox(width: AppSpacing.sm + 2)],
            Stack(
              children: [
                shadeRow,
                AnimatedBuilder(
                  animation: _shine,
                  child: fillRow,
                  builder: (context, child) => ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (rect) => LinearGradient(
                      colors: const [
                        FacePalette.whiteA78,
                        FacePalette.whiteA78,
                        FacePalette.mint200,
                        FacePalette.white,
                        FacePalette.pink100,
                        FacePalette.whiteA78,
                        FacePalette.whiteA78,
                      ],
                      stops: const [0.0, 0.3, 0.42, 0.5, 0.58, 0.7, 1.0],
                      transform: _Slide(_shine.value * 2 - 1),
                    ).createShader(rect),
                    child: child,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A slide for a gradient: moves it sideways by [shift] of its own width.
class _Slide extends GradientTransform {
  const _Slide(this.shift);

  final double shift;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(shift * bounds.width, 0, 0);
}
