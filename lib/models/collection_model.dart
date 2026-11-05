import 'dart:convert';

import 'package:flutter/material.dart';

/// A named, live, on-device smart search.
///
/// The name and the query are independent: search "dog", call it "Mittu". Only the definition is stored. Members are
/// worked out from the embedding index every time, so new scans show up on their own.
class SmartCollection {
  const SmartCollection({
    required this.id,
    required this.name,
    required this.prompts,
    this.icon = Icons.bookmark_border_rounded,
    this.explainQuery,
    this.contentMode = 'both',
    this.sensitivity = defaultSensitivity,
    this.isBuiltIn = false,
    this.createdAt = 0,
    this.kind = kindText,
    this.seedEmbedding,
    this.seedUri,
    this.seedTimestampMs,
    this.seedModel,
    this.personIds = const [],
  });

  static const String kindText = 'text';
  static const String kindPhotos = 'photos';

  /// Standard deviations above a query's library-wide mean score that an item must reach to count as a member.
  /// It can be set for each collection.
  static const double defaultSensitivity = 3.0;

  final String id;
  final String name;
  /// Shown on a card that has no cover photo yet. Built-ins each have one, and a collection you made uses the generic
  /// bookmark.
  final IconData icon;

  /// Phrasings of the same idea, embedded separately and averaged, which is more accurate than a single phrase. A
  /// collection you made has exactly one.
  final List<String> prompts;

  /// Short phrase used to explain a match ("why this matched") when a result is opened from this collection.
  /// Defaults to the first prompt.
  final String? explainQuery;

  /// One of 'both', 'images' or 'videos'.
  final String contentMode;
  final double sensitivity;
  final bool isBuiltIn;
  final int createdAt;

  /// One of 'text' (a phrase) or 'photos' (found by looking like a photo you saved a search from). A photo collection
  /// stores that photo's embedding itself, so it keeps working if the original file is deleted.
  final String kind;
  final List<double>? seedEmbedding;
  final String? seedUri;
  final int? seedTimestampMs;

  /// The search model that made [seedEmbedding], see CollectionsController.modelVersion. A vector from another model
  /// cannot be compared with the library's, so a photo collection whose seed came from another model has the photo
  /// embedded again. Null means it was made before this was recorded, by the OpenAI CLIP model the app used then.
  final String? seedModel;

  /// Ids of the recognised people mentioned when this collection was made, such as "@Raseel at the beach".
  /// Membership narrows to photos and videos with all of them in it, the same "together" rule as the search box's
  /// @-mention. Empty when there is no person filter.
  final List<int> personIds;

  bool get isPhotos => kind == kindPhotos;

  /// Built-ins that are things you keep rather than moments you look back on: papers, screens, tickets, notes and
  /// forwards. The Collections tab puts them after the rest and never features them on the big card.
  static const Set<String> everydayIds = {
    'builtin_documents',
    'builtin_screenshots',
    'builtin_tickets_passes',
    'builtin_notes_whiteboards',
    'builtin_memes',
  };

  bool get isEveryday => isBuiltIn && everydayIds.contains(id);

  String get queryText => explainQuery ?? prompts.first;

  /// Changes whenever anything that affects the cached query embedding
  /// changes, so a stale one is never reused.
  String get embeddingSignature => prompts.join('|');

  /// [explainQuery] is only needed when [prompts] is given but the short phrase should stay, as when restoring a
  /// built-in's own override. [seedEmbedding] and [seedModel] are set when a photo collection's photo has been
  /// embedded again by the current search model.
  SmartCollection copyWith({
    String? name,
    List<String>? prompts,
    String? contentMode,
    double? sensitivity,
    String? explainQuery,
    List<int>? personIds,
    List<double>? seedEmbedding,
    String? seedModel,
  }) {
    return SmartCollection(
      id: id,
      name: name ?? this.name,
      icon: icon,
      prompts: prompts ?? this.prompts,
      explainQuery: explainQuery ?? (prompts != null ? null : this.explainQuery),
      contentMode: contentMode ?? this.contentMode,
      sensitivity: sensitivity ?? this.sensitivity,
      isBuiltIn: isBuiltIn,
      createdAt: createdAt,
      kind: kind,
      seedEmbedding: seedEmbedding ?? this.seedEmbedding,
      seedUri: seedUri,
      seedTimestampMs: seedTimestampMs,
      seedModel: seedModel ?? this.seedModel,
      personIds: personIds ?? this.personIds,
    );
  }

