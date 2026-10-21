import 'package:flutter/material.dart';
import 'package:lost_and_found/utils/palettes/tour_palette.dart';

/// A photo or a short video the tour uses for its demos: public-domain (CC0) pictures and clips bundled with the
/// app, so the demos work before anything is downloaded and without the person's own photos. Credits:
/// assets/tour/photos/CREDITS.txt and assets/tour/videos/CREDITS.txt.
class SamplePhoto {
  const SamplePhoto(
    this.id,
    this.label, {
    this.video = false,
    this.focus = Alignment.center,
  });

  final String id;

  /// What is in it, as the demo would describe it.
  final String label;

  /// Which part stays in view when a tile crops it (a face near the top, say).
  final Alignment focus;

  /// A four-second muted clip (the still of it is its poster) rather than a photo.
  final bool video;

  /// The picture: the photo, or the still of a video.
  String get asset =>
      video ? 'assets/tour/videos/$id.jpg' : 'assets/tour/photos/$id.jpg';

  String get videoAsset => 'assets/tour/videos/$id.mp4';
}

// The first seven are what shows before the first search.
const List<SamplePhoto> kSamplePhotos = [
  SamplePhoto('v_football', 'A football match with flares', video: true),
  SamplePhoto('dog_beach', 'A dog on a beach'),
  SamplePhoto('tajmahal', 'The Taj Mahal and its gardens'),
  SamplePhoto('party', 'Friends at a party'),
  SamplePhoto(
    'v_cooking',
    'Cooking chicken and broccoli in a pan',
    video: true,
  ),
  SamplePhoto('sunset', 'Boats at sunset'),
  SamplePhoto('v_husky', 'A husky howling in a car', video: true),
  SamplePhoto('hike', 'Friends on a hike'),
  SamplePhoto('pro_ronaldo', 'Cristiano Ronaldo taking a free kick'),
  SamplePhoto('houseboat', 'A houseboat in the Kerala backwaters'),
  SamplePhoto('cheering', 'A crowd cheering'),
  SamplePhoto('puppy', 'A newborn puppy'),
  SamplePhoto('running', 'Runners in a race'),
  SamplePhoto('v_surf', 'Body surfing at sunset', video: true),
  SamplePhoto('cake', 'A birthday cake'),
  SamplePhoto('qutub', 'The Qutb Minar in Delhi'),
  SamplePhoto('friends_walk', 'Three friends walking'),
  SamplePhoto('kayak', 'A kayak at sunset'),
  SamplePhoto('pro_sansiro', 'San Siro during a Serie A match'),
  SamplePhoto('v_tram', 'A tram in the snow', video: true),
  SamplePhoto('cycling', 'Cyclists on a road'),
  SamplePhoto('dog_adult', 'A chocolate Labrador'),
  SamplePhoto('apple_cake', 'Apple cake with ice cream'),
  SamplePhoto('dance', 'A dance performance'),
  SamplePhoto('snow_hike', 'Two hikers in the snow'),
  SamplePhoto('friends_beach', 'Friends on a beach at sunset'),
  SamplePhoto('pro_fans', 'Football fans in a stadium'),
  SamplePhoto('cat', 'A grey cat in the grass'),
  // Photos of the person the "@" demo finds (see [kMentionQuery]).
  SamplePhoto(
    'messi_2026',
    'Lionel Messi in a suit, 2026',
    focus: Alignment(0, -0.7),
  ),
  SamplePhoto(
    'messi_2012',
    'Lionel Messi looking back over his shoulder, 2012',
  ),
  SamplePhoto('messi_2023a', 'Lionel Messi pressing in a match, 2023'),
  SamplePhoto('messi_2025', 'Lionel Messi warming up, 2025'),
  SamplePhoto('messi_2023b', 'Lionel Messi chasing the ball, 2023'),
  SamplePhoto('messi_2023c', 'Lionel Messi on the pitch, 2023'),
  SamplePhoto('messi_2010', 'Lionel Messi at La Romareda, 2010'),
];

