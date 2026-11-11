import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_text_controller.dart';
import 'package:lost_and_found/features/people/models/person.dart';

/// A text field with the search box's "@name" autocomplete, for any place where someone describes who is in a photo
/// alongside free text. Typing "@" opens a dropdown of matching people below the field, and picking one inserts the
/// name as a recognised mention. Use it instead of a plain TextField wherever a query is typed (see
/// [MentionTextEditingController]). The search box's own pill uses [MentionDropdown] directly, as it anchors its own
/// field.
class MentionInputField extends StatefulWidget {
  const MentionInputField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration,
    this.style,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
  });

  final MentionTextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextStyle? style;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// Called on every keystroke, mention pick or recognition change, not only on submission.
  final VoidCallback? onChanged;

  @override
  State<MentionInputField> createState() => _MentionInputFieldState();
}

class _MentionInputFieldState extends State<MentionInputField> {
  final LayerLink _mentionLink = LayerLink();
  OverlayEntry? _mentionEntry;
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _removeMentionOverlay();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onChanged?.call();
    if (widget.controller.activeMentionQuery == null) {
      _removeMentionOverlay();
    } else if (_mentionEntry == null) {
      _mentionEntry = OverlayEntry(
        builder: (_) => MentionDropdown(
          link: _mentionLink,
          controller: widget.controller,
          focusNode: _focusNode,
        ),
      );
      Overlay.of(context).insert(_mentionEntry!);
    }
  }

  void _removeMentionOverlay() {
    final entry = _mentionEntry;
    if (entry == null) return;
    _mentionEntry = null;
    entry.remove();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _mentionLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        style: widget.style,
        decoration: widget.decoration ?? const InputDecoration(),
      ),
    );
  }
}

/// The "@" autocomplete dropdown: the named people matching what is typed after the "@". It is anchored to the field
/// through [link], so it follows the field when it scrolls. Picking a person confirms that exact person (see
/// [MentionTextEditingController.selectMention]), and the tap lands outside the field and unfocuses it, so picking
/// gives the focus back. The overlay gives its entries a full-screen box, so it is unconstrained to size to its short
/// list. It is public so that [MentionInputField] and the search box's pill look and behave the same.
class MentionDropdown extends StatelessWidget {
  const MentionDropdown({
    super.key,
    required this.link,
    required this.controller,
    required this.focusNode,
  });

  final LayerLink link;
  final MentionTextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, AppSpacing.xs),
      child: UnconstrainedBox(
        alignment: Alignment.topLeft,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final query = controller.activeMentionQuery;
            if (query == null) return const SizedBox.shrink();

            final people = Get.isRegistered<FacesController>()
                ? Get.find<FacesController>().people
                : const <Person>[];
            final already = controller.recognizedPeople.map((p) => p.id).toSet();
            final matches = people
                .where((p) => (p.name ?? '').isNotEmpty)
                .where((p) => !already.contains(p.id))
                .where((p) => p.name!.toLowerCase().contains(query.toLowerCase()))
                .take(6)
                .toList();
            if (matches.isEmpty) return const SizedBox.shrink();

            return Material(
              elevation: 8,
              shadowColor: AppColors.ink.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              color: AppColors.canvas,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260, maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final person = matches[i];
                    return InkWell(
                      onTap: () {
                        controller.selectMention(person);
                        focusNode.requestFocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            FaceAvatar(faceId: person.coverFaceId, size: 32),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                person.name!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
