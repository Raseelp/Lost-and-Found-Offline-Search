import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/collections_controller.dart';
import 'package:lost_and_found/controllers/export_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/app_search_field.dart';
import 'package:lost_and_found/view/widget/confirm_dialog.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/nothing_indexed.dart';
import 'package:lost_and_found/view/widget/zip_art.dart';
import 'package:lost_and_found/view/widget/zip_progress.dart';

/// Opens the zip export with [select] (see [ExportController.collectionKey] and
/// [ExportController.personKey]) already ticked.
Future<void> openExportZip(
  BuildContext context, {
  Set<String> select = const {},
}) {
  if (!Get.isRegistered<ExportController>()) Get.put(ExportController());
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ExportZipScreen(select: select)));
}

/// Choose albums, see what the zip would be, choose how to split it, make it, watch it being
/// made, and send it on.
class ExportZipScreen extends StatefulWidget {
  const ExportZipScreen({super.key, this.select = const {}});

  final Set<String> select;

  @override
  State<ExportZipScreen> createState() => _ExportZipScreenState();
}

class _ExportZipScreenState extends State<ExportZipScreen> {
  late final ExportController _export = Get.find<ExportController>();

  @override
  void initState() {
    super.initState();
    // The albums are set up before the first frame, so it never shows the last visit's.
    _export.prepare(select: widget.select);
    WidgetsBinding.instance.addPostFrameCallback((_) => _export.open());
  }

  @override
  void dispose() {
    _export.closeScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: GetBuilder<ExportController>(
          builder: (c) {
            final phase = c.status.phase;
            final Widget body;
            if (phase == 'idle') {
              // Back from the settings goes back to the albums, not out of the screen.
              body = PopScope(
                key: ValueKey('builder-${c.step}'),
                canPop: c.step == 0,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) c.setStep(0);
                },
                child: c.step == 0 ? _BuilderView(c: c) : _SettingsView(c: c),
              );
            } else if (phase != 'failed' &&
                phase != 'cancelled' &&
                (c.status.running || c.playing)) {
              // Also once the zip is made, until the show of it has played out.
              body = _ProgressView(key: const ValueKey('progress'), c: c);
            } else if (phase == 'done') {
              body = _DoneView(key: const ValueKey('done'), c: c);
            } else if (phase == 'cancelled') {
              body = _MessageView(
                key: const ValueKey('cancelled'),
                c: c,
                icon: Icons.block_rounded,
                title: 'Cancelled',
                message:
                    'Nothing was kept. Your photos and videos are untouched.',
              );
            } else {
              body = _MessageView(
                key: const ValueKey('failed'),
                c: c,
                icon: Icons.error_outline_rounded,
                title: 'The zip could not be made',
                message: c.status.error.isEmpty
                    ? 'Something went wrong.'
                    : c.status.error,
              );
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(.05, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: body,
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------ choosing

// Whether nothing has been indexed (so there is nothing to export for that reason).
bool _nothingIndexed() =>
    !Get.isRegistered<NativeController>() ||
    Get.find<NativeController>().totalEmbeddings == 0;

class _BuilderView extends StatelessWidget {
  const _BuilderView({required this.c});

  final ExportController c;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final collections = c.shownCollections, people = c.shownPeople;
    final rows = <Object>[
      if (collections.isNotEmpty) 'Collections',
      ...collections,
      if (people.isNotEmpty) 'People',
      ...people,
    ];
    final nothingAtAll = c.collections.isEmpty && c.people.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.xl,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.ink,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text('Export as zip', style: textTheme.titleLarge),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xs,
                  AppSpacing.xl,
                  AppSpacing.base,
                ),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Put albums in a zip to keep, send, or move to another device. Your photos and videos stay where they are: the zip is a copy.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              if (!nothingAtAll)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SearchHeader(
                    query: c.query,
                    chosen: c.selected.length,
                    onChanged: c.setQuery,
                  ),
                ),
              if (rows.isEmpty && nothingAtAll && _nothingIndexed())
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xxl,
                    AppSpacing.xxxl,
                    AppSpacing.xxl,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: NothingIndexed(icon: Icons.folder_zip_outlined),
                  ),
                )
              else if (rows.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      nothingAtAll
                          ? 'There is nothing to export yet. Collections and people appear once something is indexed.'
                          : 'No collection or person is called "${c.query.trim()}".',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.ink48,
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String) {
                      final heading = Text(
                        row.toUpperCase(),
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.ink48,
                          letterSpacing: .5,
                        ),
                      );
                      // Each heading carries the button that ticks everything under it.
                      final group = row == 'Collections' ? collections : people;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.xs,
                          AppSpacing.md,
                          0,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: heading),
                            TextButton(
                              onPressed: () => c.toggleAll(group),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 36),
                              ),
                              child: Text(
                                c.allChosen(group) ? 'Clear all' : 'Select all',
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final album = row as ExportAlbum;
                    return _AlbumRow(
                      album: album,
                      selected: c.selected.contains(album.key),
                      onTap: () => c.toggle(album),
                    );
                  },
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.base),
              ),
            ],
          ),
        ),
        _SummaryBar(c: c, settings: false),
      ],
    );
  }
}

