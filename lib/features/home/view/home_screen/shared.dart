part of '../home_screen.dart';

/// The values of NativeController.homeTab.
const int _tabSearch = 0;

const int _tabCollections = 1;

const int _tabLibrary = 2;

const int _tabFaces = 3;

/// The proportions of the bar, measured off Google Photos' floating bar on a phone about 411 dp wide. It is a 58 dp
/// pill with fully rounded ends, with a 42 dp selected chip inset 8 dp inside it. The round search button is the
/// same 58 dp tall.
const double _barHeight = kFloatingBarHeight;

const double _barInset = 8;

const double _chipHeight = _barHeight - 2 * _barInset;

/// The height of the bar while several people are ticked: two rows, who is chosen and then the two buttons.
const double _tallBarHeight = 106;

class _NavTab {
  const _NavTab(this.value, this.label, this.icon, this.selectedIcon);

  final int value;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// One thing the bar can do with what is ticked: its icon, its words, which can depend on how many are ticked, and
/// what it does.
class _BarAction {
  const _BarAction({
    required this.icon,
    required this.labelFor,
    required this.onTap,
  });

  final IconData icon;
  final String Function(int chosen) labelFor;
  final VoidCallback onTap;
}

/// While choosing people (People tab) or collections (Collections tab): how many are ticked and what the bar can do
/// with them. One action fills the bar and two share it, side by side.
class _BarSelection {
  const _BarSelection({
    required this.chosen,
    required this.onCancel,
    required this.emptyLabel,
    required this.actions,
    this.faceIds = const [],
    this.summaryFor,
  });

  final int chosen;
  final VoidCallback onCancel;

  /// What the bar says until something is ticked.
  final String emptyLabel;
  final List<_BarAction> actions;

  /// The faces of the people ticked, shown stacked in the tall bar.
  final List<int> faceIds;

  /// "3 people chosen" and the like, for the tall bar.
  final String Function(int chosen)? summaryFor;

  /// True with two actions once something is ticked. The bar then grows to two rows so neither is cramped.
  bool get tall => chosen > 0 && actions.length > 1;
}

/// A damped spring toward a target that can move every frame. [ratio] below 1 overshoots a little.
class _Spring {
  _Spring(this.stiffness, this.ratio);

  final double stiffness;
  final double ratio;
  double x = 0;
  double v = 0;

  /// Moves toward [target] over [dt] seconds. [stiff] scales the stiffness for this step, for a firmer pull while
  /// settling than while following a finger. The time is split into small fixed steps, so a slow frame does not make
  /// it jump or blow up.
  void step(double target, double dt, {double stiff = 1}) {
    final k = stiffness * stiff;
    final damping = 2 * math.sqrt(k) * ratio;
    for (var left = dt; left > 0; left -= 1 / 240) {
      final h = math.min(left, 1 / 240);
      v += (k * (target - x) - damping * v) * h;
      x += v * h;
    }
  }

  void jump(double to) {
    x = to;
    v = 0;
  }

  bool restsAt(double target) => (x - target).abs() < 0.05 && v.abs() < 0.05;
}

/// How the finger on the tab pill pulls on the bar under it: toward an end (-1 left to 1 right) and up or down (-1 up
/// to 1 down), eased and on springs. The bar stretches that way (see _BarShape), and a plain tap leaves it alone.
final _barPull = ValueNotifier<(double, double)>((0, 0));

/// The bar's outline as the finger pulls on it, the way Liquid Glass bars give: always a whole capsule, grown
/// toward the pull (the near edge goes most of the way, the far one follows a little) and a touch thinner the
/// other way, as if keeping its volume. The tabs inside do not stretch. At rest, it is the plain pill.
class _BarShape {
  const _BarShape(this.side, this.lift);

  final double side;
  final double lift;

  bool get resting => side == 0 && lift == 0;

  Path path(Size size) {
    final s = side.abs();
    final l = lift.abs();
    final rect = Rect.fromLTRB(
      (side < 0 ? -12 * s : 2 * s) + 3 * l,
      (lift < 0 ? -9 * l : 2 * l) + 1.5 * s,
      size.width + (side > 0 ? 12 * s : -2 * s) - 3 * l,
      size.height + (lift > 0 ? 9 * l : -2 * l) - 1.5 * s,
    );
    final radius = math.min(_barHeight / 2, size.height / 2) * rect.height / size.height;
    return Path()..addRRect(RRect.fromRectAndRadius(resting ? Offset.zero & size : rect, Radius.circular(radius)));
  }
}

double _tanh(double x) {
  final e = math.exp(2 * x.clamp(-10.0, 10.0));
  return (e - 1) / (e + 1);
}
