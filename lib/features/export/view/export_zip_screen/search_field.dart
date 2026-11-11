part of '../export_zip_screen.dart';

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.initial,
    required this.chosen,
    required this.onChanged,
  });

  final String initial;
  final int chosen;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppSearchField(
      controller: _text,
      hint: 'Search collections and people',
      onChanged: widget.onChanged,
      trailingWhenEmpty: widget.chosen > 0
          ? Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text(
                '${widget.chosen} chosen',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }
}
