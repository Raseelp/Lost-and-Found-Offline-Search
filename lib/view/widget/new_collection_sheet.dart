import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/models/collection_model.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/mention_input_field.dart';
import 'package:lost_and_found/view/widget/mention_text_controller.dart';

/// The sheet that makes a new collection (from the action button, see ActionFab): what to find, in words (with
/// other ways of saying it) or by a photo to look like, a preview of what that finds and who is in it, photos,
/// videos or both, and a name taken from the words. Before anything is typed it offers a few ideas to start from.
Future<void> showNewCollectionSheet(BuildContext context, CollectionsController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (_) => _NewCollectionSheet(controller: controller),
  );
}

// Ideas offered before anything is typed (a named person's one is added when there is one).
const _ideas = ['Sunsets', 'Receipts', 'Food', 'Mountains', 'Handwritten notes'];

// At most this many other ways of saying it.
const _maxMore = 3;

// How many of the best matches the preview shows.
const _shownMatches = 5;

class _NewCollectionSheet extends StatefulWidget {
  const _NewCollectionSheet({required this.controller});

  final CollectionsController controller;

  @override
  State<_NewCollectionSheet> createState() => _NewCollectionSheetState();
}

class _NewCollectionSheetState extends State<_NewCollectionSheet> {
  // Names typed in the words are recognised as people, the same way the search box does it.
  late final MentionTextEditingController _query = MentionTextEditingController(
    peopleProvider: () => Get.isRegistered<FacesController>() ? Get.find<FacesController>().people : const [],
  );
  final TextEditingController _name = TextEditingController();
  // The name follows the words until it is typed over.
  bool _nameTyped = false;

  final List<String> _more = [];
  final TextEditingController _moreField = TextEditingController();
  final FocusNode _moreFocus = FocusNode();
  bool _addingMore = false;

  // Made from a photo instead of words.
  String? _photoUri;
  Uint8List? _photoBytes;

  String _contentMode = 'both';

