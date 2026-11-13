import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/core/app_links.dart';
import 'package:lost_and_found/core/open_link.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/widgets/confirm_dialog.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/library/controllers/library_controller.dart';
import 'package:lost_and_found/features/library/models/indexed_folder_model.dart';
import 'package:lost_and_found/features/library/services/library_service.dart';
import 'package:lost_and_found/features/library/view/widgets/data_summary.dart';
import 'package:lost_and_found/features/library/view/widgets/how_it_works.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/features/people/models/face_scan.dart';
import 'package:lost_and_found/features/settings/view/developer_note/page_bar.dart';

/// What the app has made and kept on the phone, the way to clear it, and how the app works. The note above the scan opens
/// it.
class YourDataScreen extends StatefulWidget {
  const YourDataScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const YourDataScreen());

  @override
  State<YourDataScreen> createState() => _YourDataScreenState();
}

class _YourDataScreenState extends State<YourDataScreen> {
  /// The widest the content gets, so lines stay easy to read on a tablet or a phone turned sideways.
  static const _contentWidth = 640.0;

  /// How many photos and videos the gallery holds. Null until it has been read, and when it cannot be.
  ({int photos, int videos})? _onPhone;

  /// The most recently indexed photos and videos and the faces of the first people, as pictures for the tiles.
  List<Uint8List> _photoPictures = const [];
  List<Uint8List> _videoPictures = const [];
  List<Uint8List> _facePictures = const [];

  @override
  void initState() {
    super.initState();
    _readGallery();
    _readPictures();
  }

  /// How many pictures the tiles show, and how many are asked for. More are asked for than shown, as a photo that was
  /// deleted after it was indexed has no picture to read.
  static const _photoSlots = 8;
  static const _videoSlots = 6;

  Future<void> _readPictures() async {
    try {
      final samples = await LibraryService().getIndexedSamples(photos: _photoSlots * 2, videos: _videoSlots * 2);
      final media = MediaService();
      final photos = await _all([for (final uri in samples.photos) media.loadThumbnail(uri: uri, isVideo: false, size: 160)]);
      if (!mounted) return;
      setState(() => _photoPictures = photos.take(_photoSlots).toList());
      // One at a time: a video frame waits for the lock of a scan's video decoding and would hold up every shared thread.
      for (final v in samples.videos) {
        if (_videoPictures.length >= _videoSlots) break;
        final frame = await _all([media.loadThumbnail(uri: v.uri, isVideo: true, timestampMs: v.timestampMs, size: 160)]);
        if (!mounted) return;
        if (frame.isNotEmpty) setState(() => _videoPictures = [..._videoPictures, ...frame]);
      }
    } catch (_) {
      // The pictures are only for looks, so the tiles keep their empty slots when they cannot be read.
    }
  }

  /// The pictures that could be read, in the order asked for. One that could not be is left out.
  Future<List<Uint8List>> _all(List<Future<Uint8List?>> pictures) async {
    final read = await Future.wait([for (final picture in pictures) picture.then<Uint8List?>((b) => b).catchError((_) => null)]);
    return [for (final bytes in read) if (bytes != null) bytes];
  }

  /// The faces that were asked for, so a list of people that has not changed is not read again.
  List<int> _faceIds = const [];

  /// Reads the pictures of the first people's cover faces, when those faces are not the ones already read.
  void _followPeople(FacesController faces) {
    final ids = [for (final person in faces.people.take(3)) person.coverFaceId];
    if (listEquals(ids, _faceIds)) return;
    _faceIds = ids;
    scheduleMicrotask(() => _readFaces(faces, ids));
  }

  Future<void> _readFaces(FacesController faces, List<int> ids) async {
    final crops = await _all([
      for (final id in ids)
        if (faces.cachedCrop(id) != null)
          Future.value(faces.cachedCrop(id))
        else
          faces.crop(id).whenComplete(() => faces.releaseCrop(id)),
    ]);
    if (mounted && listEquals(ids, _faceIds)) setState(() => _facePictures = crops);
  }