  /// This photo collection looking like another photo: [uri] (and the moment of a video, if it is one) with
  /// [embedding], the vector the search model [model] made for it. Everything else stays as it is.
  SmartCollection withSeed({
    required String uri,
    int? timestampMs,
    required List<double> embedding,
    required String model,
  }) {
    return SmartCollection(
      id: id,
      name: name,
      icon: icon,
      prompts: prompts,
      explainQuery: explainQuery,
      contentMode: contentMode,
      sensitivity: sensitivity,
      isBuiltIn: isBuiltIn,
      createdAt: createdAt,
      kind: kind,
      seedEmbedding: embedding,
      seedUri: uri,
      seedTimestampMs: timestampMs,
      seedModel: model,
      personIds: personIds,
    );
  }

  Map<String, Object?> toRow({int hiddenState = 0}) => {
    'id': id,
    'name': name,
    'emoji': '',
    'prompts': jsonEncode(prompts),
    'contentMode': contentMode,
    'sensitivity': sensitivity,
    'isBuiltIn': isBuiltIn ? 1 : 0,
    'hidden': hiddenState,
    'createdAt': createdAt,
    'kind': kind,
    'seed': isPhotos
        ? jsonEncode({
            'embedding': seedEmbedding,
            'uri': seedUri,
            'timestampMs': seedTimestampMs,
            'model': seedModel,
          })
        : null,
    'personIds': personIds.isEmpty ? null : jsonEncode(personIds),
  };

  factory SmartCollection.fromRow(Map<String, Object?> row) {
    final kind = row['kind'] as String? ?? kindText;
    final seedRaw = row['seed'] as String?;
    final seed = kind == kindPhotos && seedRaw != null
        ? jsonDecode(seedRaw) as Map<String, dynamic>
        : null;
    return SmartCollection(
      kind: kind,
      icon: kind == kindPhotos ? Icons.photo_library_outlined : Icons.bookmark_border_rounded,
      seedEmbedding: (seed?['embedding'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      seedUri: seed?['uri'] as String?,
      seedTimestampMs: (seed?['timestampMs'] as num?)?.toInt(),
      seedModel: seed?['model'] as String?,
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      prompts: (jsonDecode(row['prompts'] as String? ?? '[]') as List).cast<String>(),
      contentMode: row['contentMode'] as String? ?? 'both',
      sensitivity: (row['sensitivity'] as num?)?.toDouble() ?? defaultSensitivity,
      isBuiltIn: (row['isBuiltIn'] as int? ?? 0) == 1,
      createdAt: row['createdAt'] as int? ?? 0,
      personIds: (row['personIds'] as String?) == null
          ? const []
          : (jsonDecode(row['personIds'] as String) as List).cast<num>().map((e) => e.toInt()).toList(),
    );
  }
}

/// What the last scoring pass found for one collection: the count and a few cover items for its card.
class CollectionStats {
  const CollectionStats({required this.count, required this.covers});

  final int count;
  final List<CollectionCover> covers;

  static const empty = CollectionStats(count: 0, covers: []);
}

class CollectionCover {
  const CollectionCover({required this.uri, required this.isVideo, required this.timestampMs});

  final String uri;
  final bool isVideo;
  final int timestampMs;

  String get cacheKey => isVideo ? '$uri@$timestampMs' : uri;

  factory CollectionCover.fromMap(Map<dynamic, dynamic> map) {
    return CollectionCover(
      uri: map['path'] as String? ?? '',
      isVideo: map['isVideo'] as bool? ?? false,
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What a collection that is still being made would hold, see CollectionsController.previewCollection. It has how
/// many items, the best few, and the people in them with how many of the items each is in, most first.
class CollectionPreview {
  const CollectionPreview({required this.count, required this.items, required this.people});

  final int count;
  final List<CollectionCover> items;
  final List<({int personId, int count})> people;
}
