import 'package:flutter/services.dart';
import 'package:lost_and_found/core/native/native_channel.dart';
import 'package:lost_and_found/features/people/models/face_scan.dart';
import 'package:lost_and_found/features/people/models/merge.dart';
import 'package:lost_and_found/features/people/models/person.dart';
import 'package:lost_and_found/features/people/models/photo_face.dart';

/// The people found in photos and videos, and fixing them.
class PeopleService {
  Future<List<Person>> listPeople({bool hidden = false}) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('listPeople', {
      'hidden': hidden,
    });
    return (list ?? const [])
        .map((e) => Person.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<Person?> personSummary(int personId) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'personSummary',
      {'personId': personId},
    );
    return map == null ? null : Person.fromMap(map);
  }

  /// A person's photos, in the shape the search results grid reads.
  Future<List<Map<String, dynamic>>> personPhotos(int personId) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('personPhotos', {
      'personId': personId,
    });
    return (list ?? const [])
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Photos by several people at once. [mode]: 'any', 'together' or 'only'
  /// (see PeopleMode). Same shape as [personPhotos].
  Future<List<Map<String, dynamic>>> peoplePhotos(
    List<int> personIds,
    String mode,
  ) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('peoplePhotos', {
      'personIds': personIds,
      'mode': mode,
    });
    return (list ?? const [])
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// How many photos each mode would give for these people.
  Future<Map<String, int>> peopleCounts(List<int> personIds) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'peopleCounts',
      {'personIds': personIds},
    );
    return {
      for (final e in (map ?? const <String, dynamic>{}).entries)
        e.key: (e.value as num).toInt(),
    };
  }

  /// The people listed on the People tab who are in these photos and videos (by uri), each with how many of them
  /// they are in, most first.
  Future<List<({int personId, int count})>> peopleIn(List<String> uris) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('peopleIn', {'uris': uris});
    return [
      for (final e in (list ?? const []).cast<Map>())
        (personId: (e['personId'] as num).toInt(), count: (e['count'] as num).toInt()),
    ];
  }

  Future<List<PersonFace>> personFaces(int personId) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('personFaces', {
      'personId': personId,
    });
    return (list ?? const [])
        .map((e) => PersonFace.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// The recognised people in one photo, with where their faces are.
  ///
  /// [token] identifies the viewer asking: if it is closed before the request's turn
  /// comes, [cancelPhotoFaces] with the same token skips the (then pointless) scan.
  Future<List<PhotoFace>> photoFaces(String uri, {int? token}) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('photoFaces', {
      'uri': uri,
      'token': token,
    });
    return (list ?? const [])
        .map((e) => PhotoFace.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// Who is in the frame at [positionMs] of a video, looked up on the spot (nothing is stored). Faces come back with
  /// made-up negative ids, just to tell them apart. [token] as in [photoFaces].
  Future<List<PhotoFace>> videoFaces(
    String uri,
    int positionMs, {
    int? token,
  }) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('videoFaces', {
      'uri': uri,
      'positionMs': positionMs,
      'token': token,
    });
    return (list ?? const [])
        .map((e) => PhotoFace.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// The faces a scan stored for the frame at exactly [tsMs] of a video: [VideoFrameFaces.exact]
  /// says whether their positions can be trusted on the player's picture at once.
  Future<VideoFrameFaces> videoFrameFaces(String uri, int tsMs) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'videoFrameFaces',
      {'uri': uri, 'tsMs': tsMs},
    );
    if (map == null) return VideoFrameFaces(false, const []);
    return VideoFrameFaces(
      map['exact'] as bool? ?? false,
      ((map['faces'] as List?) ?? const [])
          .map((e) => PhotoFace.fromMap(e as Map<dynamic, dynamic>))
          .toList(),
    );
  }

  /// The people the background scan found in a video, and when (earliest first).
  Future<List<VideoPerson>> videoPeople(String uri) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('videoPeople', {
      'uri': uri,
    });
    return (list ?? const [])
        .map((e) => VideoPerson.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// Whether a video can be scanned and has been ('needs', 'done', 'unavailable'), and how loose
  /// the next scan of it will be.
  Future<VideoScanInfo> videoScanState(String uri) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'videoScanState',
      {'uri': uri},
    );
    return map == null
        ? VideoScanInfo('unavailable', 0, null)
        : VideoScanInfo.fromMap(map);
  }

  /// A video the user asked to scan: scans it if it has not been (its people are then ready for [videoPeople]). True
  /// if it was scanned; false if it already was, or can't be. Follow its progress with [photoScanStatus] (key "video:"
  /// + the uri).
  Future<VideoScanResult> scanVideoFaces(String uri, {int? token}) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'scanVideoFaces',
      {'uri': uri, 'token': token},
    );
    return map == null
        ? VideoScanResult(false, 0, 0)
        : VideoScanResult.fromMap(map);
  }

  Future<void> cancelPhotoFaces(int token) =>
      nativeChannel.invokeMethod('cancelPhotoFaces', {'token': token});

  /// How far the scan of a photo opened in the viewer has got, or null if none is running.
  Future<PhotoScanStatus?> photoScanStatus(String uri) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'photoScanStatus',
      {'uri': uri},
    );
    return map == null ? null : PhotoScanStatus.fromMap(map);
  }

  /// A square picture of one face.
  Future<Uint8List> faceCrop(int faceId, {int size = 256}) async {
    final bytes = await nativeChannel.invokeMethod<List<int>>('faceCrop', {
      'faceId': faceId,
      'size': size,
    });
    return Uint8List.fromList(bytes!);
  }

  Future<void> renamePerson(int personId, String? name) => nativeChannel
      .invokeMethod('renamePerson', {'personId': personId, 'name': name});

  Future<void> hidePerson(int personId, bool hidden) => nativeChannel.invokeMethod(
    'hidePerson',
    {'personId': personId, 'hidden': hidden},
  );

  /// Joins [otherId] into [keepId]; the name and edits carry over.
  ///
  /// Returns the merge's history id (for undoing it), 0 if nothing was merged.
  Future<int> mergePeople({required int keepId, required int otherId}) async {
    final id = await nativeChannel.invokeMethod<int>('mergePeople', {
      'keepId': keepId,
      'otherId': otherId,
    });
    return id ?? 0;
  }

  /// Merges that can still be undone, newest first.
  Future<List<MergeRecord>> mergeHistory() async {
    final list = await nativeChannel.invokeListMethod<dynamic>('mergeHistory');
    return (list ?? const [])
        .map((e) => MergeRecord.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// The two groups a person's faces fall into, or null if there are too few clear faces.
  Future<SplitPreview?> previewSplit(int personId) async {
    final map = await nativeChannel.invokeMapMethod<String, dynamic>(
      'previewSplit',
      {'personId': personId},
    );
    return map == null ? null : SplitPreview.fromMap(map);
  }

  /// Moves [faceIds] out of the person into a separate person; returns that person's id.
  Future<int> splitPerson(int personId, List<int> faceIds) async =>
      await nativeChannel.invokeMethod<int>('splitPerson', {
        'personId': personId,
        'faceIds': faceIds,
      }) ??
      0;

  /// Splits a merged person back out; false if that merge can't be found any more.
  Future<bool> undoMerge(int id) async =>
      await nativeChannel.invokeMethod<bool>('undoMerge', {'id': id}) ?? false;

  /// Pairs of people who may be the same person, most likely first.
  Future<List<MergeSuggestion>> suggestMerges({int limit = 20}) async {
    final list = await nativeChannel.invokeListMethod<dynamic>('suggestMerges', {
      'limit': limit,
    });
    return (list ?? const [])
        .map((e) => MergeSuggestion.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  /// "These are different people": never suggested or merged automatically again.
  Future<void> rejectMerge(int a, int b) =>
      nativeChannel.invokeMethod('rejectMerge', {'a': a, 'b': b});

  Future<void> removeFace(int faceId) =>
      nativeChannel.invokeMethod('removeFace', {'faceId': faceId});
}
