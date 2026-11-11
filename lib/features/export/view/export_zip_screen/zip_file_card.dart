part of '../export_zip_screen.dart';

class _ZipFileCard extends StatefulWidget {
  const _ZipFileCard({required this.c});

  final ExportController c;

  @override
  State<_ZipFileCard> createState() => _ZipFileCardState();
}

class _ZipFileCardState extends State<_ZipFileCard> {
  late final TextEditingController _name = TextEditingController(
    text: widget.c.zipName,
  );
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final textTheme = Theme.of(context).textTheme;
    if (!_focus.hasFocus && _name.text != c.zipName) _name.text = c.zipName;
    return _Card(
      title: 'The zip',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            focusNode: _focus,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            onChanged: c.setName,
            textInputAction: TextInputAction.done,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'Name',
              counterText: '',
              suffixText: '.zip',
              filled: true,
              fillColor: AppColors.canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: c.pickFolder,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_outlined,
                    size: 20,
                    color: AppColors.ink80,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Save in',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.ink48,
                          ),
                        ),
                        Text(
                          c.folderUri != null
                              ? (c.folderLabel ?? 'Chosen folder')
                              : (c.downloadsAvailable
                                    ? 'Downloads › Lost & Found'
                                    : 'Choose a folder'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: c.needsFolder ? AppColors.danger : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Change',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (c.folderUri != null && c.downloadsAvailable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: c.useDownloads,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Use Downloads instead'),
              ),
            ),
          const Divider(height: AppSpacing.xl, color: AppColors.hairline),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('List of what is inside', style: textTheme.bodyMedium),
                    Text(
                      'A small list.json with each file\'s name, date and size',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink48,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: c.includeList, onChanged: c.setIncludeList),
            ],
          ),
        ],
      ),
    );
  }
}
