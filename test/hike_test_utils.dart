import 'dart:math' as math;

import 'package:bivi/models/hike_record.dart';

/// Builds synthetic GPS tracks for tests: walking north from a fixed origin.
class TrackBuilder {
  TrackBuilder({DateTime? start, this.lat0 = 37.65, this.lng0 = 126.98})
      : time = start ?? DateTime(2026, 10, 3, 8);

  final double lat0;
  final double lng0;
  DateTime time;
  double north = 0;
  double alt = 200;
  final points = <TrackPoint>[];
  int _n = 0;

  static const _mPerDegLat = 111195.0;

  TrackPoint _point({double east = 0, double altNoise = 0, double accuracy = 8}) => TrackPoint(
        lat: lat0 + north / _mPerDegLat,
        lng: lng0 + east / (_mPerDegLat * math.cos(lat0 * math.pi / 180)),
        alt: alt + altNoise,
        accuracy: accuracy,
        time: time,
      );

  /// Walks [meters] north in [minutes], changing altitude by [climb], one fix every ~15 m.
  /// Altitude gets a small deterministic wobble (±3 m) like real GPS.
  void walk(double meters, double minutes, double climb) {
    final steps = (meters / 15).round();
    for (var i = 0; i < steps; i++) {
      north += meters / steps;
      alt += climb / steps;
      time = time.add(Duration(milliseconds: (minutes * 60000 / steps).round()));
      points.add(_point(altNoise: 3 * math.sin(_n++ * 1.7)));
    }
  }

  /// Stays put for [minutes] with one fix a minute, jittering up to 10 m and ±8 m in altitude.
  void rest(double minutes) {
    for (var i = 0; i < minutes; i++) {
      time = time.add(const Duration(minutes: 1));
      points.add(_point(east: 10 * math.sin(_n * 2.3), altNoise: 8 * math.sin(_n * 1.3)));
      _n++;
    }
  }

  /// Jumps [meters] north in [minutes] (e.g. a car ride) as a single fix.
  void jump(double meters, double minutes) {
    north += meters;
    time = time.add(Duration(seconds: (minutes * 60).round()));
    points.add(_point());
  }
}

HikeRecord fakeRecord({
  required String id,
  required DateTime start,
  double distanceM = 8000,
  double gainM = 600,
  int movingMin = 180,
  int restMin = 30,
  int restCount = 3,
  int? packGrams,
  int? rating,
  String place = '',
  String memo = '',
}) {
  final total = Duration(minutes: movingMin + restMin);
  return HikeRecord(
    id: id,
    startedAt: start,
    endedAt: start.add(total),
    place: place,
    memo: memo,
    packWeightGrams: packGrams,
    rating: rating,
    stats: HikeStats(
      distanceM: distanceM,
      gainM: gainM,
      lossM: gainM,
      maxAltM: 200 + gainM,
      minAltM: 200,
      movingSec: movingMin * 60,
      restSec: restMin * 60,
      restCount: restCount,
      up: SlopeTotals(distanceM: distanceM / 2, seconds: movingMin * 36, verticalM: gainM),
      down: SlopeTotals(distanceM: distanceM / 2, seconds: movingMin * 24, verticalM: gainM),
    ),
  );
}
