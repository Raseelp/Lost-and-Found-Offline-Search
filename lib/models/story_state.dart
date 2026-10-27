import 'dart:convert';

/// One picture of a story: where it is, not the picture itself (loaded when it is shown).
class StoryFrame {
  const StoryFrame({required this.uri, required this.isVideo, required this.timestampMs});

  final String uri;
  final bool isVideo;
  final int timestampMs;

  Map<String, dynamic> toJson() => {'u': uri, 'v': isVideo, 't': timestampMs};

  factory StoryFrame.fromJson(Map<String, dynamic> m) =>
      StoryFrame(uri: m['u'] as String, isVideo: m['v'] as bool? ?? false, timestampMs: (m['t'] as num?)?.toInt() ?? 0);
}

/// What is remembered about one ring: its current edition (the story it is showing), when that was made and
/// looked at, and what has been used up. Times are milliseconds since the epoch, 0 for "never".
class RingState {
  RingState(this.key);

  final String key;

  /// When the current edition was made, and when it was last opened. An edition that was made and not opened yet has
  /// `viewedAt < builtAt`.
  int builtAt = 0;
  int viewedAt = 0;

  /// How many photos and videos the ring held when its edition was made, and how many of them could be used then
  /// (screenshots are left out): what a round can show is known from the second.
  int lastCount = 0;
  int eligible = 0;

  /// The way the current edition was chosen (see StoryPlanner) and its caption.
  String? lens;
  String? caption;
  List<StoryFrame> frames = [];

  /// A ring that has used up what it had rests until then; a ring set aside with "Not now" is left out until then.
  int restUntil = 0;
  int mutedUntil = 0;

  /// How many of its photos and videos went into an edition in the current round (kept in the ledger).
  int shownCount = 0;

  bool get hasEdition => frames.isNotEmpty;

  String get framesJson => jsonEncode([for (final f in frames) f.toJson()]);

  static List<StoryFrame> framesFrom(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return [for (final e in jsonDecode(json) as List) StoryFrame.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      return [];
    }
  }

  Map<String, Object?> toMap() => {
    'key': key,
    'built_at': builtAt,
    'viewed_at': viewedAt,
    'last_count': lastCount,
    'eligible': eligible,
    'lens': lens,
    'caption': caption,
    'frames': framesJson,
    'rest_until': restUntil,
    'muted_until': mutedUntil,
  };

  factory RingState.fromMap(Map<String, Object?> m) => RingState(m['key'] as String)
    ..builtAt = (m['built_at'] as num?)?.toInt() ?? 0
    ..viewedAt = (m['viewed_at'] as num?)?.toInt() ?? 0
    ..lastCount = (m['last_count'] as num?)?.toInt() ?? 0
    ..eligible = (m['eligible'] as num?)?.toInt() ?? 0
    ..lens = m['lens'] as String?
    ..caption = m['caption'] as String?
    ..frames = framesFrom(m['frames'] as String?)
    ..restUntil = (m['rest_until'] as num?)?.toInt() ?? 0
    ..mutedUntil = (m['muted_until'] as num?)?.toInt() ?? 0;
}
