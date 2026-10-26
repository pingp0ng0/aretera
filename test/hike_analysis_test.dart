import 'package:bivi/data/demo_records.dart';
import 'package:bivi/models/hike_record.dart';
import 'package:bivi/services/hike_analysis.dart';
import 'package:bivi/services/hike_insights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'hike_test_utils.dart';

void main() {
  group('analyzeTrack', () {
    // 2 km up (+400 m) in 40 min → 10 min rest → 2 km down (−400 m) in 30 min.
    final b = TrackBuilder()
      ..walk(2000, 40, 400)
      ..rest(10)
      ..walk(2000, 30, -400);
    final start = b.points.first.time;
    final end = b.points.last.time;
    final s = analyzeTrack(b.points, start: start, end: end);

    test('distance ignores rest jitter', () {
      expect(s.distanceM, closeTo(4000, 120));
    });

    test('climb and descent survive GPS altitude noise', () {
      expect(s.gainM, closeTo(400, 40));
      expect(s.lossM, closeTo(400, 40));
      expect(s.maxAltM, closeTo(600, 10));
      expect(s.minAltM, closeTo(200, 10));
    });

    test('one 10-minute rest, the rest is moving time', () {
      expect(s.restCount, 1);
      expect(s.restSec, closeTo(600, 90));
      expect(s.movingSec, closeTo(70 * 60, 120));
      expect(s.movingSec + s.restSec, end.difference(start).inSeconds);
    });

    test('uphill / downhill split and paces', () {
      expect(s.up.distanceM, closeTo(2000, 300));
      expect(s.down.distanceM, closeTo(2000, 300));
      expect(s.up.kmh, closeTo(3.0, 0.4));
      expect(s.down.kmh, closeTo(4.0, 0.5));
      expect(s.up.verticalM, closeTo(400, 60));
    });

    test('stats survive a JSON round trip', () {
      final back = HikeStats.fromJson(s.toJson());
      expect(back.distanceM, s.distanceM.roundToDouble());
      expect(back.restCount, s.restCount);
      expect(back.up.seconds, s.up.seconds);
    });
  });

  test('standing still for 30 minutes is one rest with no distance or climb', () {
    final b = TrackBuilder()..rest(30);
    final s = analyzeTrack(b.points, start: b.points.first.time, end: b.points.last.time);
    expect(s.distanceM, lessThan(30));
    expect(s.gainM, lessThan(10));
    expect(s.restCount, 1);
    expect(s.movingSec, 0);
  });

  test('a car ride (>15 km/h) is not counted as hiking', () {
    final b = TrackBuilder()
      ..walk(1000, 20, 0)
      ..jump(5000, 5)
      ..walk(1000, 20, 0);
    final s = analyzeTrack(b.points, start: b.points.first.time, end: b.points.last.time);
    expect(s.distanceM, closeTo(2000, 80));
    expect(s.movingSec, closeTo(40 * 60, 60));
  });

  group('recording gaps (PRD_step5 5-5)', () {
    // 1 km walk → app closed for 4 h while travelling 12 km → 1 km walk.
    final b = TrackBuilder()
      ..walk(1000, 20, 50)
      ..jump(12000, 240)
      ..walk(1000, 20, 50);
    final s = analyzeTrack(b.points, start: b.points.first.time, end: b.points.last.time);

    test('the gap is kept out of distance, moving time and rests', () {
      expect(s.distanceM, closeTo(2000, 80));
      expect(s.movingSec, closeTo(40 * 60, 60));
      expect(s.gapCount, 1);
      expect(s.gapSec, closeTo(240 * 60, 60));
      expect(s.gapDistanceM, closeTo(12000, 50));
      expect(s.restCount, 0);
      expect(s.restSec, lessThan(120));
      expect(isStatsEligible(fakeRecord(id: 'x', start: b.points.first.time, distanceM: s.distanceM)), isTrue);
    });

    test('the map line splits at the gap', () {
      final parts = splitAtGaps(b.points);
      expect(parts.length, 2);
      expect(parts.first.last.time.isBefore(parts.last.first.time), isTrue);
    });

    test('a long stop in one place stays a rest, not a gap', () {
      final stay = TrackBuilder()
        ..walk(500, 10, 0)
        ..rest(0); // no-op: keeps the builder API symmetric
      stay.time = stay.time.add(const Duration(hours: 2));
      stay.points.add(TrackPoint(
          lat: stay.points.last.lat, lng: stay.points.last.lng, alt: 200, accuracy: 8, time: stay.time));
      stay.walk(500, 10, 0);
      final r = analyzeTrack(stay.points, start: stay.points.first.time, end: stay.points.last.time);
      expect(r.gapCount, 0);
      expect(r.restCount, 1);
      expect(r.restSec, closeTo(2 * 3600, 120));
    });
  });

  test('inaccurate fixes are ignored', () {
    final b = TrackBuilder()..walk(1000, 20, 0);
    final noisy = [
      ...b.points,
      TrackPoint(lat: 37.7, lng: 127.0, alt: 900, accuracy: 120, time: b.points[10].time.add(const Duration(seconds: 1))),
    ];
    final s = analyzeTrack(noisy, start: b.points.first.time, end: b.points.last.time);
    expect(s.distanceM, closeTo(1000, 40));
    expect(s.maxAltM, lessThan(210));
  });

  test('empty track gives zeros, all time as rest', () {
    final t = DateTime(2026, 10, 1, 9);
    final s = analyzeTrack(const [], start: t, end: t.add(const Duration(minutes: 5)));
    expect(s.distanceM, 0);
    expect(s.movingSec, 0);
    expect(s.restSec, 300);
    expect(s.maxAltM, isNull);
  });

  test('elevation profile follows the climb and is capped in size', () {
    final b = TrackBuilder()..walk(6000, 120, 900);
    final profile = elevationProfile(b.points, maxPoints: 100);
    expect(profile.length, lessThanOrEqualTo(102));
    final s = analyzeTrack(b.points, start: b.points.first.time, end: b.points.last.time);
    expect(profile.map((p) => p.$2).reduce((a, c) => a > c ? a : c), s.maxAltM);
    expect(profile.first.$2, closeTo(200, 10));
    expect(profile.last.$2, closeTo(1100, 10));
    expect(profile.last.$1, closeTo(6000, 150));
  });

  test('highest point is the summit', () {
    final b = TrackBuilder()
      ..walk(1000, 20, 300)
      ..walk(1000, 20, -300);
    final top = highestPoint(b.points)!;
    expect(top.lat, closeTo(b.lat0 + 1000 / 111195, 0.001));
  });

  test('Android fixes keep their altitude even though hasAltitude comes back false', () {
    Position fix(double alt) => Position(
          latitude: 37.4,
          longitude: 127.1,
          timestamp: DateTime.utc(2026, 10, 23, 7, 3),
          accuracy: 18,
          altitude: alt,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
    expect(fix(123).hasAltitude, isFalse); // what the Android plugin gives us
    expect(TrackPoint.fromPosition(fix(123)).alt, 123);
    expect(TrackPoint.fromPosition(fix(0)).alt, isNull);
    expect(TrackPoint.fromPosition(fix(123)).time.isUtc, isFalse);
  });

  test('TrackPoint JSON is compact and round-trips', () {
    final p = TrackPoint(lat: 37.1234567, lng: 127.7654321, alt: 812.34, accuracy: 7.6, time: DateTime(2026, 10, 1, 9));
    final back = TrackPoint.fromJson(p.toJson());
    expect(back.lat, closeTo(37.123457, 1e-9));
    expect(back.alt, 812.3);
    expect(back.time, p.time);
  });

  test('demo hikes (DEMO_RECORDS builds) analyse to sensible numbers', () {
    final demos = buildDemoHikes(DateTime(2026, 10, 23));
    expect(demos.length, 6);
    for (final (r, track) in demos) {
      expect(r.id, startsWith(demoIdPrefix));
      expect(r.pointCount, track.length);
      expect(r.stats.restCount, 3, reason: r.place); // two on the way up + summit
      expect(r.stats.gainM, greaterThan(100));
    }
    final i = HikeInsights.from([for (final (r, _) in demos) r], now: DateTime(2026, 10, 23));
    expect(i.weightFit!.slope, lessThan(0)); // heavier demo packs walk slower
  });

  group('HikeInsights', () {
    final now = DateTime(2026, 10, 23);
    final records = [
      fakeRecord(id: 'a', start: DateTime(2026, 10, 3), packGrams: 6000, rating: 2, gainM: 400),
      fakeRecord(id: 'b', start: DateTime(2026, 9, 12), packGrams: 9000, rating: 4, gainM: 900, movingMin: 240),
      fakeRecord(id: 'c', start: DateTime(2026, 9, 1), packGrams: 12000, rating: 4, gainM: 1100, movingMin: 300),
      // Too short for pace statistics, still counted in totals.
      fakeRecord(id: 'd', start: DateTime(2026, 8, 1), distanceM: 200, gainM: 0, movingMin: 5, restMin: 0),
    ];
    final i = HikeInsights.from(records, now: now);

    test('totals and months', () {
      expect(i.count, 4);
      expect(i.eligibleCount, 3);
      expect(i.months.length, 12);
      expect(i.months.last.month, DateTime(2026, 10));
      expect(i.months.last.count, 1);
      expect(i.months[10].count, 2); // September
      expect(i.months[10].gainM, 2000);
    });

    test('pace model predicts from effort distance', () {
      final pace = i.pace!;
      expect(pace.basedOn, 3);
      // moving (180+240+300 min) / effort km (12 + 17 + 19)
      expect(pace.secPerEffortKm, closeTo(720 * 60 / 48, 1e-6));
      // 15 min per effort-km × (10 km + 500 m / 100)
      expect(pace.movingFor(10000, 500).inMinutes, 225);
      expect(pace.restRatio, closeTo(90 / 720, 1e-9));
    });

    test('heavier pack → slower in this data', () {
      expect(i.weightPoints.length, 3);
      expect(i.weightFit, isNotNull);
      expect(i.weightFit!.slope, lessThan(0));
    });

    test('average gain per difficulty star', () {
      expect(i.gainByRating[4]!.$1, 1000);
      expect(i.gainByRating[4]!.$2, 2);
      expect(i.gainByRating[2]!.$1, 400);
    });

    test('no fit with fewer than 3 points or no weight spread', () {
      expect(LinearFit.of([(1, 1), (2, 2)]), isNull);
      expect(LinearFit.of([(5, 1), (5, 2), (5, 3)], minXRange: 1), isNull);
      expect(LinearFit.of([(0, 1), (1, 3), (2, 5)])!.slope, closeTo(2, 1e-9));
    });
  });
}
