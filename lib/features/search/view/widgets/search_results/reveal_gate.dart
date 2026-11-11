part of '../search_results.dart';

/// Gates the swap from placeholder to real content behind _minimumRevealDelay (first time only) and a plain crossfade
/// (every time). The timer starts at mount, not at data arrival, so slow bytes are never held up any further.
class _RevealGate extends StatefulWidget {
  const _RevealGate({
    required this.cacheKey,
    required this.ready,
    required this.placeholder,
    required this.child,
  });

  final String cacheKey;
  final bool ready;
  final Widget placeholder;
  final Widget child;

  @override
  State<_RevealGate> createState() => _RevealGateState();
}

class _RevealGateState extends State<_RevealGate> {
  bool _delayElapsed = false;

  @override
  void initState() {
    super.initState();
    _startOrSkipDelay();
  }

  /// A different item can land in the same slot, from a fresh search or the bento pattern reshuffling which index gets
  /// which tile. Only a different cache key re-arms the delay.
  @override
  void didUpdateWidget(_RevealGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _delayElapsed = false;
      _startOrSkipDelay();
    }
  }

  void _startOrSkipDelay() {
    if (_revealedTileKeys.contains(widget.cacheKey)) {
      _delayElapsed = true;
      return;
    }
    Future.delayed(_minimumRevealDelay, () {
      if (!mounted) return;
      setState(() => _delayElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reveal = widget.ready && _delayElapsed;
    if (reveal) _revealedTileKeys.add(widget.cacheKey);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey(reveal),
        child: reveal ? widget.child : widget.placeholder,
      ),
    );
  }
}

/// However fast a photo's bytes arrive, even if already in memory on the first frame, the placeholder stays up for at
/// least this long the first time its cache key is shown, so a load always reads as a deliberate reveal rather than a
/// jarring pop-in. It is paid once per cache key (see _revealedTileKeys).
const Duration _minimumRevealDelay = Duration(milliseconds: 450);

/// A cache key that has made it through this gate once stays revealed for good. It is kept in memory only, cleared on
/// app restart, because it is purely cosmetic. Scrolling a tile out of view and back, or any later rebuild, never
/// replays the reveal for a photo the user has already been shown.
final Set<String> _revealedTileKeys = <String>{};
