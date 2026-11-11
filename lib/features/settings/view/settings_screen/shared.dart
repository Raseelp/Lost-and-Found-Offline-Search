part of '../settings_screen.dart';

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ColoredBox(
        color: AppColors.pearl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.dividerSoft),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _RowChevron extends StatelessWidget {
  const _RowChevron();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: AppColors.ink48,
    );
  }
}

/// A settings row that does something when tapped.
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.chevron = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Shows an arrow on the right, for a row that opens another screen or app.
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: _SettingsRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          trailing: chevron ? const _RowChevron() : null,
        ),
      ),
    );
  }
}
