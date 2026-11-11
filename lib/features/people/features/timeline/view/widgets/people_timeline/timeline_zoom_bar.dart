part of '../people_timeline.dart';

/// How much of the years to show, as four buttons: everything, five years, one year, three months.
class TimelineZoomBar extends StatelessWidget {
  const TimelineZoomBar({super.key, required this.window});

  final TimelineWindow window;

  /// The number of years each button shows (null: everything).
  static const _steps = [
    ('All', null),
    ('5 years', 5.0),
    ('1 year', 1.0),
    ('3 months', 0.25),
  ];

  bool _isActive(double? years) {
    if (window.width <= 0) return false;
    if (years == null) return window.ppm <= window.minPpm * 1.04;
    return (window.years - years).abs() / years < 0.12 && window.ppm > window.minPpm * 1.04;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: window,
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          children: [
            for (final (label, years) in _steps)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _isActive(years),
                  label: years == null ? 'Show all years' : 'Show $label',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (years == null) {
                        window.showAll();
                      } else {
                        window.showYears(years);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _isActive(years) ? AppColors.canvas : AppColors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: _isActive(years) ? AppColors.hairline : AppColors.transparent),
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        style: textTheme.bodySmall?.copyWith(
                          color: _isActive(years) ? AppColors.primary : AppColors.ink80,
                          fontWeight: _isActive(years) ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
