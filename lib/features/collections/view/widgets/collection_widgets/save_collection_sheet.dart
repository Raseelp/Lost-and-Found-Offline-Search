part of '../collection_widgets.dart';

class _SaveCollectionSheet extends StatefulWidget {
  const _SaveCollectionSheet({
    required this.title,
    required this.initialName,
    required this.initialQuery,
    required this.showQuery,
    required this.onSave,
  });

  final String title;
  final String initialName;
  final String? initialQuery;
  final bool showQuery;
  final Future<void> Function(String name, String query, List<int> personIds) onSave;

  @override
  State<_SaveCollectionSheet> createState() => _SaveCollectionSheetState();
}

/// The sheet's content scrolls, so a tall keyboard or a long "@name and @name2" query cannot push it taller than the
/// space left above it, and the Save button stays reachable.
class _SaveCollectionSheetState extends State<_SaveCollectionSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  /// The same "@name" recognition the search box uses, so a collection made from the Collections page, and not only
  /// one saved from an existing search, can filter by person too. The people provider mirrors how AppSearchController
  /// builds its searchTextController.
  late final MentionTextEditingController _query = MentionTextEditingController(
    peopleProvider: () =>
        Get.isRegistered<FacesController>() ? Get.find<FacesController>().people : const [],
  )..text = widget.initialQuery ?? '';

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    super.dispose();
  }

  bool get _canSave =>
      widget.showQuery ? _query.text.trim().isNotEmpty : _name.text.trim().isNotEmpty;

  /// Closes the sheet at once and does the work behind it. The new card appears in the list and plays its own
  /// "finding matches" animation, so there is nothing to wait on here.
  void _save() {
    final query = widget.showQuery ? _query.queryWithoutMention : (widget.initialQuery ?? '');
    final personIds = widget.showQuery
        ? _query.recognizedPeople.map((p) => p.id).toList()
        : const <int>[];
    final name = _name.text.trim();
    final onSave = widget.onSave;
    Navigator.of(context).pop();
    unawaited(onSave(name, query, personIds));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.base,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(widget.title, style: textTheme.titleMedium),
              if (!widget.showQuery &&
                  (widget.initialQuery ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Finds: ${widget.initialQuery}',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                ),
              ],
              const SizedBox(height: AppSpacing.base),
              if (widget.showQuery) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: MentionInputField(
                    controller: _query,
                    autofocus: widget.initialQuery == null,
                    onChanged: () => setState(() {}),
                    style: textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'What to look for, e.g. "dog" or "@name at the beach"',
                      hintStyle: const TextStyle(color: AppColors.ink48),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              _Field(
                controller: _name,
                hint: widget.showQuery
                    ? 'Name (optional), e.g. "Mittu"'
                    : 'Name, e.g. "Mittu"',
                autofocus: !widget.showQuery,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: _canSave ? AppColors.primary : AppColors.hairline,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: InkWell(
                    onTap: _canSave ? _save : null,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Center(
                        child: Text(
                          'Save',
                          style: textTheme.titleSmall?.copyWith(
                            color: _canSave
                                ? AppColors.onPrimary
                                : AppColors.ink48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: (_) => onChanged(),
        textCapitalization: TextCapitalization.sentences,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.ink48),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        ),
      ),
    );
  }
}