// ---------------------------------------------------------------- the zip's settings (step 2)

// Name, where it goes, how it is split and what is inside: a page of its own, after the albums
// are chosen, so none of it can be missed before the zip is made.
class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.c});

  final ExportController c;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final names = c.selectedAlbums.map((a) => a.name).toList();
    final shown = names.length <= 3
        ? names.join(', ')
        : '${names.take(3).join(', ')} and ${names.length - 3} more';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.xl,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.ink,
                ),
                onPressed: () => c.setStep(0),
              ),
              Expanded(
                child: Text('Zip settings', style: textTheme.titleLarge),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs,
              AppSpacing.xl,
              AppSpacing.base,
            ),
            children: [
              Text(
                'Making a zip of $shown.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.ink80,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              _ZipFileCard(c: c),
              const SizedBox(height: AppSpacing.md),
              // Only a zip big enough to be split gets the splitting controls.
              if (c.canSplit) ...[
                _SplitCard(c: c),
                const SizedBox(height: AppSpacing.md),
              ] else if (c.selected.isNotEmpty && !c.loadingAny) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    'It is small (about ${zipBytes(c.totalBytes)}), so it will be one zip file.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _InsideCard(c: c),
            ],
          ),
        ),
        _SummaryBar(c: c, settings: true),
      ],
    );
  }
}

// The search box, pinned above the list so it stays in reach while scrolling.
class _SearchHeader extends SliverPersistentHeaderDelegate {
  _SearchHeader({
    required this.query,
    required this.chosen,
    required this.onChanged,
  });

  final String query;
  final int chosen;
  final ValueChanged<String> onChanged;

