part of '../person_menu.dart';

class _OrbitButton extends StatelessWidget {
  const _OrbitButton({required this.action, required this.onTap});

  final _Orbit action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final quiet = action.fix;
    final color = action.danger ? AppColors.danger : (quiet ? AppColors.ink48 : AppColors.ink80);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: action.label,
      onTap: onTap,
      excludeSemantics: true,
      child: _column(color),
    );
  }

  Widget _column(Color color) {
    final quiet = action.fix;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppColors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: quiet ? AppColors.canvas : AppColors.pearl,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
                boxShadow: quiet
                    ? null
                    : [BoxShadow(color: AppColors.ink.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Icon(action.icon, size: 18, color: color),
            ),
          ),
        ),
        const SizedBox(height: 3),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            action.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: action.danger ? AppColors.danger : AppColors.ink48),
          ),
        ),
      ],
    );
  }
}
