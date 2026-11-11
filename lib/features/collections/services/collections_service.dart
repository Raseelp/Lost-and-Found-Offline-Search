import 'package:lost_and_found/core/native/native_channel.dart';

/// Scoring photos against a collection and listing what belongs to it.
class CollectionsService {
  /// One pass over the index scoring every collection at once (see the collections section of EmbeddingEngine).
  /// [collections] entries carry id, embedding, contentMode and k.
  Future<List<Map<String, dynamic>>> scoreCollections(
    List<Map<String, dynamic>> collections,
  ) async {
    final results = await nativeChannel.invokeMethod<List<dynamic>>(
      'scoreCollections',
      {'collections': collections},
    );
    return (results ?? const [])
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Every member of one collection, best first (capped at [limit]).
  Future<List<Map<String, dynamic>>> collectionMembers(
    Map<String, dynamic> collection, {
    int limit = 200,
  }) async {
    final results = await nativeChannel.invokeMethod<List<dynamic>>(
      'collectionMembers',
      {
        'collections': [collection],
        'limit': limit,
      },
    );
    return (results ?? const [])
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