  Future<void> _readGallery() async {
    try {
      final counts = await LibraryService().getPhoneMediaCounts();
      if (mounted) setState(() => _onPhone = counts);
    } catch (_) {
      // The gallery could not be counted, so the tiles only say how many are searchable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            const PageBar(title: 'Your data'),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => ListView(
                  padding: EdgeInsets.fromLTRB(
                    math.max(AppSpacing.xl, (box.maxWidth - _contentWidth) / 2),
                    AppSpacing.base,
                    math.max(AppSpacing.xl, (box.maxWidth - _contentWidth) / 2),
                    AppSpacing.xxl,
                  ),
                  children: [
                    const _StaysOnPhone(),
                    const SizedBox(height: AppSpacing.lg),
                    GetBuilder<LibraryController>(
                      builder: (library) =>
                          _withFaces((status) => _summary(library, status)),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const _SectionLabel('Clear data'),
                    GetBuilder<LibraryController>(
                      builder: (library) => _withFaces(
                        (status) =>
                            _ClearRows(library: library, status: status),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const _SectionLabel('How it works'),
                    const HowItWorks(),
                    const SizedBox(height: AppSpacing.xxl),
                    const _SourceCode(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _withFaces(Widget Function(FaceStatus status) build) {
    if (!Get.isRegistered<FacesController>()) return build(FaceStatus());
    return GetBuilder<FacesController>(
      builder: (faces) {
        _followPeople(faces);
        return build(faces.status);
      },
    );
  }

  Widget _summary(LibraryController library, FaceStatus status) {
    DataSummary summary(CollectionsController? collections) => DataSummary(
      photos: library.totalImages,
      videos: library.totalVideos,
      photosOnPhone: _onPhone?.photos,
      videosOnPhone: _onPhone?.videos,
      faces: status.faces,
      people: status.people,
      collections: collections == null
          ? 0
          : collections.visible
                .where((c) => collections.statsFor(c.id).count > 0)
                .length,
      lastScan: _lastScanTime(library.allIndexedFoldersList),
      failed: library.totalFailed,
      photoPictures: _photoPictures,
      videoPictures: _videoPictures,
      facePictures: _facePictures,
      collectionPictures: collections == null ? const [] : _coversOf(collections),
    );
    if (!Get.isRegistered<CollectionsController>()) return summary(null);
    return GetBuilder<CollectionsController>(builder: summary);
  }

  /// The covers of the first three collections worth showing that have one and whose picture has been read. As on the
  /// Collections tab, the everyday ones such as documents and screenshots are left out, and the collections come in the
  /// order of that tab, the person's own first and then the fullest.
  List<Uint8List> _coversOf(CollectionsController collections) {
    final covers = <Uint8List>[];
    for (final collection in collections.visible) {
      if (collection.isEveryday) continue;
      final bytes = collections.statsFor(collection.id).count > 0 ? collections.coverFor(collection.id) : null;
      if (bytes != null) covers.add(bytes);
      if (covers.length == 3) break;
    }
    return covers;
  }
}

DateTime? _lastScanTime(List<IndexedFolder> folders) {
  if (folders.isEmpty) return null;
  final latest = folders
      .map((f) => f.updatedAt)
      .reduce((a, b) => a > b ? a : b);
  if (latest <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(latest);
}

/// The promise at the top of the page: a lock, what it says in a few words, and one plain line under it.
class _StaysOnPhone extends StatelessWidget {
  const _StaysOnPhone();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stays on this phone',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Everything here is stored on this device. None of it is ever sent anywhere.',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.ink80,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.ink48,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// The two ways to clear what the app has made, the same as in Settings: the search data, and the face data.
class _ClearRows extends StatelessWidget {
  const _ClearRows({required this.library, required this.status});

  final LibraryController library;
  final FaceStatus status;

  @override
  Widget build(BuildContext context) {
    final hasSearchData =
        library.totalEmbeddings > 0 || library.allIndexedFoldersList.isNotEmpty;
    final hasFaceData =
        status.faces > 0 || status.people > 0 || status.processed > 0;
    final scanning = library.isScanning;
    final faces = Get.isRegistered<FacesController>()
        ? Get.find<FacesController>()
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ColoredBox(
        color: AppColors.parchment,
        child: Column(
          children: [
            _ClearRow(
              title: 'Clear search data',
              subtitle: scanning
                  ? 'Stop indexing first'
                  : hasSearchData
                  ? 'Forgets everything indexed for search'
                  : 'Nothing indexed yet',
              onTap: scanning || !hasSearchData
                  ? null
                  : () => showConfirmDialog(
                      context,
                      title: 'Clear search data?',
                      message:
                          'This removes everything the app indexed for search and forgets all indexed folders. You will need to scan again to search. The people already found are kept. "Clear face data" removes those.',
                      confirmLabel: 'Clear',
                      onConfirm: library.clearAllEmbeddings,
                    ),
            ),
            const Divider(height: 1, color: AppColors.hairline),
            _ClearRow(
              title: 'Clear face data',
              subtitle: scanning
                  ? 'Stop indexing first'
                  : hasFaceData
                  ? 'Forgets every group and name, then finds faces again'
                  : 'No face data yet',
              onTap: scanning || !hasFaceData || faces == null
                  ? null
                  : () => showConfirmDialog(
                      context,
                      title: 'Clear face data?',
                      message:
                          'All groups and the names you gave will be removed, and every indexed photo is searched for faces again.',
                      confirmLabel: 'Clear',
                      onConfirm: faces.rescanEverything,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearRow extends StatelessWidget {
  const _ClearRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title, subtitle;

  /// Null greys the row out: there is nothing for it to clear.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleSmall?.copyWith(color: AppColors.danger),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(color: AppColors.ink48),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The way to the project's source code on GitHub, for anyone who wants to see for themselves how the app works.
class _SourceCode extends StatelessWidget {
  const _SourceCode();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          'Want to see for yourself? The source code is on GitHub.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: AppColors.ink48, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => openLink(kRepoUrl),
          icon: const Icon(Icons.code_rounded, size: 20),
          label: const Text('View the source code'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.hairline),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}
