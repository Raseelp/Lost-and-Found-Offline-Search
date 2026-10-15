import 'package:flutter/material.dart';
import 'package:lost_and_found/models/memories.dart';
import 'package:lost_and_found/models/people_timeline.dart';
import 'package:lost_and_found/services/native_services.dart';
import 'package:lost_and_found/utils/app_colors.dart';
import 'package:lost_and_found/utils/app_radius.dart';
import 'package:lost_and_found/utils/app_spacing.dart';
import 'package:lost_and_found/view/widget/memory_widgets.dart';
import 'package:lost_and_found/view/widget/timeline_preview.dart';

/// Every photo and video from one day of a past year, in the order they were taken.
class DayPhotosScreen extends StatefulWidget {
  const DayPhotosScreen({
    super.key,
    required this.from,
    required this.title,
    this.days = 1,
  });

  /// The start of the first day (midnight); it runs for [days] days.
  final DateTime from;
  final String title;
  final int days;

  @override
  State<DayPhotosScreen> createState() => _DayPhotosScreenState();
}

class _DayPhotosScreenState extends State<DayPhotosScreen> {
  static const int _columns = 3;
  static const double _gap = 4;

  final PreviewLoader _loader = PreviewLoader();
  List<PreviewPhoto> _photos = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final next = DateTime(
        widget.from.year,
        widget.from.month,
        widget.from.day + widget.days,
      );
      final photos = await NativeServices().memoryDay(widget.from, next);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
      });
    } catch (e) {
      debugPrint('day photos failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final count = _photos.length;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.base,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: AppColors.ink,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: textTheme.titleLarge),
                        Text(
                          _loading
                              ? ' '
                              : (count == 1
                                    ? '1 photo or video'
                                    : '$count photos and videos'),
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
            Expanded(
              child: _failed
                  ? Center(
                      child: Text(
                        "Couldn't load this day.",
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink48,
                        ),
                      ),
                    )
                  : (!_loading && _photos.isEmpty)
                  ? Center(
                      child: Text(
                        'Nothing from this day.',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.ink48,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.base,
                        AppSpacing.xs,
                        AppSpacing.base,
                        MediaQuery.of(context).padding.bottom + AppSpacing.xxl,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _columns,
                            mainAxisSpacing: _gap,
                            crossAxisSpacing: _gap,
                          ),
                      itemCount: _loading ? 12 : count,
                      itemBuilder: (context, i) {
                        if (_loading) {
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.parchment,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          );
                        }
                        final photo = _photos[i];
                        return MemoryTile(
                          photo: photo,
                          loader: _loader,
                          large: true,
                          radius: AppRadius.md,
                          onTap: () => openMemoryPhoto(context, _loader, photo),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The days a [MemoryYear] stands for, for [DayPhotosScreen]: its date (a week round it when the date itself has
/// nothing in any year), and what to call it.
({DateTime from, int days, String title}) dayOf(
  MemoryYear year,
  OnThisDay today,
) {
  final date = DateTime(year.year, today.month, today.day);
  if (today.exact.isNotEmpty) {
    return (
      from: date,
      days: 1,
      title: '${dayLabel(date.month, date.day)}, ${date.year}',
    );
  }
  return (
    from: DateTime(date.year, date.month, date.day - 3),
    days: 7,
    title: 'Around ${dayLabel(date.month, date.day)}, ${date.year}',
  );
}
