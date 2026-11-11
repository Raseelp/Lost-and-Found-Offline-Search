part of '../new_collection_sheet.dart';

/// The sheet that makes a new collection (from the action button, see ActionFab): what to find, in words (with
/// other ways of saying it) or by a photo to look like, a preview of what that finds and who is in it, photos,
/// videos or both, and a name taken from the words. Before anything is typed it offers a few ideas to start from.
Future<void> showNewCollectionSheet(BuildContext context, CollectionsController controller) =>
    showCollectionSheet(context, controller);

/// The same sheet, for changing a collection that exists: [editing] is filled in as it is, with everything that can be
/// set when one is made, and saving changes it in place.
Future<void> showCollectionSheet(
  BuildContext context,
  CollectionsController controller, {
  SmartCollection? editing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (_) => _CollectionSheet(controller: controller, editing: editing),
  );
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
