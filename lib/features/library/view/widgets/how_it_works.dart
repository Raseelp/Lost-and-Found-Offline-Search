import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';

/// A question and its answer, as written on the Your data page.
class _Entry {
  const _Entry(this.question, this.answer);

  final String question;
  final List<String> answer;
}

const _entries = [
  _Entry('Does anything leave my phone?', [
    'No. Your photos, videos, faces and searches stay on this phone. The app has no account, no ads and no analytics, and nothing it makes is uploaded anywhere.',
    'What it makes is kept in the app\'s private storage, where other apps cannot read it.',
  ]),
  _Entry('How does search find my photos?', [
    'When you scan, a small AI model that runs on your phone looks at each photo and turns it into a list of numbers that describes what is in it.',
    'When you type a search, the same model turns your words into numbers in the same way. The app then shows the photos whose numbers are closest to your words. That is why you can search for "a dog on a beach" without anyone tagging your photos.',
    'For a video, several frames spread through it are looked at, so a search can take you to the right moment.',
  ]),
  _Entry('How does the app recognise faces?', [
    'It finds each face in a photo, straightens it, and turns it into a list of numbers that describes how that face looks.',
    'Faces whose numbers are close are grouped as one person. Clear faces start a group. Small or blurry ones can only join a group that already exists, so they do not mix people up.',
    'Faces are only compared with each other, inside your own photos. There is no list of known people to match against, and the names you give are saved on this phone only.',
  ]),
  _Entry('How does it work without the internet?', [
    'The models for search and for faces are stored on your phone and run on its own processor. There is no server to ask, so search, faces, collections and memories all work with the phone offline, even in flight mode.',
  ]),
  _Entry('What does the app keep about my photos?', [
    'For each photo or video, a list of numbers, where it is on your phone and when it was taken. The numbers are not a picture, and the photo itself is not stored. Your originals stay where they are, and the app never copies them.',
    'For each face, where it sits in the photo and its own list of numbers.',
    'It also keeps the collections you made, the names you gave people, and its settings.',
  ]),
  _Entry('How do collections fill themselves?', [
    'A collection stores only what you asked for: some words, a person, or a photo to match. It does not store a list of photos.',
    'Each time you open it, the app looks through the index for the best matches. So new photos appear in a collection by themselves as indexing goes on.',
  ]),
  _Entry('Why does scanning take time and battery?', [
    'Each photo is run through the model on your phone, and a large library has thousands. It can take from minutes to hours, and the phone may get warm.',
    'It keeps going in the background, with a notification. You can stop it at any time and continue later. Search already works on what is finished.',
  ]),
];

/// The questions about how the app works, each opening to its answer when tapped.
class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _entries.length; i++) ...[
          if (i == 0) const Divider(height: 1, color: AppColors.hairline),
          _Question(_entries[i]),
          const Divider(height: 1, color: AppColors.hairline),
        ],
      ],
    );
  }
}

class _Question extends StatefulWidget {
  const _Question(this.entry);

  final _Entry entry;

  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(child: Text(widget.entry.question, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                    const SizedBox(width: AppSpacing.md),
                    ExcludeSemantics(
                      child: AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: calm(context) ? Duration.zero : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: AppColors.ink48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SmoothSize(
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < widget.entry.answer.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
                        Text(widget.entry.answer[i], style: text.bodyMedium?.copyWith(color: AppColors.ink80, height: 1.5)),
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
