import 'dart:math' as math;

import '../models/gpx_route.dart' show GpxPoint, haversine;
import '../models/hike_record.dart';

// Tuning for phone GPS noise (PRD_step5 "계산 규칙").
/// Fixes worse than this are left out of every calculation.
const maxAccuracyM = 50.0;

/// Staying within this radius for [restMinDuration] counts as a rest.
const restRadiusM = 30.0;
const restMinDuration = Duration(minutes: 3);

/// Faster than this between two fixes = vehicle or GPS jump; excluded.
const maxHikingSpeedMs = 15 / 3.6;

/// No fix for this long while the position changed = recording was interrupted (app closed, phone off).
/// Kept out of distance and moving time (PRD_step5 5-5). Shorter holes (GPS lost under trees) still
/// count as walking; staying in place is already a rest.
const maxGap = Duration(minutes: 10);

/// True when the stretch between two consecutive fixes is a recording gap (see [maxGap]).
bool isRecordingGap(TrackPoint a, TrackPoint b) =>
    b.time.difference(a.time) >= maxGap && _dist(a, b) > restRadiusM;

/// GPS altitude is smoothed with a centred moving average of this many fixes,
/// then only changes of at least [altThresholdM] count as climbing/descending.
const altSmoothingWindow = 5;
const altThresholdM = 5.0;

/// Moving parts are grouped into chunks of about this length and classed by grade.
const slopeChunkM = 150.0;
const slopeGrade = 0.05;

double _dist(TrackPoint a, TrackPoint b) => haversine(GpxPoint(a.lat, a.lng), GpxPoint(b.lat, b.lng));

/// Accurate fixes sorted by time, at most one per timestamp.
List<TrackPoint> cleanTrack(List<TrackPoint> raw) {
  final sorted = raw.where((p) => p.accuracy <= maxAccuracyM).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  final out = <TrackPoint>[];
  for (final p in sorted) {
    if (out.isNotEmpty && !p.time.isAfter(out.last.time)) continue;
    out.add(p);
  }
  return out;
}

/// Rest intervals as (first, last) point indices: every point stays within
/// [restRadiusM] of the first one for at least [restMinDuration].
List<(int, int)> findRests(List<TrackPoint> pts) {
  final rests = <(int, int)>[];
  var i = 0;
  while (i < pts.length - 1) {
    var j = i + 1;
    while (j < pts.length && _dist(pts[i], pts[j]) <= restRadiusM) {
      j++;
    }
    final last = j - 1;
    if (last > i && pts[last].time.difference(pts[i].time) >= restMinDuration) {
      // A stay that continues right where the previous one ended is the same rest.
      if (rests.isNotEmpty && rests.last.$2 == i) {
        rests[rests.length - 1] = (rests.last.$1, last);
      } else {
        rests.add((i, last));
      }
      i = last;
    } else {
      i++;
    }
  }
  return rests;
}

enum _Seg { moving, rest, invalid }

/// A fix on the moving path, with cumulative moving distance/time up to it.
class _Node {
  _Node(this.point, this.distanceM, this.movingSec);

  final TrackPoint point;
  final double distanceM;
  final int movingSec;
  double smoothAlt = 0;
}

/// Shared pipeline behind [analyzeTrack], [elevationProfile] and [highestPoint].
class _Analysis {
  _Analysis(List<TrackPoint> raw) : points = cleanTrack(raw) {
    final pts = points;
    if (pts.isEmpty) return;
    rests = findRests(pts);

    final seg = List.filled(math.max(0, pts.length - 1), _Seg.moving);
    for (final (a, b) in rests) {
      for (var k = a; k < b; k++) {
        seg[k] = _Seg.rest;
      }
    }

    var cumD = 0.0;
    var cumSec = 0;
    final runs = <List<_Node>>[
      [_Node(pts.first, 0, 0)],
    ];
    for (var k = 0; k < seg.length; k++) {
      final a = pts[k], b = pts[k + 1];
      final dt = b.time.difference(a.time).inMilliseconds / 1000;
      if (seg[k] == _Seg.rest) continue; // jitter while resting adds nothing
      final d = _dist(a, b);
      if (dt >= maxGap.inSeconds) {
        // Not a rest (that was handled above), so the phone moved while nothing was recorded.
        gapSec += dt.round();
        gapCount++;
        gapDistanceM += d;
        runs.add([_Node(b, cumD, cumSec)]);
        continue;
      }
      if (d / dt > maxHikingSpeedMs) {
        seg[k] = _Seg.invalid;
        invalidSec += dt.round();
        runs.add([_Node(b, cumD, cumSec)]);
        continue;
      }
      cumD += d;
      cumSec += dt.round();
      runs.last.add(_Node(b, cumD, cumSec));
    }
    distanceM = cumD;
    movingSec = cumSec;

    for (final run in runs) {
      final withAlt = run.where((n) => n.point.alt != null).toList();
      if (withAlt.isEmpty) {
        // No altitude at all: the whole run counts as flat.
        flat += SlopeTotals(
          distanceM: run.last.distanceM - run.first.distanceM,
          seconds: run.last.movingSec - run.first.movingSec,
        );
        continue;
      }
      _smooth(withAlt);
      altNodes.addAll(withAlt);
      _gainLoss(withAlt);
      _slopes(withAlt);
    }
  }

