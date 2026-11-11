part of '../person_menu.dart';

/// Everything you can do with one person, in one menu, opened by holding a face in the People tab. Their own page
/// shows the same five actions as [PersonHeadActions], floating round their head instead.
void showPersonMenu(
  BuildContext context,
  FacesController faces,
  Person person,
) {
  showFacesSheet<void>(
    context,
    title: person.name ?? 'This person',
    builder: (sheet) => SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetRow(
          icon: Icons.edit_outlined,
          label: person.name == null ? 'Add a name' : 'Rename',
          subtitle: person.name == null ? 'So you can search for them by name' : 'Change the name shown everywhere',
          onTap: () async {
            Navigator.of(sheet).pop();
            final name = await showRenamePersonDialog(context, person.name);
            if (name != null) faces.rename(person, name);
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.folder_zip_outlined,
          label: 'Save all their photos',
          subtitle: '${person.name == null ? 'Their' : "${person.name}'s"} photos and videos in one zip file',
          onTap: () {
            Navigator.of(sheet).pop();
            openExportZip(context, select: {ExportController.personKey(person.id)});
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.groups_rounded,
          label: 'Photos with someone else',
          subtitle: "Pick a person to see photos they're both in",
          onTap: () {
            Navigator.of(sheet).pop();
            Navigator.of(context).popUntil((route) => route.isFirst);
            Get.find<HomeController>().setHomeTab(3);
            faces.startSelecting(person);
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.visibility_off_outlined,
          label: 'Hide this person',
          subtitle: 'They move to Hidden people in Settings',
          onTap: () {
            Navigator.of(sheet).pop();
            faces.setHidden(person, true);
          },
        ),
        const _MenuHeading('Fix mistakes'),
        SheetRow(
          icon: Icons.merge_type_rounded,
          label: 'Merge duplicates',
          subtitle: 'A person appears more than once? Join them',
          onTap: () {
            Navigator.of(sheet).pop();
            showMergePicker(context, faces, person);
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.call_split_rounded,
          label: 'Separate two people',
          subtitle: 'Use this when this card has two different people in it',
          onTap: () {
            Navigator.of(sheet).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SplitPersonScreen(person: person)),
            );
          },
        ),
        const Divider(height: 1, color: AppColors.dividerSoft),
        SheetRow(
          icon: Icons.grid_view_rounded,
          label: 'Check their faces',
          subtitle: 'Remove any face that belongs to someone else',
          onTap: () {
            Navigator.of(sheet).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FaceReviewScreen(person: person),
              ),
            );
          },
        ),
      ],
      ),
    ),
  );
}

/// A small heading over a group of the menu's rows, in the style of the app's other list headings.
class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.lg, AppSpacing.base, AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.ink48,
            letterSpacing: .5,
          ),
        ),
      ),
    );
  }
}
