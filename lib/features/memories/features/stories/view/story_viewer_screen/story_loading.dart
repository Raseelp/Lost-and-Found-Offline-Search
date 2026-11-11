part of '../story_viewer_screen.dart';

/// What is on screen while a picture is on its way: the colours of the last picture of the story (or of the face or
/// cover of the ring), breathing a little darker and lighter, with a pale band of light sliding across. When the
/// picture arrives it fades in over it. Only colours are drawn, with no blurred picture, so there is nothing to work
/// out again and again while a window is opening. With motion off the colours alone show, still. Only the breathing and
/// the band move, and they are a layer of their own.
class _StoryLoading extends StatefulWidget {
  const _StoryLoading({this.look});

  final _Look? look;

  @override
  State<_StoryLoading> createState() => _StoryLoadingState();
}

class _StoryLoadingState extends State<_StoryLoading> with SingleTickerProviderStateMixin {
  late final AnimationController _run;

  @override
  void initState() {
    super.initState();
    _run = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (calm(context)) {
      _run
        ..stop()
        ..value = 0;
    } else if (!_run.isAnimating) {
      _run.repeat();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _Ambient(look: widget.look),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _run,
            builder: (context, _) {
              final t = _run.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: AppColors.scrim.withValues(alpha: 0.12 + 0.1 * math.sin(t * 2 * math.pi))),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-2.2 + 4.4 * t, -1),
                        end: Alignment(-0.8 + 4.4 * t, 1),
                        colors: [
                          AppColors.onMedia.withValues(alpha: 0),
                          AppColors.onMedia.withValues(alpha: 0.14),
                          AppColors.onMedia.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
