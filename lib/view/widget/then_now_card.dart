import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/controllers/memories_controller.dart';
import 'package:lost_and_found/models/memories.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/then_now_screen.dart';

/// "Then and now" on a person's page: their clearest photo from their first year next to the clearest from
/// their latest, tilted a little each way. Not there when there are not enough photos over enough time.
/// Opens the comparison.
class ThenAndNowCard extends StatefulWidget {
  const ThenAndNowCard({super.key, required this.person});

  final Person person;

  @override
  State<ThenAndNowCard> createState() => _ThenAndNowCardState();
}

class _ThenAndNowCardState extends State<ThenAndNowCard> {
  final MemoriesController _memories = Get.find<MemoriesController>();
  ThenNow? _found;
  int _loadedFor = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ThenAndNowCard old) {
    super.didUpdateWidget(old);
    if (old.person.id != widget.person.id ||
        old.person.photoCount != widget.person.photoCount) {
      _load();
    }
  }

  Future<void> _load() async {
    final person = widget.person;
    _loadedFor = person.id;
    final found = await _memories.thenNowFor(person);
    if (!mounted || _loadedFor != person.id) return;
    setState(() => _found = found);
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: found == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: _CardBody(
                person: widget.person,
                found: found,
                memories: _memories,
              ),
            ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.person,
    required this.found,
    required this.memories,
  });

  final Person person;
  final ThenNow found;
  final MemoriesController memories;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    return Semantics(
      button: true,
      label: 'Then and now, ${found.spanLabel} apart. Opens the comparison.',
      excludeSemantics: true,
      child: Material(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ThenAndNowScreen(person: person, found: found),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                _Portrait(
                  side: found.then,
                  memories: memories,
                  tilt: -4,
                  year: found.then.taken.year,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: AppColors.ink48,
                ),
                const SizedBox(width: AppSpacing.sm),
                _Portrait(
                  side: found.now,
                  memories: memories,
                  tilt: 3,
                  year: found.now.taken.year,
                ),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              found.isNow(now) ? 'THEN & NOW' : 'THEN & LATEST',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: AppColors.primary,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${found.spanLabel} apart',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small tilted portrait with its year underneath.
class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.side,
    required this.memories,
    required this.tilt,
    required this.year,
  });

  final ThenNowSide side;
  final MemoriesController memories;
  final double tilt;
  final int year;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: tilt * math.pi / 180,
          child: Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow.withValues(alpha: 0.14),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: PortraitImage(side: side, memories: memories),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$year',
          style: textTheme.labelSmall?.copyWith(
            color: AppColors.ink48,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The head-and-shoulders picture of [side], fading in once it is made.
class PortraitImage extends StatefulWidget {
  const PortraitImage({
    super.key,
    required this.side,
    required this.memories,
    this.fit = BoxFit.cover,
  });

  final ThenNowSide side;
  final MemoriesController memories;
  final BoxFit fit;

  @override
  State<PortraitImage> createState() => _PortraitImageState();
}

class _PortraitImageState extends State<PortraitImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PortraitImage old) {
    super.didUpdateWidget(old);
    if (old.side.cropKey != widget.side.cropKey) {
      // The old picture stays until the new one is made (no grey flash when a thumbnail is picked).
      _load();
    }
  }

  Future<void> _load() async {
    final side = widget.side;
    final bytes = await widget.memories.portrait(side);
    if (!mounted || widget.side.cropKey != side.cropKey) {
      return;
    }
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return ColoredBox(
      color: AppColors.hairline,
      child: bytes == null
          ? const SizedBox.expand()
          : Image.memory(
              bytes,
              fit: widget.fit,
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
              frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                opacity: frame == null && !sync ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                child: child,
              ),
            ),
    );
  }
}
