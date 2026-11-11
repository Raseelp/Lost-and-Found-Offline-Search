part of '../timeline_preview.dart';

/// A picture of the timeline, shown as soon as there is anything of it. The small version shows at once, then the
/// large one when [large] is set and it has arrived, then the sharp one when [sharp] is set, for a picture shown big.
/// Each better version fades in over the one before, so nothing jumps or blinks while it sharpens.
class PreviewImage extends StatefulWidget {
  const PreviewImage({
    super.key,
    required this.photo,
    required this.loader,
    this.large = false,
    this.sharp = false,
    this.alignment = Alignment.center,
    this.fill = AppColors.parchment,
  });

  final PreviewPhoto photo;
  final PreviewLoader loader;
  final bool large;

  /// Also fetch the biggest version, once the large one is in.
  final bool sharp;
  final Alignment alignment;

  /// What shows until the picture is there.
  final Color fill;

  @override
  State<PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<PreviewImage> {
  /// What is on show, and a better version fading in over it.
  Uint8List? _shown;
  Uint8List? _incoming;

  /// True when the incoming version is decoded, so it is at least starting to show.
  bool _incomingReady = false;

  /// The best version either of them is: 0 nothing yet, 1 small, 2 large, 3 sharp.
  int _top = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PreviewImage old) {
    super.didUpdateWidget(old);
    if (old.photo.cacheKey != widget.photo.cacheKey) {
      _shown = null;
      _incoming = null;
      _incomingReady = false;
      _top = 0;
    }
    if (old.photo.cacheKey != widget.photo.cacheKey || old.large != widget.large || old.sharp != widget.sharp) _resolve();
  }

  /// Takes the best version in memory and asks for the better ones. A version already in memory is shown at once if
  /// there is nothing yet, else it fades in over what is there.
  void _resolve() {
    final photo = widget.photo, loader = widget.loader;
    final wantLarge = widget.large || widget.sharp;
    final sharp = widget.sharp ? loader.peek(photo, large: true, sharp: true) : null;
    final large = wantLarge ? loader.peek(photo, large: true) : null;
    final small = loader.peek(photo, large: false);
    final best = sharp ?? large ?? small;
    final rank = sharp != null ? 3 : (large != null ? 2 : (small != null ? 1 : 0));
    if (best != null && rank > _top) {
      _top = rank;
      if (_shown == null && _incoming == null) {
        _shown = best;
      } else {
        _incoming = best;
        _incomingReady = false;
      }
    }

    final key = photo.cacheKey;
    if (_top < 1) _fetch(key, 1);
    if (wantLarge && _top < 2) {
      _fetch(key, 2);
    } else if (widget.sharp && _top == 2) {
      _fetch(key, 3);
    }
  }

  /// Asks the loader for version [rank] of the photo with [key]. The sharp version follows the large one and is not
  /// asked for at the same time, because a picture that is only passing by never needs it.
  void _fetch(String key, int rank) {
    bool wanted() =>
        mounted && widget.photo.cacheKey == key && (rank <= 1 || widget.large || widget.sharp) && (rank < 3 || widget.sharp);
    widget.loader.get(widget.photo, large: rank >= 2, sharp: rank == 3, wanted: wanted).then((b) {
      if (b == null || !wanted()) return;
      _deliver(b, rank);
      if (rank == 2 && widget.sharp) _fetch(key, 3);
    });
  }

  /// Fades the latest version in over what is shown. A version that is already showing becomes what is shown. One that
  /// has not been decoded yet is dropped, because it would leave a hole where the picture was.
  void _deliver(Uint8List bytes, int rank) {
    if (rank <= _top) return;
    setState(() {
      _top = rank;
      if (_incoming != null && _incomingReady) _shown = _incoming;
      _incoming = bytes;
      _incomingReady = false;
    });
  }

  /// Called when the fade of the latest version has ended. It becomes what is shown.
  void _promote() {
    if (!mounted || _incoming == null) return;
    setState(() {
      _shown = _incoming;
      _incoming = null;
      _incomingReady = false;
    });
  }

  Widget _image(Uint8List bytes) {
    return Image.memory(
      bytes,
      key: ObjectKey(bytes),
      fit: BoxFit.cover,
      alignment: widget.alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      width: double.infinity,
      height: double.infinity,
      frameBuilder: (context, child, frame, sync) {
        final ready = frame != null || sync;
        if (ready && identical(bytes, _incoming)) _incomingReady = true;
        return AnimatedOpacity(
          opacity: ready ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          onEnd: _promote,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown, incoming = _incoming;
    return ColoredBox(
      color: widget.fill,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shown != null) _image(shown),
          if (incoming != null) _image(incoming),
        ],
      ),
    );
  }
}