SamplePhoto samplePhoto(String id) =>
    kSamplePhotos.firstWhere((p) => p.id == id);

/// A search the demo plays. The order of the photos is worked out ahead of time (nothing is searched while the
/// tour is showing): the best match first, then the rest by how close they are.
class SampleQuery {
  const SampleQuery(this.text, this.best, {this.mention});

  final String text;

  /// Set when the text starts with an "@" pick: the demo then shows the people list, narrowed as the name is
  /// typed, and the pick turning into a name in the bar.
  final SampleMention? mention;

  /// The photos that match, best first (at least seven); the others follow in the order of the list of samples.
  final List<String> best;

  List<String> get order => [
    ...best,
    for (final p in kSamplePhotos)
      if (!best.contains(p.id)) p.id,
  ];
}

/// A named person the "@" demo picks out of the list.
class SampleMention {
  const SampleMention(this.name, this.face);

  final String name;

  /// The picture in the list.
  final String face;
}

/// The people in the "@" list, in order.
const List<SampleMention> kMentionPeople = [
  SampleMention('Leo', 'assets/tour/faces/leo.jpg'),
  SampleMention('Maya', 'assets/tour/faces/maya.jpg'),
  SampleMention('Messi', 'assets/tour/faces/messi.jpg'),
  SampleMention('Noor', 'assets/tour/faces/noor.jpg'),
  SampleMention('Sam', 'assets/tour/faces/sam.jpg'),
];

/// Which of [kSampleQueries] is the "@" one: the first search on the second page.
const int kMentionQuery = 8;

const List<SampleQuery> kSampleQueries = [
  SampleQuery('a dog on a beach', [
    'dog_beach',
    'dog_adult',
    'friends_beach',
    'puppy',
    'sunset',
    'kayak',
    'cat',
  ]),
  SampleQuery('a trip to India', [
    'tajmahal',
    'qutub',
    'houseboat',
    'v_cooking',
    'friends_walk',
    'sunset',
    'dance',
  ]),
  SampleQuery('a dog howling', [
    'v_husky',
    'dog_adult',
    'dog_beach',
    'puppy',
    'cat',
    'sunset',
    'friends_walk',
  ]),
  SampleQuery('cooking dinner', [
    'v_cooking',
    'apple_cake',
    'cake',
    'party',
    'friends_walk',
    'dance',
    'friends_beach',
  ]),
  SampleQuery('friends hiking', [
    'hike',
    'snow_hike',
    'friends_walk',
    'friends_beach',
    'running',
    'cycling',
    'kayak',
  ]),
  SampleQuery('snow in the city', [
    'v_tram',
    'snow_hike',
    'puppy',
    'cat',
    'sunset',
    'friends_walk',
    'kayak',
  ]),
  SampleQuery('birthday cake', [
    'cake',
    'party',
    'apple_cake',
    'pro_fans',
    'dance',
    'friends_walk',
    'cheering',
  ]),
  SampleQuery('surfing at sunset', [
    'v_surf',
    'kayak',
    'sunset',
    'friends_beach',
    'dog_beach',
    'snow_hike',
    'cycling',
  ]),
  // Index [kMentionQuery]. Only photos of that person, the ones that look most like a stadium first.
  SampleQuery(
    '@Messi in a stadium',
    [
      'messi_2010',
      'messi_2023a',
      'messi_2012',
      'messi_2023b',
      'messi_2025',
      'messi_2023c',
      'messi_2026',
    ],
    mention: SampleMention('Messi', 'assets/tour/faces/messi.jpg'),
  ),
];

// The tour's look: a light, airy page - soft white going to a pale mint, with a little mint and peach glowing
// behind - and the app's teal for everything that acts. Its colours are in TourPalette.

/// The soft shadow of the tour's white cards.
const List<BoxShadow> kTourSoftShadow = [
  BoxShadow(
    color: TourPalette.mint900A14,
    blurRadius: 18,
    offset: Offset(0, 6),
  ),
];
