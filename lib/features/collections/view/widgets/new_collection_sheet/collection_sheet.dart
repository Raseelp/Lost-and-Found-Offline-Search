part of '../new_collection_sheet.dart';

class _CollectionSheet extends StatefulWidget {
  const _CollectionSheet({required this.controller, this.editing});

  final CollectionsController controller;

  /// The collection being changed, or null for a new one.
  final SmartCollection? editing;

  @override
  State<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends State<_CollectionSheet> {
  /// Names typed in the words are recognised as people, the same way the search box does it.
  late final MentionTextEditingController _query = MentionTextEditingController(
    peopleProvider: () => Get.isRegistered<FacesController>() ? Get.find<FacesController>().people : const [],
  );
  final TextEditingController _name = TextEditingController();
  /// True once the name was typed over. Until then the name follows the words.
  bool _nameTyped = false;

  final List<String> _more = [];
  final TextEditingController _moreField = TextEditingController();
  final FocusNode _moreFocus = FocusNode();
  bool _addingMore = false;

  /// Set when the collection is made from a photo instead of words.
  String? _photoUri;
  Uint8List? _photoBytes;

  String _contentMode = 'both';

  SmartCollection? get _editing => widget.editing;
  bool get _isEdit => _editing != null;
  bool get _isPhotoEdit => _editing?.isPhotos ?? false;

  /// The words as the sheet opened. Words that are left alone are saved exactly as they were stored, whatever the
  /// field's name recognition makes of them: a name in them that was never a filter must not become one now, and a
  /// built-in keeps its own several phrasings, because the sheet shows only the short phrase.
  String _startText = '';

  bool get _wordsTouched => _query.text != _startText;

  /// People of the collection that the words cannot name again (no name, or the same name as someone else), kept so
  /// that saving does not drop them.
  List<int> _keptIds = const [];

  CollectionPreview? _preview;
  bool _previewing = false;
  int _previewToken = 0;
  Timer? _previewTimer;
  final Map<String, Uint8List> _thumbs = {};

  /// Leaving the field for another way of saying it keeps what was typed in it, except when the sheet itself is going
  /// away.
  @override
  void initState() {
    super.initState();
    _moreFocus.addListener(() {
      if (mounted && !_moreFocus.hasFocus && _addingMore) _commitMore();
    });
    if (_isEdit) _prefill(_editing!);
  }

  /// Fills the sheet with [c] as it is. People it already filters by are put back in front of the words, the same way
  /// the search's own lastQueryWithMentions does, and the field's name recognition picks them up at once. A collection
  /// of people only keeps no words. Other phrasings are listed only for a collection you made, because a built-in's
  /// several phrasings are an implementation detail.
  void _prefill(SmartCollection c) {
    _contentMode = c.contentMode;
    _nameTyped = true;
    _name.text = c.name;
    if (c.isPhotos) {
      final uri = c.seedUri;
      if (uri != null) {
        unawaited(
          MediaService()
              .loadThumbnail(uri: uri, isVideo: c.seedTimestampMs != null, timestampMs: c.seedTimestampMs ?? 0, size: 240)
              .then((bytes) {
                if (mounted) setState(() => _photoBytes = bytes);
              })
              .catchError((_) {}),
        );
      }
      return;
    }
    final people = Get.isRegistered<FacesController>() ? Get.find<FacesController>().people : const <Person>[];
    final names = [
      for (final p in people)
        if (c.personIds.contains(p.id) && (p.name ?? '').trim().isNotEmpty) p.name!.trim(),
    ];
    final words = c.queryText == 'a photo' && c.personIds.isNotEmpty ? '' : c.queryText;
    _query.text = [if (names.isNotEmpty) names.join(' and '), if (words.isNotEmpty) words].join(' ');
    _startText = _query.text;
    final recognized = {for (final p in _query.recognizedPeople) p.id};
    _keptIds = [
      for (final id in c.personIds)
        if (!recognized.contains(id)) id,
    ];
    if (!c.isBuiltIn) _more.addAll(c.prompts.skip(1).take(_maxMore));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _schedulePreview();
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _query.dispose();
    _name.dispose();
    _moreField.dispose();
    _moreFocus.dispose();
    super.dispose();
  }

  bool get _hasWords => _query.text.trim().isNotEmpty;
  bool get _photoMode => _photoUri != null || _isPhotoEdit;
  bool get _hasInput => _photoMode || _hasWords || _keptIds.isNotEmpty;

  /// The phrases the collection is made of as the sheet stands. Words left alone keep what is stored (a built-in keeps
  /// all its phrasings), with the ones added here after them.
  List<String> get _promptsNow {
    final c = _editing;
    if (c != null && !_wordsTouched) return c.isBuiltIn ? [...c.prompts, ..._more] : [c.prompts.first, ..._more];
    return [_query.queryWithoutMention.trim(), ..._more];
  }

  /// The people the matches have to include: those named in the words, and those kept from before. Words left alone
  /// keep the people the collection had.
  List<int> get _peopleNow {
    final c = _editing;
    if (c != null && !_wordsTouched) return [...c.personIds];
    return {..._keptIds, for (final p in _query.recognizedPeople) p.id}.toList();
  }

  String get _autoName {
    if (_photoUri != null) return 'Similar photos';
    final words = _query.text.trim().replaceAll('@', '');
    return words.isEmpty ? '' : words[0].toUpperCase() + words.substring(1);
  }

  void _changed() {
    if (!_nameTyped) _name.text = _autoName;
    _schedulePreview();
    setState(() {});
  }

  /// Starts the preview once typing pauses and not on every key. The last answer dims at once, so it is clear a new
  /// one is coming.
  void _schedulePreview() {
    if (_isPhotoEdit && _photoUri == null) return;
    _previewTimer?.cancel();
    final native = Get.find<LibraryController>();
    if (!_hasInput || native.totalEmbeddings == 0) {
      _previewToken++;
      setState(() {
        _preview = null;
        _previewing = false;
      });
      return;
    }
    setState(() => _previewing = true);
    _previewTimer = Timer(const Duration(milliseconds: 450), _runPreview);
  }

  Future<void> _runPreview() async {
    final token = ++_previewToken;
    final preview = await widget.controller.previewCollection(
      prompts: _promptsNow,
      seedUri: _photoUri,
      contentMode: _contentMode,
      personIds: _photoUri == null ? _peopleNow : const [],
      sensitivity: _editing?.sensitivity ?? SmartCollection.defaultSensitivity,
      shown: _shownMatches,
    );
    if (!mounted || token != _previewToken) return;
    setState(() {
      _preview = preview;
      _previewing = false;
    });
    for (final item in preview?.items ?? const <CollectionCover>[]) {
      if (_thumbs.containsKey(item.cacheKey)) continue;
      unawaited(_loadThumb(item));
    }
  }

  Future<void> _loadThumb(CollectionCover item) async {
    try {
      final bytes = await MediaService().loadThumbnail(
        uri: item.uri,
        isVideo: item.isVideo,
        timestampMs: item.timestampMs,
        size: 240,
      );
      if (mounted) setState(() => _thumbs[item.cacheKey] = bytes);
    } catch (_) {
      // The thumbnail is optional, so that square stays blank.
    }
  }

  void _commitMore() {
    final text = _moreField.text.trim();
    _moreField.clear();
    setState(() {
      _addingMore = false;
      if (text.isNotEmpty && !_more.contains(text) && _more.length < _maxMore) _more.add(text);
    });
    if (text.isNotEmpty) _schedulePreview();
  }

  Future<void> _pickPhoto() async {
    final uri = await SearchService().pickImageForSearching() as String?;
    if (uri == null || !mounted) return;
    setState(() {
      _photoUri = uri;
      _photoBytes = null;
    });
    _changed();
    try {
      final bytes = await MediaService().loadThumbnail(uri: uri, isVideo: false, size: 240);
      if (mounted && _photoUri == uri) setState(() => _photoBytes = bytes);
    } catch (_) {
      // The thumbnail is optional, and the photo is still what the collection looks like.
    }
  }

  void _clearPhoto() {
    setState(() {
      _photoUri = null;
      _photoBytes = null;
    });
    _changed();
  }

  /// Closes right away and does the work behind it. The tile of the collection appears on the Collections tab and
  /// plays its own "finding matches", so there is nothing to wait for here. A phrase still being typed is kept.
  void _save() {
    if (_addingMore) _commitMore();
    if (_isEdit) {
      _saveEdit();
      return;
    }
    final controller = widget.controller;
    final typed = _name.text.trim();
    final name = typed.isNotEmpty ? typed : _autoName;
    final contentMode = _contentMode;
    final photo = _photoUri;
    final query = _query.queryWithoutMention;
    final personIds = [for (final p in _query.recognizedPeople) p.id];
    final more = [..._more];
    Navigator.of(context).pop();
    if (photo != null) {
      unawaited(
        controller.createPhotoCollection(name: name, uri: photo, contentMode: contentMode).then((made) {
          if (made == null) {
            AppToast.show("That photo couldn't be read.");
          }
        }),
      );
    } else {
      unawaited(
        controller.createCollection(
          name: name,
          query: query,
          contentMode: contentMode,
          personIds: personIds,
          morePrompts: more,
        ),
      );
    }
  }

  /// Changes the collection in place and closes the sheet. A name alone is a rename: nothing is found again unless the
  /// words, the phrasings, the people or what is included changed. A photo collection can change its name, what it
  /// includes and the photo it looks like. A built-in whose words were left alone keeps its own phrasings, with any
  /// added here after them.
  void _saveEdit() {
    final c = _editing!;
    final controller = widget.controller;
    final typed = _name.text.trim();
    final SmartCollection updated;
    if (c.isPhotos) {
      final name = typed.isEmpty ? c.name : typed;
      final photo = _photoUri;
      final contentMode = _contentMode;
      Navigator.of(context).pop();
      if (photo == null) {
        unawaited(controller.updateCollection(c.copyWith(name: name, contentMode: contentMode)));
      } else {
        unawaited(
          controller.changePhoto(c, uri: photo, name: name, contentMode: contentMode).then((read) {
            if (!read) AppToast.show("That photo couldn't be read.");
          }),
        );
      }
      return;
    }
    final prompts = _promptsNow;
    if (prompts.first.isEmpty) prompts[0] = 'a photo';
    final keepsOwn = c.isBuiltIn && !_wordsTouched;
    updated = c.copyWith(
      name: typed.isNotEmpty ? typed : (_autoName.isNotEmpty ? _autoName : c.name),
      contentMode: _contentMode,
      personIds: _peopleNow,
      prompts: keepsOwn && _more.isEmpty ? null : prompts,
      explainQuery: keepsOwn ? c.explainQuery : null,
    );
    Navigator.of(context).pop();
    unawaited(controller.updateCollection(updated));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textTheme = Theme.of(context).textTheme;
    final showIdeas = !_hasInput && !_isEdit;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.base, AppSpacing.xl, AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Text(_isEdit ? 'Edit collection' : 'New collection', style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Fills itself as new photos are indexed.',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.ink80),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _Label('FIND'),
                  const SizedBox(height: AppSpacing.sm),
                  _photoMode ? _photoFind(textTheme) : _wordsFind(textTheme),
                  if (_hasWords && !_photoMode) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _morePhrasings(textTheme),
                  ],
                  if (showIdeas) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const _Label('TRY ONE'),
                    const SizedBox(height: AppSpacing.sm),
                    _ideaChips(),
                    const SizedBox(height: AppSpacing.lg),
                    _startFromPhoto(textTheme),
                  ],
                  if (_hasInput && (_preview != null || _previewing)) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _previewCard(textTheme),
                  ],
                  if (_hasInput) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const _Label('INCLUDE'),
                    const SizedBox(height: AppSpacing.sm),
                    _includeChoice(),
                    const SizedBox(height: AppSpacing.lg),
                    const _Label('NAME'),
                    const SizedBox(height: AppSpacing.sm),
                    _nameField(textTheme),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _saveButton(textTheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wordsFind(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.base, right: AppSpacing.xs),
      decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(
        children: [
          Expanded(
            child: MentionInputField(
              controller: _query,
              autofocus: !_isEdit,
              onChanged: _changed,
              style: textTheme.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'Describe what to find',
                hintStyle: TextStyle(color: AppColors.ink48),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
            ),
          ),
          if (_hasWords)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink80),
              onPressed: () {
                _query.clear();
                _more.clear();
                _changed();
              },
            ),
        ],
      ),
    );
  }

  Widget _photoFind(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox.square(
              dimension: 48,
              child: _photoBytes == null
                  ? const ColoredBox(color: AppColors.hairline)
                  : Image.memory(_photoBytes!, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text('Photos that look like this', style: textTheme.titleSmall)),
          if (_isPhotoEdit)
            IconButton(
              tooltip: 'Choose another photo',
              icon: const Icon(Icons.image_outlined, size: 20, color: AppColors.ink80),
              onPressed: _pickPhoto,
            )
          else
            IconButton(
              tooltip: 'Describe in words instead',
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink80),
              onPressed: _clearPhoto,
            ),
        ],
      ),
    );
  }

  Widget _morePhrasings(TextTheme textTheme) {
    final chipText = textTheme.labelMedium?.copyWith(color: AppColors.ink);
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Also describe it as', style: textTheme.bodySmall?.copyWith(color: AppColors.ink80)),
          for (final phrase in _more)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth),
              child: Container(
                height: 32,
                padding: const EdgeInsets.only(left: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.parchment,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(phrase, style: chipText, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(
                      tooltip: 'Remove $phrase',
                      visualDensity: VisualDensity.compact,
                      iconSize: 14,
                      icon: const Icon(Icons.close_rounded, color: AppColors.ink80),
                      onPressed: () {
                        setState(() => _more.remove(phrase));
                        _schedulePreview();
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (_addingMore)
            Container(
              width: 160,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.parchment,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: TextField(
                controller: _moreField,
                focusNode: _moreFocus,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _commitMore(),
                style: chipText,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  hintText: 'e.g. "coast"',
                  hintStyle: TextStyle(color: AppColors.ink48),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            )
          else if (_more.length < _maxMore)
            TextButton(
              onPressed: () => setState(() => _addingMore = true),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                textStyle: textTheme.labelMedium,
              ),
              child: const Text('+ Add'),
            ),
        ],
      ),
    );
  }

  Widget _ideaChips() {
    final faces = Get.isRegistered<FacesController>() ? Get.find<FacesController>() : null;
    final named = faces?.people.where((p) => p.name != null && p.name!.trim().isNotEmpty).toList() ?? const [];
    final ideas = [..._ideas, if (named.isNotEmpty) '${named.first.name!.trim()} at the beach'];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final idea in ideas)
          _Pill(
            label: idea,
            onTap: () {
              _query.text = idea;
              _query.selection = TextSelection.collapsed(offset: idea.length);
              _changed();
            },
          ),
      ],
    );
  }

  Widget _startFromPhoto(TextTheme textTheme) {
    return Material(
      color: AppColors.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _pickPhoto,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.parchment,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.image_outlined, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start from a photo', style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Find photos that look like one you pick',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.ink80),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.ink80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewCard(TextTheme textTheme) {
    final preview = _preview;
    final String headline;
    if (preview == null) {
      headline = 'Finding matches...';
    } else if (preview.count == 0) {
      headline = 'Nothing matches yet';
    } else {
      headline = _countLabel(preview.count, _contentMode);
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: _previewing && preview != null ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(headline, style: textTheme.titleSmall),
            if (preview != null && preview.count == 0) ...[
              const SizedBox(height: 2),
              Text(
                'New photos that match will be added as they are indexed.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.ink80),
              ),
            ],
            if (preview != null && preview.items.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (var i = 0; i < _shownMatches; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: i < preview.items.length ? _thumb(preview.items[i]) : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (preview != null && preview.people.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1, color: AppColors.hairline),
              const SizedBox(height: AppSpacing.md),
              _peopleLine(preview, textTheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumb(CollectionCover item) {
    final bytes = _thumbs[item.cacheKey];
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: bytes == null
          ? const ColoredBox(color: AppColors.hairline)
          : Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 240, gaplessPlayback: true),
    );
  }

  /// Who is in the matches: a few of their faces and their names. It only says who is there, and nothing in it can be
  /// tapped.
  Widget _peopleLine(CollectionPreview preview, TextTheme textTheme) {
    final faces = Get.find<FacesController>();
    final byId = {for (final p in faces.people) p.id: p};
    final people = [
      for (final entry in preview.people)
        if (byId[entry.personId] != null) byId[entry.personId]!,
    ];
    if (people.isEmpty) return const SizedBox.shrink();
    const size = 32.0, overlap = 8.0;
    final shown = people.take(4).toList();
    return Row(
      children: [
        SizedBox(
          width: size + (shown.length - 1) * (size - overlap) + 4,
          height: size + 4,
          child: Stack(
            children: [
              for (var i = shown.length - 1; i >= 0; i--)
                Positioned(
                  left: i * (size - overlap),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: AppColors.parchment, shape: BoxShape.circle),
                    child: FaceAvatar(faceId: shown[i].coverFaceId, size: size),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            peopleLine([for (final p in people) p.name]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: AppColors.ink80),
          ),
        ),
      ],
    );
  }

  /// Three even choices across the sheet. With large text they would break words in half, so they wrap as they are.
  Widget _includeChoice() {
    const choices = [('both', 'Both'), ('images', 'Images'), ('videos', 'Videos')];
    Widget pill(String value, String label) => _Pill(
      label: label,
      selected: _contentMode == value,
      onTap: () {
        if (_contentMode == value) return;
        setState(() => _contentMode = value);
        _schedulePreview();
      },
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [for (final (value, label) in choices) pill(value, label)],
      );
    }
    return Row(
      children: [
        for (final (value, label) in choices) ...[
          if (value != choices.first.$1) const SizedBox(width: AppSpacing.sm),
          Expanded(child: pill(value, label)),
        ],
      ],
    );
  }

  Widget _nameField(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: TextField(
        controller: _name,
        onChanged: (text) => setState(() => _nameTyped = text.trim().isNotEmpty),
        textCapitalization: TextCapitalization.sentences,
        style: textTheme.bodyMedium,
        decoration: const InputDecoration(
          hintText: 'Name',
          hintStyle: TextStyle(color: AppColors.ink48),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        ),
      ),
    );
  }

  Widget _saveButton(TextTheme textTheme) {
    final enabled = _hasInput;
    return Material(
      color: enabled ? AppColors.primary : AppColors.hairline,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: enabled ? _save : null,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(
            child: Text(
              _isEdit ? 'Save changes' : 'Save collection',
              style: textTheme.titleSmall?.copyWith(color: enabled ? AppColors.onPrimary : AppColors.ink48),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ideas offered before anything is typed. An idea for a named person is added when there is one.
const _ideas = ['Sunsets', 'Receipts', 'Food', 'Mountains', 'Handwritten notes'];

/// At most this many other ways of saying it.
const _maxMore = 3;

/// How many of the best matches the preview shows.
const _shownMatches = 5;

/// A small heading over a part of the sheet, like the one in the search filter sheet.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.ink80, letterSpacing: 0.5),
    );
  }
}

/// A round choice, the same as in the search filter sheet. It is filled when chosen.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.selected = false});

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
      color: selected ? AppColors.primary : AppColors.parchment,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm + 2),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.ink,
            ),
          ),
        ),
      ),
    ),
    );
  }
}
