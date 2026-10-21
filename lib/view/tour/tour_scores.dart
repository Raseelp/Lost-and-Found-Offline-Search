import 'package:lost_and_found/view/tour/tour_samples.dart';

/// How close each sample photo is to a search, for the film on the fourth page. The tour runs before the search model
/// has been downloaded, so nothing real can be worked out: the scores are made up ahead of time, in the range the real
/// model gives (low: about 0.1 to 0.35, not close to 1), and in the order [kSampleQueries] has for the search.
class TourScores {
  TourScores._(this._scores);

  /// The best match gets 0.33, and each place after it 0.015 less; the photos that are not among the matches get a
  /// steady made-up score between 0.12 and 0.2.
  factory TourScores.forQuery(SampleQuery query, List<String> ids) {
    return TourScores._({
      for (final id in ids)
        id: query.best.contains(id)
            ? 0.33 - 0.015 * query.best.indexOf(id)
            : 0.12 + (_hash(id) % 80) / 1000,
    });
  }

  final Map<String, double> _scores;

  /// How close a photo is to the words.
  double score(String id) => _scores[id]!;

  static int _hash(String s) {
    var h = 17;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }
}
