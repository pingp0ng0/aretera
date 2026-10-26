import 'dart:math' as math;

import '../models/hike_record.dart';
import '../services/hike_analysis.dart';

/// Sample hikes for checking the records tab on a phone without going hiking.
/// Reachable only in builds made with `--dart-define=DEMO_RECORDS=true` (see Env.demoRecords).
/// Tracks are synthetic (out-and-back zigzags near real trailheads), not real routes.
const demoIdPrefix = 'demo-';

// (place, start lat, start lng, start alt m, distance km, climb m, pack kg, rating, days ago)
const _demoHikes = [
  ('북한산 백운대 (데모)', 37.6440, 126.9930, 120.0, 8.2, 720.0, 7.5, 3, 4),
  ('관악산 연주대 (데모)', 37.4370, 126.9640, 90.0, 7.0, 560.0, 6.2, 2, 21),
  ('설악산 대청봉 (데모)', 38.0950, 128.4400, 400.0, 14.5, 1300.0, 12.4, 5, 40),
  ('지리산 세석대피소 (데모)', 35.2850, 127.6500, 600.0, 11.0, 1050.0, 11.2, 4, 75),
  ('덕유산 향적봉 (데모)', 35.8800, 127.7300, 700.0, 9.5, 830.0, 9.0, 3, 110),
  ('굴업도 개머리언덕 (데모)', 37.1950, 125.9750, 10.0, 6.0, 180.0, 10.5, 1, 140),
];

List<(HikeRecord, List<TrackPoint>)> buildDemoHikes(DateTime now) {
  final out = <(HikeRecord, List<TrackPoint>)>[];
  for (final (i, h) in _demoHikes.indexed) {
    final (place, lat, lng, alt0, km, climb, kg, rating, daysAgo) = h;
    final start = DateTime(now.year, now.month, now.day - daysAgo, 7, 30);
    final track = _outAndBack(lat, lng, alt0, km * 1000, climb, kg, start, seed: i);
    final end = track.last.time;
    out.add((
      HikeRecord(
        id: '$demoIdPrefix$i',
        startedAt: start,
        endedAt: end,
        stats: analyzeTrack(track, start: start, end: end),
        place: place,
        packWeightGrams: (kg * 1000).round(),
        rating: rating,
        memo: '데모 기록입니다. 확인 후 삭제하세요.',
        pointCount: track.length,
      ),
      track,
    ));
  }
  return out;
}

/// Climbs [climb] over the first half, rests at the top, comes back down.
/// Heavier packs walk a little slower so the weight chart has a trend.
List<TrackPoint> _outAndBack(
  double lat0,
  double lng0,
  double alt0,
  double meters,
  double climb,
  double packKg,
  DateTime start, {
  required int seed,
}) {
  const mPerDegLat = 111195.0;
  final mPerDegLng = mPerDegLat * math.cos(lat0 * math.pi / 180);
  final rnd = math.Random(seed);
  final effortKmh = 4.6 - 0.08 * packKg;
  final half = meters / 2;
  final steps = (half / 15).round();
  final points = <TrackPoint>[];
  var t = start;
  var n = 0;

  TrackPoint at(double along, double alt, {double jitter = 0}) {
    final north = along * 0.8, east = along * 0.6 + 120 * math.sin(along / 400);
    return TrackPoint(
      lat: lat0 + (north + jitter * rnd.nextDouble()) / mPerDegLat,
      lng: lng0 + (east + jitter * rnd.nextDouble()) / mPerDegLng,
      alt: alt + 3 * math.sin(n++ * 1.7),
      accuracy: 6 + rnd.nextInt(10).toDouble(),
      time: t,
    );
  }

  void rest(double along, double alt, int minutes) {
    for (var m = 0; m < minutes; m++) {
      t = t.add(const Duration(minutes: 1));
      points.add(at(along, alt, jitter: 12));
    }
  }

  // Up: time from effort distance (flat + climb/100).
  final upSecPerStep = ((half / 1000 + climb / 100) / effortKmh * 3600) / steps;
  final restAt = {steps ~/ 3, 2 * steps ~/ 3};
  for (var s = 1; s <= steps; s++) {
    t = t.add(Duration(milliseconds: (upSecPerStep * 1000).round()));
    final along = half * s / steps;
    final alt = alt0 + climb * s / steps;
    points.add(at(along, alt));
    if (restAt.contains(s)) rest(along, alt, 5 + rnd.nextInt(4));
  }
  rest(half, alt0 + climb, 15);

  // Down: a bit faster than flat walking.
  final downSecPerStep = (half / 1000 / (effortKmh * 1.1) * 3600) / steps;
  for (var s = steps - 1; s >= 0; s--) {
    t = t.add(Duration(milliseconds: (downSecPerStep * 1000).round()));
    // Come back on a slightly offset line so the two directions are both visible.
    final along = half * s / steps;
    points.add(at(along, alt0 + climb * s / steps, jitter: 0)
        .shifted(eastM: 25, mPerDegLng: mPerDegLng));
  }
  return points;
}

extension on TrackPoint {
  TrackPoint shifted({required double eastM, required double mPerDegLng}) => TrackPoint(
        lat: lat,
        lng: lng + eastM / mPerDegLng,
        alt: alt,
        accuracy: accuracy,
        time: time,
      );
}