  CollectionPreview? _preview;
  bool _previewing = false;
  int _previewToken = 0;
  Timer? _previewTimer;
  final Map<String, Uint8List> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _moreFocus.addListener(() {
      // Leaving the field keeps what was typed in it (not when the sheet itself is going away).
      if (mounted && !_moreFocus.hasFocus && _addingMore) _commitMore();
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
  bool get _hasInput => _photoUri != null || _hasWords;

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

  // ---- preview ----

  void _schedulePreview() {
    _previewTimer?.cancel();
    final native = Get.find<NativeController>();
    if (!_hasInput || native.totalEmbeddings == 0) {
      _previewToken++;
      setState(() {
        _preview = null;
        _previewing = false;
      });
      return;
    }
    // The last answer dims at once, so it is clear a new one is coming.
    setState(() => _previewing = true);
    // Not on every key: once typing pauses.
    _previewTimer = Timer(const Duration(milliseconds: 450), _runPreview);
  }

  Future<void> _runPreview() async {
    final token = ++_previewToken;
    final preview = await widget.controller.previewCollection(
      prompts: [_query.queryWithoutMention, ..._more],
      seedUri: _photoUri,
      contentMode: _contentMode,
      personIds: _photoUri == null ? [for (final p in _query.recognizedPeople) p.id] : const [],
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
      final bytes = await NativeServices().loadThumbnail(
        uri: item.uri,
        isVideo: item.isVideo,
        timestampMs: item.timestampMs,
        size: 240,
      );
      if (mounted) setState(() => _thumbs[item.cacheKey] = bytes);
    } catch (_) {
      // That square stays blank.
    }
  }

  // ---- other ways of saying it ----

  void _commitMore() {
    final text = _moreField.text.trim();
    _moreField.clear();
    setState(() {
      _addingMore = false;
      if (text.isNotEmpty && !_more.contains(text) && _more.length < _maxMore) _more.add(text);
    });
    if (text.isNotEmpty) _schedulePreview();
  }

  // ---- from a photo ----

  Future<void> _pickPhoto() async {
    final uri = await NativeServices().pickImageForSearching() as String?;
    if (uri == null || !mounted) return;
    setState(() {
      _photoUri = uri;
      _photoBytes = null;
    });
    _changed();
    try {
      final bytes = await NativeServices().loadThumbnail(uri: uri, isVideo: false, size: 240);
      if (mounted && _photoUri == uri) setState(() => _photoBytes = bytes);
    } catch (_) {
      // The square stays blank; the photo is still what the collection looks like.
    }
  }

  void _clearPhoto() {
    setState(() {
      _photoUri = null;
      _photoBytes = null;
    });
    _changed();
  }

  // ---- saving ----

  // Closes right away and does the work behind it: the new tile appears on the Collections tab and plays its own
  // "finding matches", so there is nothing to wait for here.
  void _save() {
    // A phrase still being typed is kept.
    if (_addingMore) _commitMore();
    final controller = widget.controller;
    final typed = _name.text.trim();
    final name = typed.isNotEmpty ? typed : _autoName;
    final contentMode = _contentMode;
    final messenger = ScaffoldMessenger.of(context);
    final photo = _photoUri;
    final query = _query.queryWithoutMention;
    final personIds = [for (final p in _query.recognizedPeople) p.id];
    final more = [..._more];
    Navigator.of(context).pop();
    if (photo != null) {
      unawaited(
        controller.createPhotoCollection(name: name, uri: photo, contentMode: contentMode).then((made) {
          if (made == null) {
            messenger.showSnackBar(const SnackBar(content: Text('That photo could not be read')));
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

  // ---- building ----

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textTheme = Theme.of(context).textTheme;
    final showIdeas = !_hasInput;

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
                  Text('New collection', style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Fills itself as new photos are indexed.',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.ink80),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _Label('FIND'),
                  const SizedBox(height: AppSpacing.sm),
                  _photoUri != null ? _photoFind(textTheme) : _wordsFind(textTheme),
                  if (_hasWords && _photoUri == null) ...[
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
              autofocus: true,
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
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Also describe it as', style: textTheme.bodySmall?.copyWith(color: AppColors.ink80)),
        for (final phrase in _more)
          Container(
            height: 32,
            padding: const EdgeInsets.only(left: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.parchment,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(phrase, style: chipText),
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
      // Still showing the last answer while the new one is worked out.
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

  // Who is in the matches: a few of their faces and their names. Only to say who is there; nothing to tap.
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

  Widget _includeChoice() {
    const choices = [('both', 'Both'), ('images', 'Images'), ('videos', 'Videos')];
    return Row(
      children: [
        for (final (value, label) in choices) ...[
          if (value != choices.first.$1) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _Pill(
              label: label,
              selected: _contentMode == value,
              onTap: () {
                if (_contentMode == value) return;
                setState(() => _contentMode = value);
                _schedulePreview();
              },
            ),
          ),
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
              'Save collection',
              style: textTheme.titleSmall?.copyWith(color: enabled ? AppColors.onPrimary : AppColors.ink48),
            ),
          ),
        ),
      ),
    );
  }
}

/// "142 photos and videos", "1 photo", "9 videos": how many items, by what the collection includes.
@visibleForTesting
String countLabel(int count, String contentMode) => _countLabel(count, contentMode);

String _countLabel(int count, String contentMode) {
  final one = count == 1;
  final what = switch (contentMode) {
    'images' => one ? 'photo' : 'photos',
    'videos' => one ? 'video' : 'videos',
    _ => one ? 'photo or video' : 'photos and videos',
  };
  return '$count $what';
}

/// The line under the preview's faces: "With Maya, Anna, Rose and 4 others" (people without a name are among
/// the others), "With 3 people" when none has a name. [names] is everyone in the matches, most seen first.
@visibleForTesting
String peopleLine(List<String?> names) {
  final named = [
    for (final n in names)
      if (n != null && n.trim().isNotEmpty) n.trim(),
  ];
  if (named.isEmpty) return names.length == 1 ? 'With 1 person' : 'With ${names.length} people';
  final shown = named.take(3).toList();
  final others = names.length - shown.length;
  if (others == 0) {
    return shown.length == 1 ? 'With ${shown.first}' : 'With ${shown.sublist(0, shown.length - 1).join(', ')} and ${shown.last}';
  }
  return 'With ${shown.join(', ')} and $others ${others == 1 ? 'other' : 'others'}';
}

// A small heading over a part of the sheet, like the search filter sheet's.
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

// A round choice, the same as the search filter sheet's: filled when chosen.
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