  static const double _height = 72;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.canvas,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: _SearchField(initial: query, chosen: chosen, onChanged: onChanged),
    );
  }

  @override
  bool shouldRebuild(_SearchHeader old) =>
      old.query != query || old.chosen != chosen;
}

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

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.selected,
    required this.onTap,
  });

  final ExportAlbum album;
  final bool selected;
  final VoidCallback onTap;

  String get _subtitle {
    if (album.loaded) {
      final parts = <String>[
        if (album.images > 0)
          '${album.images} ${album.images == 1 ? 'photo' : 'photos'}',
        if (album.videos > 0)
          '${album.videos} ${album.videos == 1 ? 'video' : 'videos'}',
      ];
      if (parts.isEmpty) return 'Nothing readable';
      return '${parts.join(' · ')} · ${zipBytes(album.bytes)}';
    }
    if (album.loading) return 'Counting…';
    return '${album.approxCount} ${album.approxCount == 1 ? 'item' : 'items'}';
  }

  Widget _avatar() {
    if (album.person != null) {
      return FaceAvatar(faceId: album.person!.coverFaceId, size: 46);
    }
    if (album.memory != null) {
      return SizedBox(
        width: 46,
        height: 46,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
      );
    }
    final Uint8List? cover = Get.isRegistered<CollectionsController>()
        ? Get.find<CollectionsController>().coverFor(album.collection!.id)
        : null;
    return SizedBox(
      width: 46,
      height: 46,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: cover != null
            ? Image.memory(cover, fit: BoxFit.cover, cacheWidth: 140)
            : ColoredBox(
                color: AppColors.parchment,
                child: Icon(
                  album.collection!.icon,
                  color: AppColors.ink48,
                  size: 22,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              _avatar(),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _subtitle,
                        key: ValueKey(_subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink48,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : AppColors.canvas,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.hairline,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: AppColors.onPrimary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// A titled box on the parchment colour.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- the zip file: name etc.

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
    // The suggested name follows the albums ticked until the user types one.
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

// ------------------------------------------------------------------------------ splitting

class _SplitCard extends StatefulWidget {
  const _SplitCard({required this.c});

  final ExportController c;

  @override
  State<_SplitCard> createState() => _SplitCardState();
}

class _SplitCardState extends State<_SplitCard> {
  // Bigger zips choose from a few sizes (and "Custom" for the slider); smaller ones have only the
  // slider.
  bool _custom = false;

  // Where the slider is, as a step from its left end; null until touched (then it follows the
  // limit in force, which starts as no split: the right end).
  double? _step;

  String _label(int bytes) => bytes >= ExportController.gb
      ? '${bytes ~/ ExportController.gb} GB'
      : '${bytes ~/ ExportController.mb} MB';

  // The slider goes from the smallest part worth making to the whole zip (at which it is not
  // split). Its steps are round sizes.
  ({int min, int max, int unit, int steps}) _range(int total, bool onlySlider) {
    const mb = ExportController.mb;
    final min = onlySlider ? (total >= 200 * mb ? 50 * mb : 25 * mb) : 100 * mb;
    final max = onlySlider
        ? total
        : (total < 8 * ExportController.gb ? total : 8 * ExportController.gb);
    var unit = 5 * mb;
    for (final candidate in const [5, 10, 25, 50, 100, 250, 500]) {
      unit = candidate * mb;
      if ((max - min) / unit <= 24) break;
    }
    return (
      min: min,
      max: max,
      unit: unit,
      steps: ((max - min) / unit).ceil().clamp(1, 1000),
    );
  }

  int _bytesAt(({int min, int max, int unit, int steps}) r, double step) =>
      step.round() >= r.steps ? r.max : r.min + step.round() * r.unit;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final textTheme = Theme.of(context).textTheme;
    final total = c.totalBytes;
    final presets = c.applicablePresets;
    final onlySlider = presets.isEmpty;
    final showSlider = onlySlider || _custom;
    final range = _range(total, onlySlider);
    final sizes = c.partSizes;
    final overFat = c.activeLimit == 0 && total > 4 * ExportController.gb;
    final noSplitAtEnd = range.max >= total;

    // Where the slider sits: where it was put, else where the limit in force is.
    final step =
        (_step ??
                (c.activeLimit == 0
                    ? range.steps.toDouble()
                    : ((c.activeLimit - range.min) / range.unit)
                          .clamp(0, range.steps)
                          .toDouble()))
            .clamp(0.0, range.steps.toDouble());
    final atEnd = step.round() >= range.steps;
    final sliderBytes = _bytesAt(range, step);

    return _Card(
      title: 'Split into parts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            onlySlider
                ? 'Your zip would be about ${zipBytes(total)}. Drag the slider to cut it into smaller zip files, or leave it at the right to keep one.'
                : 'Your zip would be about ${zipBytes(total)}. Choose how big each part may be, or keep one file.',
            style: textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Each part is a complete zip you can open on its own.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink48,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!onlySlider)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Chip(
                  label: 'One file',
                  selected: !_custom && c.activeLimit == 0,
                  onTap: () {
                    setState(() {
                      _custom = false;
                      _step = null;
                    });
                    c.setPartLimit(0);
                  },
                ),
                for (final p in presets)
                  _Chip(
                    label: 'Parts of ${_label(p)}',
                    selected: !_custom && c.activeLimit == p,
                    onTap: () {
                      setState(() {
                        _custom = false;
                        _step = null;
                      });
                      c.setPartLimit(p);
                    },
                  ),
                _Chip(
                  label: 'Custom',
                  selected: _custom,
                  onTap: () {
                    setState(() => _custom = true);
                    c.setPartLimit(atEnd && noSplitAtEnd ? 0 : sliderBytes);
                  },
                ),
              ],
            ),
          if (showSlider) ...[
            SizedBox(height: onlySlider ? 0 : AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    atEnd && noSplitAtEnd
                        ? 'One zip, not split'
                        : 'Parts of up to ${zipBytes(sliderBytes)}',
                    style: textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: step,
              min: 0,
              max: range.steps.toDouble(),
              divisions: range.steps,
              label: atEnd && noSplitAtEnd ? 'One zip' : zipBytes(sliderBytes),
              onChanged: (v) {
                setState(() => _step = v);
                final bytes = _bytesAt(range, v);
                c.setPartLimit(
                  v.round() >= range.steps && noSplitAtEnd ? 0 : bytes,
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Smaller parts',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                ),
                if (noSplitAtEnd)
                  Text(
                    'One zip',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.base),
          if (sizes.isEmpty)
            Text(
              'Nothing to put in a zip yet.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
            )
          else
            _FilesPreview(c: c, sizes: sizes),
          if (overFat) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'This is over 4 GB. Some SD cards and USB sticks cannot hold one file that big: splitting makes parts that fit.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.ink80,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// The zip files that will be made, as a plain list: their names and sizes, each with a bar of how
// full it is.
class _FilesPreview extends StatelessWidget {
  const _FilesPreview({required this.c, required this.sizes});

  final ExportController c;
  final List<int> sizes;

  static const int _shown = 5;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final names = c.zipFileNames(sizes.length);
    final shown = sizes.length <= _shown ? sizes.length : _shown;
    final rest = sizes.length - shown;
    final restBytes = sizes.skip(shown).fold<int>(0, (a, b) => a + b);
    final sentence = sizes.length == 1
        ? 'You will get one zip file, about ${zipBytes(sizes.first)}.'
        : 'You will get ${sizes.length} zip files. Each one is a complete zip you can open on its own.';
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sentence, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < shown; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.folder_zip_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          names[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        zipBytes(sizes[i]),
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink80,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (sizes.length > 1 && c.activeLimit > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 28),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            end: (sizes[i] / c.activeLimit).clamp(0.02, 1.0),
                          ),
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) =>
                              LinearProgressIndicator(
                                value: value,
                                minHeight: 4,
                                backgroundColor: AppColors.hairline,
                                color: AppColors.primary.withValues(alpha: .65),
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (rest > 0)
            Text(
              'and $rest more ${rest == 1 ? 'file' : 'files'} (${zipBytes(restBytes)})',
              style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? AppColors.onPrimary : AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- what is inside the zip

class _InsideCard extends StatelessWidget {
  const _InsideCard({required this.c});

  final ExportController c;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final albums = c.selectedAlbums;
    const shown = 4;
    Widget row(
      IconData icon,
      String text, {
      double indent = 0,
      Color? color,
      String? trailing,
    }) {
      return Padding(
        padding: EdgeInsets.only(left: indent, top: 3, bottom: 3),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? AppColors.ink48),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
              ),
          ],
        ),
      );
    }

    return _Card(
      title: 'Inside the zip',
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final album in albums.take(shown)) ...[
              row(Icons.folder_rounded, album.name, color: AppColors.primary),
              if (!album.loaded || album.images > 0)
                row(
                  Icons.image_outlined,
                  'Images',
                  indent: 26,
                  trailing: album.loaded ? '${album.images}' : '…',
                ),
              if (!album.loaded || album.videos > 0)
                row(
                  Icons.videocam_outlined,
                  'Videos',
                  indent: 26,
                  trailing: album.loaded ? '${album.videos}' : '…',
                ),
            ],
            if (albums.length > shown)
              row(
                Icons.more_horiz_rounded,
                '${albums.length - shown} more ${albums.length - shown == 1 ? 'album' : 'albums'}',
              ),
            if (c.includeList) row(Icons.description_outlined, 'list.json'),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------ the bar under it all

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.c, required this.settings});

  final ExportController c;

  /// On the settings step the button makes the zip (and the notes about it show); on the first
  /// it goes on to the settings.
  final bool settings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final chosen = c.selected.isNotEmpty;
    final loading = chosen && c.loadingAny;
    final parts = settings ? c.partSizes.length : 0;
    final notes = <(String, bool)>[
      if (settings && chosen && !loading && c.repeatedFiles > 0)
        (
          '${c.repeatedFiles} ${c.repeatedFiles == 1 ? 'file is' : 'files are'} in more than one chosen album, so ${c.repeatedFiles == 1 ? 'it is' : 'they are'} in the zip more than once (${zipBytes(c.repeatedBytes)} extra).',
          false,
        ),
      if (settings && chosen && !loading && c.unreadable > 0)
        (
          '${c.unreadable} ${c.unreadable == 1 ? 'file cannot' : 'files cannot'} be read and will be left out.',
          false,
        ),
      if (settings && chosen && !loading && c.tooBigForDownloads)
        (
          'This is more than the free space on your phone (${zipBytes(c.freeBytes)}). Choose a folder on another drive, or fewer albums.',
          true,
        ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                note.$1,
                style: textTheme.bodySmall?.copyWith(
                  color: note.$2 ? AppColors.danger : AppColors.ink80,
                  height: 1.35,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: !chosen
                    ? Text(
                        'Choose one or more albums',
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink48,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TweenAnimationBuilder<int>(
                            tween: IntTween(end: c.totalFiles),
                            duration: const Duration(milliseconds: 400),
                            builder: (context, files, _) => Text(
                              loading
                                  ? 'Counting… $files files'
                                  : '${c.totalImages} ${c.totalImages == 1 ? 'photo' : 'photos'}'
                                        '${c.totalVideos > 0 ? ' · ${c.totalVideos} ${c.totalVideos == 1 ? 'video' : 'videos'}' : ''}',
                              style: textTheme.titleSmall?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            'about ${zipBytes(c.totalBytes)} · not compressed',
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.ink48,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (settings)
                _PrimaryButton(
                  label: parts > 1 ? 'Make $parts zips' : 'Make zip',
                  enabled: c.canStart && !c.tooBigForDownloads,
                  busy: c.starting,
                  onTap: c.start,
                )
              else
                _PrimaryButton(
                  label: 'Next',
                  enabled: chosen,
                  onTap: () => c.setStep(1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final bool enabled, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : .45,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 120),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------- being made

class _ProgressView extends StatefulWidget {
  const _ProgressView({super.key, required this.c});

  final ExportController c;

  @override
  State<_ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<_ProgressView>
    with SingleTickerProviderStateMixin {
  // The least time the whole show takes, from empty to full: a zip made almost at once still
  // plays the folders filling, rather than flashing past.
  static const double _minSeconds = 4.2;

  // How far the show has got, 0..1. It follows the real progress but never faster than the
  // pace above; when the real thing is slower, it keeps up with it.
  final ValueNotifier<double> _shown = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration? _last;
  double _elapsed = 0;
  double _holdFor = 0;
  bool _handedOver = false;

  // Where each zip ends on the 0..1 line, to tell which zip it is on.
  late final List<double> _partEnds = () {
    final sizes = widget.c.partSizes;
    final total = sizes.fold<int>(0, (a, b) => a + b);
    var sum = 0;
    return [for (final s in sizes) total == 0 ? 1.0 : (sum += s) / total];
  }();

  // Recent (time, bytes done) readings, for how fast the real thing is going.
  final List<(DateTime, int)> _readings = [];

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shown.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == null
        ? 0.0
        : ((now - _last!).inMicroseconds / 1e6).clamp(0.0, .1);
    _last = now;
    _elapsed += dt;
    final status = widget.c.status;
    final finished = !status.running;
    final real = status.phase == 'preparing'
        ? 0.0
        : (finished ? 1.0 : status.fraction);

    var v = _shown.value;
    if (real > v) {
      // The fastest the show may go (eased in over the first half second), and how fast it
      // follows the real progress when that is slower.
      final cap = dt / _minSeconds * (_elapsed / .5).clamp(0.0, 1.0);
      final chase = (real - v) * (1 - math.exp(-dt * 6));
      var step = math.min(cap, chase);
      // The last of a finished one goes at the same pace, not slowed to a crawl.
      if (finished && real - v < .02) step = math.min(real - v, cap);
      v += step;
    }
    if (v != _shown.value) _shown.value = v;

    // All of it shown, and the zip is made: a moment with everything shut, then the result.
    if (finished && v >= 1 && !_handedOver) {
      _holdFor += dt;
      if (_holdFor > .8) {
        _handedOver = true;
        widget.c.finishPlayback();
      }
    }
  }

  String? _timeLeft(ZipExportStatus s) {
    final now = DateTime.now();
    if (_readings.isEmpty || _readings.last.$2 != s.bytesDone) {
      _readings.add((now, s.bytesDone));
    }
    _readings.removeWhere((r) => now.difference(r.$1).inSeconds > 12);
    if (_readings.length < 3 || s.bytesTotal <= 0) return null;
    final seconds = now.difference(_readings.first.$1).inMilliseconds / 1000;
    final bytes = s.bytesDone - _readings.first.$2;
    if (seconds < 2 || bytes <= 0) return null;
    final left = (s.bytesTotal - s.bytesDone) / (bytes / seconds);
    if (left < 8) return 'a few seconds left';
    if (left < 90) return 'about ${left.round()} seconds left';
    final minutes = (left / 60).round();
    if (minutes < 90) {
      return 'about $minutes ${minutes == 1 ? 'minute' : 'minutes'} left';
    }
    return 'about ${(minutes / 60).toStringAsFixed(1)} hours left';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final s = c.status;
    final textTheme = Theme.of(context).textTheme;
    final preparing = s.phase == 'preparing';
    final folders = c.folders;
    final files = folders.isEmpty
        ? s.filesTotal
        : folders.fold<int>(0, (sum, f) => sum + f.count);
    final bytes = folders.isEmpty
        ? s.bytesTotal
        : folders.fold<int>(0, (sum, f) => sum + f.bytes);
    final parts = _partEnds.length > 1 ? _partEnds.length : s.partsTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.base,
      ),
      child: Column(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _shown,
            builder: (context, v, _) {
              final done = v >= 1 && !s.running;
              final left = !preparing && s.running && v >= s.fraction - .02
                  ? _timeLeft(s)
                  : null;
              return Column(
                children: [
                  Text(
                    preparing
                        ? 'Checking your files'
                        : (done ? 'All zipped up' : 'Making your zip'),
                    style: textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    preparing
                        ? '${s.filesDone} of ${s.filesTotal}'
                        : '${(v * files).round()} of $files files · ${zipBytes(v * bytes)} of ${zipBytes(bytes)}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink80,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    [
                      if (left != null) left,
                      if (!preparing) '${(v * 100).floor()}%',
                    ].join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.ink48,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.base),
          ZipperBar(progress: _shown),
          if (parts > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            ValueListenableBuilder<double>(
              valueListenable: _shown,
              builder: (context, v, _) {
                var part = 1;
                if (_partEnds.length > 1) {
                  while (part < _partEnds.length &&
                      v > _partEnds[part - 1] + 1e-6) {
                    part++;
                  }
                } else {
                  part = s.part.clamp(1, parts);
                }
                return Column(
                  children: [
                    _PartDots(total: parts, current: part),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Zip $part of $parts',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink48,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: folders.isEmpty
                ? Center(
                    child: Text(
                      s.currentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink48,
                      ),
                    ),
                  )
                : ZipFolderTree(
                    folders: folders,
                    progress: _shown,
                    thumbs: c.thumbs,
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'It carries on if you leave the app. Your photos and videos are only read, never changed.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.ink48,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: 'Continue in background',
              enabled: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          if (s.running)
            TextButton(
              onPressed: () => showConfirmDialog(
                context,
                title: 'Cancel the zip?',
                message:
                    'What has been made so far is deleted. Your photos and videos are untouched.',
                confirmLabel: 'Cancel zip',
                onConfirm: c.cancel,
              ),
              child: const Text('Cancel zip'),
            )
          else
            const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// One dot per zip: the ones done are filled, the one being made pulses a little.
class _PartDots extends StatelessWidget {
  const _PartDots({required this.total, required this.current});

  final int total, current;

  @override
  Widget build(BuildContext context) {
    final shown = total > 12 ? 12 : total;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= shown; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 22 : 10,
            height: 10,
            decoration: BoxDecoration(
              color: i < current
                  ? AppColors.primary
                  : (i == current
                        ? AppColors.primaryFocus
                        : AppColors.hairline),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        if (total > shown)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('+${total - shown}'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------- finished

class _DoneView extends StatelessWidget {
  const _DoneView({super.key, required this.c});

  final ExportController c;

  @override
  Widget build(BuildContext context) {
    final s = c.status;
    final textTheme = Theme.of(context).textTheme;
    // Downloads files have a media address; anything else went to a folder the user chose.
    final inDownloads =
        s.results.isEmpty || s.results.first.uri.startsWith('content://media/');
    final saved = inDownloads
        ? 'Downloads › Lost & Found'
        : (c.savedLabel ?? 'the folder you chose');
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const Spacer(),
          const ZipDoneMark(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            s.results.length > 1
                ? 'Your ${s.results.length} zips are ready'
                : 'Your zip is ready',
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Saved in $saved',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.ink80),
          ),
          const SizedBox(height: AppSpacing.lg),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in s.results)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_zip_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          zipBytes(r.bytes),
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.ink48,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (s.skipped > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${s.skipped} ${s.skipped == 1 ? 'file' : 'files'} could not be read completely and ${s.skipped == 1 ? 'is' : 'are'} marked in the list.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: s.results.length > 1 ? 'Share the zips' : 'Share',
              enabled: true,
              onTap: () => NativeServices().shareZips([
                for (final r in s.results) r.uri,
              ]),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (inDownloads)
                TextButton(
                  onPressed: NativeServices().openDownloads,
                  child: const Text('Show in Downloads'),
                ),
              TextButton(
                onPressed: c.another,
                child: const Text('Make another'),
              ),
              TextButton(
                onPressed: () {
                  c.another();
                  Navigator.of(context).pop();
                },
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Cancelled or failed.
class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.c,
    required this.icon,
    required this.title,
    required this.message,
  });

  final ExportController c;
  final IconData icon;
  final String title, message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const Spacer(),
          Icon(icon, size: 56, color: AppColors.ink48),
          const SizedBox(height: AppSpacing.lg),
          Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.ink80,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Back to albums',
            enabled: true,
            onTap: c.another,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () {
              c.another();
              Navigator.of(context).pop();
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
