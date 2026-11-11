import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lost_and_found/features/collections/controllers/collections_controller.dart';
import 'package:lost_and_found/features/people/controllers/faces_controller.dart';
import 'package:lost_and_found/core/native/native_controller.dart';
import 'package:lost_and_found/features/collections/models/collection_model.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/features/people/view/widgets/face_widgets.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_input_field.dart';
import 'package:lost_and_found/features/search/view/widgets/mention_text_controller.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/core/media/media_service.dart';
import 'package:lost_and_found/features/people/models/person.dart';
import 'package:lost_and_found/features/search/services/search_service.dart';
part 'new_collection_sheet/shared.dart';
part 'new_collection_sheet/collection_sheet.dart';

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
