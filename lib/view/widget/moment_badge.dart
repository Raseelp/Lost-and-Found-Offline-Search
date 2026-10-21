import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/palettes/moment_palette.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';

/// The paper of the moment marks: a warm cream, readable on a bright or a dark photo.

/// What the photo with [uri] is, if it is one of the moments (see [FacesController.momentFor]), looked
/// up again whenever the people or their dates change. Nothing when it is not.
class _MomentLookup extends StatelessWidget {
  const _MomentLookup({required this.uri, required this.builder});

  final String? uri;
  final Widget Function(PhotoMoment moment) builder;

  @override
  Widget build(BuildContext context) {
    if (uri == null || !Get.isRegistered<FacesController>()) {
      return const SizedBox.shrink();
    }
    final faces = Get.find<FacesController>();
    return ValueListenableBuilder<int>(
      valueListenable: faces.momentsRevision,
      builder: (context, _, __) {
        final moment = faces.momentFor(uri);
        return moment == null ? const SizedBox.shrink() : builder(moment);
      },
    );
  }
}

/// The mark on a photo tile that is a moment: a little cream bookmark hanging from the top edge, with
/// the sparkle of the story button on it (just the ribbon on a very small tile). Put it in a [Stack],
/// at the top, a few pixels in from a corner.
class MomentTag extends StatelessWidget {
  const MomentTag({super.key, required this.uri, this.compact = false});

  final String? uri;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _MomentLookup(
      uri: uri,
      builder: (moment) {
        final width = compact ? 9.0 : 20.0, height = compact ? 14.0 : 29.0;
        return Semantics(
          label: moment.title,
          child: ExcludeSemantics(
            child: SizedBox(
              width: width,
              height: height,
              child: CustomPaint(
                painter: _RibbonPainter(),
                child: compact
                    ? null
                    : const Align(
                        alignment: Alignment(0, -0.5),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 11,
                          color: AppColors.primary,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final notch = w * 0.42;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h - notch)
      ..lineTo(0, h)
      ..close();
    canvas.drawShadow(path, AppColors.shadow, 3, false);
    canvas.drawPath(path, Paint()..color = MomentPalette.paper);
    // A hairline, so it still shows on a cream-coloured photo.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = AppColors.scrim.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter old) => false;
}

/// What a moment says over an opened photo or video, like the caption of a film: the people's faces,
/// the date in small capitals, and the moment itself in italics, on a soft shade that comes in from
/// the edge. It slides in once the photo is up. Nothing when the photo is not a moment.
class MomentCaption extends StatelessWidget {
  const MomentCaption({
    super.key,
    required this.uri,
    this.outer = EdgeInsets.zero,
  });

  final String? uri;

  /// Room around it (only there when it is).
  final EdgeInsets outer;

  @override
  Widget build(BuildContext context) {
    return _MomentLookup(
      uri: uri,
      builder: (moment) => Padding(
        padding: outer,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(uri),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset((1 - t) * -22, 0),
                child: child,
              ),
            ),
            child: _LowerThird(moment: moment),
          ),
        ),
      ),
    );
  }
}

class _LowerThird extends StatelessWidget {
  const _LowerThird({required this.moment});

  final PhotoMoment moment;

  static const _shadow = [Shadow(color: MomentPalette.blackA60, blurRadius: 6)];

  @override
  Widget build(BuildContext context) {
    final who = moment.names;
    final faces = moment.people.take(3).toList();
    return Semantics(
      label: '${moment.title}. ${who == null ? '' : '$who. '}${moment.when}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Stack(
            children: [
              // The shade: dark at the edge of the screen, fading out to the right, and fading
              // out above and below too, so it has no edges.
              Positioned.fill(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.transparent,
                      AppColors.scrim,
                      AppColors.scrim,
                      AppColors.transparent,
                    ],
                    stops: [0, 0.3, 0.7, 1],
                  ).createShader(rect),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.scrim.withValues(alpha: 0.62),
                          AppColors.scrim.withValues(alpha: 0.44),
                          AppColors.scrim.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                // The right side is only shade: it carries the fade out to nothing.
                padding: const EdgeInsets.fromLTRB(16, 20, 40, 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (faces.isNotEmpty) ...[
                      SizedBox(
                        width: 34.0 + (faces.length - 1) * 22,
                        height: 34,
                        child: Stack(
                          children: [
                            for (var i = 0; i < faces.length; i++)
                              Positioned(
                                left: i * 22.0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: MomentPalette.paper,
                                      width: 1.6,
                                    ),
                                  ),
                                  child: FaceAvatar(
                                    faceId: faces[i].coverFaceId,
                                    size: 34,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 11,
                                color: MomentPalette.paper,
                                shadows: _shadow,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                moment.when.toUpperCase(),
                                style: const TextStyle(
                                  color: MomentPalette.paper,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                  height: 1.2,
                                  shadows: _shadow,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            moment.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.instrumentSerif(
                              color: AppColors.onMedia,
                              fontSize: 19.5,
                              fontStyle: FontStyle.italic,
                              height: 1.1,
                              shadows: _shadow,
                            ),
                          ),
                          if (who != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.onMedia.withValues(
                                  alpha: 0.78,
                                ),
                                fontSize: 12,
                                height: 1.2,
                                shadows: _shadow,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