  final List<TrackPoint> points;
  List<(int, int)> rests = const [];
  double distanceM = 0;
  int movingSec = 0;
  int gapSec = 0;
  int gapCount = 0;
  double gapDistanceM = 0;
  int invalidSec = 0;
  double gainM = 0;
  double lossM = 0;
  SlopeTotals up = SlopeTotals.zero;
  SlopeTotals down = SlopeTotals.zero;
  SlopeTotals flat = SlopeTotals.zero;

  /// Nodes with a smoothed altitude, in track order.
  final altNodes = <_Node>[];

  static void _smooth(List<_Node> nodes) {
    const half = altSmoothingWindow ~/ 2;
    for (var i = 0; i < nodes.length; i++) {
      final from = math.max(0, i - half), to = math.min(nodes.length - 1, i + half);
      var sum = 0.0;
      for (var k = from; k <= to; k++) {
        sum += nodes[k].point.alt!;
      }
      nodes[i].smoothAlt = sum / (to - from + 1);
    }
  }

  void _gainLoss(List<_Node> nodes) {
    var ref = nodes.first.smoothAlt;
    for (final n in nodes) {
      final diff = n.smoothAlt - ref;
      if (diff >= altThresholdM) {
        gainM += diff;
        ref = n.smoothAlt;
      } else if (diff <= -altThresholdM) {
        lossM -= diff;
        ref = n.smoothAlt;
      }
    }
  }

  void _slopes(List<_Node> nodes) {
    var a = 0;
    for (var b = 1; b < nodes.length; b++) {
      final dd = nodes[b].distanceM - nodes[a].distanceM;
      if (dd < slopeChunkM && b < nodes.length - 1) continue;
      final dt = nodes[b].movingSec - nodes[a].movingSec;
      final dv = nodes[b].smoothAlt - nodes[a].smoothAlt;
      final isUp = dd < 10 ? dv >= altThresholdM : dv / dd > slopeGrade;
      final isDown = dd < 10 ? dv <= -altThresholdM : dv / dd < -slopeGrade;
      if (isUp) {
        up += SlopeTotals(distanceM: dd, seconds: dt, verticalM: dv);
      } else if (isDown) {
        down += SlopeTotals(distanceM: dd, seconds: dt, verticalM: -dv);
      } else {
        flat += SlopeTotals(distanceM: dd, seconds: dt);
      }
      a = b;
    }
  }
}

/// Distance, climbing, moving/rest split and slope paces for one hike.
/// [start]/[end] are the hike's wall-clock bounds (rest = total − moving − excluded − gaps).
HikeStats analyzeTrack(List<TrackPoint> raw, {required DateTime start, required DateTime end}) {
  final a = _Analysis(raw);
  final total = math.max(0, end.difference(start).inSeconds);
  final alts = [for (final n in a.altNodes) n.smoothAlt];
  return HikeStats(
    distanceM: a.distanceM,
    gainM: a.gainM,
    lossM: a.lossM,
    maxAltM: alts.isEmpty ? null : alts.reduce(math.max),
    minAltM: alts.isEmpty ? null : alts.reduce(math.min),
    movingSec: math.min(a.movingSec, total),
    restSec: math.max(0, total - a.movingSec - a.invalidSec - a.gapSec),
    restCount: a.rests.length,
    up: a.up,
    down: a.down,
    flat: a.flat,
    gapSec: a.gapSec,
    gapCount: a.gapCount,
    gapDistanceM: a.gapDistanceM,
  );
}

/// The track split where recording stopped, so maps can draw those stretches differently.
List<List<TrackPoint>> splitAtGaps(List<TrackPoint> points) {
  if (points.isEmpty) return const [];
  final parts = <List<TrackPoint>>[
    [points.first],
  ];
  for (var i = 1; i < points.length; i++) {
    if (isRecordingGap(points[i - 1], points[i])) parts.add([]);
    parts.last.add(points[i]);
  }
  return parts;
}

/// (distance m, smoothed altitude m) along the moving path, at most [maxPoints] entries.
List<(double, double)> elevationProfile(List<TrackPoint> raw, {int maxPoints = 300}) {
  final nodes = _Analysis(raw).altNodes;
  if (nodes.length <= maxPoints) return [for (final n in nodes) (n.distanceM, n.smoothAlt)];
  // Even sampling, plus the high point so the chart label matches the record's max altitude.
  final step = nodes.length / maxPoints;
  var top = 0;
  for (var i = 1; i < nodes.length; i++) {
    if (nodes[i].smoothAlt > nodes[top].smoothAlt) top = i;
  }
  final picks = {for (var i = 0; i < maxPoints; i++) (i * step).floor(), top, nodes.length - 1}.toList()..sort();
  return [for (final i in picks) (nodes[i].distanceM, nodes[i].smoothAlt)];
}

/// The fix with the highest smoothed altitude (or the middle fix without altitude data).
TrackPoint? highestPoint(List<TrackPoint> raw) {
  final a = _Analysis(raw);
  if (a.altNodes.isNotEmpty) {
    return a.altNodes.reduce((x, y) => y.smoothAlt > x.smoothAlt ? y : x).point;
  }
  return a.points.isEmpty ? null : a.points[a.points.length ~/ 2];
}

/// Fixes to draw on a map (accurate ones; all of them if too few are accurate).
List<TrackPoint> drawableTrack(List<TrackPoint> raw) {
  final clean = cleanTrack(raw);
  if (clean.length >= 2) return clean;
  return [...raw]..sort((a, b) => a.time.compareTo(b.time));
}
