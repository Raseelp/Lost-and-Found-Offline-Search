import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/faces_controller.dart';
import 'package:lost_and_found/controllers/native_controller.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/then_now_card.dart';
import 'package:lost_and_found/view/widget/face_widgets.dart';
import 'package:lost_and_found/view/widget/person_menu.dart';
import 'package:lost_and_found/view/widget/search_results.dart';

/// One person: their face, name and every photo they are in. It uses the same tiles and viewers as search results
/// and collections.
class PersonScreen extends StatefulWidget {
  const PersonScreen({super.key, required this.person});

  final Person person;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

/// Registers itself as open after the first frame, because opening notifies listeners, which cannot happen
/// mid-build. Until the person is loaded, the header shows what the screen was given. When the person is hidden or
/// merged away from here there is nothing left to show, so the screen leaves. Together, Merge, Split, Review, Hide
/// and Export are the buttons floating round the photo below, not hidden behind a tap. The Then and now card shows
/// their first year and their latest side by side, when there are enough photos over enough time.
class _PersonScreenState extends State<PersonScreen> {
  late final FacesController _faces = Get.find<FacesController>();

  /// True once this page has registered itself as open.
  bool _pushed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pushed = true;
      _faces.openPerson(widget.person, push: true);
    });
  }

  @override
  void dispose() {
    if (_pushed) _faces.closePerson();
    super.dispose();
  }

  Future<void> _rename(Person person) async {
    final name = await showRenamePersonDialog(context, person.name);
    if (name != null) _faces.rename(person, name);
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<FacesController>(
      builder: (faces) {
        final person = faces.active;
        final native = Get.find<NativeController>();
        final textTheme = Theme.of(context).textTheme;

        final shown = person ?? widget.person;

        if (person == null && faces.photos.isEmpty && !faces.isLoadingPhotos && _opened) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
        }
        if (person != null) _opened = true;

        return Scaffold(
          backgroundColor: AppColors.canvas,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.ink),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      PersonHeadActions(faces: _faces, person: shown, size: 104),
                      const SizedBox(height: AppSpacing.md),
                      InkWell(
                        onTap: () => _rename(shown),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                shown.name ?? 'Add a name',
                                style: shown.name != null
                                    ? textTheme.titleLarge
                                    : textTheme.titleLarge?.copyWith(color: AppColors.ink48),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              const Icon(Icons.edit_outlined, size: 16, color: AppColors.ink48),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        shown.photoCount == 1 ? '1 photo' : '${shown.photoCount} photos',
                        style: textTheme.bodySmall?.copyWith(color: AppColors.ink48),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: ThenAndNowCard(person: shown)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  sliver: collectionResultsGrid(
                    controller: native,
                    results: faces.photos,
                    bytesFor: (item) => faces.photoThumbs[FacesController.thumbKey(item)],
                    matchQuery: '',
                    loading: faces.isLoadingThumbs,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _opened = false;
}
