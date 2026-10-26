import 'dart:math' as math;

import '../models/hike_record.dart';

/// Records shorter than this are kept in the list but left out of pace statistics.
const minStatsDistanceM = 500.0;
const minStatsMovingSec = 600;

/// The pace model uses this many most recent eligible records.
const paceModelRecords = 10;

bool isStatsEligible(HikeRecord r) =>
    r.stats.distanceM >= minStatsDistanceM && r.stats.movingSec >= minStatsMovingSec;

/// Least-squares line y = slope · x + intercept.
class LinearFit {
  const LinearFit(this.slope, this.intercept, this.n);

  final double slope;
  final double intercept;
  final int n;

  double at(double x) => slope * x + intercept;

  /// null with fewer than [minPoints] points or when x barely varies.
  static LinearFit? of(List<(double, double)> pts, {int minPoints = 3, double minXRange = 0}) {
    if (pts.length < minPoints) return null;
    final xs = [for (final p in pts) p.$1];
    if (xs.reduce(math.max) - xs.reduce(math.min) < math.max(minXRange, 1e-9)) return null;
    final n = pts.length;
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = pts.map((p) => p.$2).reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0;
    for (final (x, y) in pts) {
      sxy += (x - mx) * (y - my);
      sxx += (x - mx) * (x - mx);
    }
    final slope = sxy / sxx;
    return LinearFit(slope, my - slope * mx, n);
  }
}

/// Personal time estimate: moving time per effort-km and the usual rest share.
class PaceModel {
  const PaceModel({required this.secPerEffortKm, required this.restRatio, required this.basedOn});

  final double secPerEffortKm;

  /// Rest time ÷ moving time.
  final double restRatio;
  final int basedOn;

  Duration movingFor(double distanceM, double gainM) =>
      Duration(seconds: (secPerEffortKm * (distanceM / 1000 + gainM / 100)).round());

  Duration restFor(Duration moving) => Duration(seconds: (moving.inSeconds * restRatio).round());
}

class MonthTotal {
  const MonthTotal(this.month, {this.count = 0, this.distanceM = 0, this.gainM = 0});

  /// First day of the month.
  final DateTime month;
  final int count;
  final double distanceM;
  final double gainM;
}

/// A record plotted on the pack-weight chart: kg vs effort speed (effort-km per moving hour).
class WeightSpeedPoint {
  const WeightSpeedPoint(this.kg, this.effortKmh);

  final double kg;
  final double effortKmh;
}

/// Everything the analysis tab shows, computed on the device (PRD_step5 5-3).
class HikeInsights {
  HikeInsights._({
    required this.count,
    required this.distanceM,
    required this.gainM,
    required this.duration,
    required this.months,
    required this.eligibleCount,
    required this.up,
    required this.down,
    required this.flat,
    required this.movingRatio,
    required this.restsPerHike,
    required this.avgRest,
    required this.weightPoints,
    required this.weightFit,
    required this.ratingPoints,
    required this.gainByRating,
    required this.pace,
  });

  factory HikeInsights.from(List<HikeRecord> records, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final eligible = records.where(isStatsEligible).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    // Last 12 calendar months, oldest first.
    final months = [
      for (var i = 11; i >= 0; i--) DateTime(today.year, today.month - i),
    ];
    final monthTotals = [
      for (final m in months)
        () {
          final inMonth =
              records.where((r) => r.startedAt.year == m.year && r.startedAt.month == m.month);
          return MonthTotal(
            m,
            count: inMonth.length,
            distanceM: inMonth.fold(0.0, (s, r) => s + r.stats.distanceM),
            gainM: inMonth.fold(0.0, (s, r) => s + r.stats.gainM),
          );
        }(),
    ];

    var up = SlopeTotals.zero, down = SlopeTotals.zero, flat = SlopeTotals.zero;
    var moving = 0, rest = 0, restCount = 0;
    for (final r in eligible) {
      up += r.stats.up;
      down += r.stats.down;
      flat += r.stats.flat;
      moving += r.stats.movingSec;
      rest += r.stats.restSec;
      restCount += r.stats.restCount;
    }

    final weightPoints = [
      for (final r in eligible)
        if (r.packWeightGrams != null && r.packWeightGrams! > 0 && r.stats.effortKm > 0)
          WeightSpeedPoint(r.packWeightGrams! / 1000, r.stats.effortKm / (r.stats.movingSec / 3600)),
    ];

    final rated = [
      for (final r in records)
        if (r.rating != null && r.stats.distanceM >= minStatsDistanceM) (r.stats.gainM, r.rating!),
    ];
    final gainByRating = <int, (double, int)>{};
    for (var star = 1; star <= 5; star++) {
      final gains = [for (final (g, s) in rated) if (s == star) g];
      if (gains.isNotEmpty) {
        gainByRating[star] = (gains.reduce((a, b) => a + b) / gains.length, gains.length);
      }
    }

    PaceModel? pace;
    final recent = eligible.take(paceModelRecords).toList();
    final recentEffort = recent.fold(0.0, (s, r) => s + r.stats.effortKm);
    final recentMoving = recent.fold(0, (s, r) => s + r.stats.movingSec);
    if (recent.isNotEmpty && recentEffort > 0) {
      pace = PaceModel(
        secPerEffortKm: recentMoving / recentEffort,
        restRatio: recentMoving == 0 ? 0 : recent.fold(0, (s, r) => s + r.stats.restSec) / recentMoving,
        basedOn: recent.length,
      );
    }

    return HikeInsights._(
      count: records.length,
      distanceM: records.fold(0.0, (s, r) => s + r.stats.distanceM),
      gainM: records.fold(0.0, (s, r) => s + r.stats.gainM),
      duration: records.fold(Duration.zero, (s, r) => s + r.duration),
      months: monthTotals,
      eligibleCount: eligible.length,
      up: up,
      down: down,
      flat: flat,
      movingRatio: moving + rest == 0 ? null : moving / (moving + rest),
      restsPerHike: eligible.isEmpty ? null : restCount / eligible.length,
      avgRest: restCount == 0 ? null : Duration(seconds: rest ~/ restCount),
      weightPoints: weightPoints,
      weightFit: LinearFit.of([for (final p in weightPoints) (p.kg, p.effortKmh)], minXRange: 1),
      ratingPoints: rated,
      gainByRating: gainByRating,
      pace: pace,
    );
  }

  final int count;
  final double distanceM;
  final double gainM;
  final Duration duration;
  final List<MonthTotal> months;

  /// Records long enough for pace statistics.
  final int eligibleCount;
  final SlopeTotals up;
  final SlopeTotals down;
  final SlopeTotals flat;

  /// Moving ÷ (moving + rest), over eligible records.
  final double? movingRatio;
  final double? restsPerHike;
  final Duration? avgRest;
  final List<WeightSpeedPoint> weightPoints;

  /// Effort speed vs pack kg; null until 3+ records with at least 1 kg of spread.
  final LinearFit? weightFit;

  /// How much effort speed changes per extra kg, in % of the average (negative = slower).
  double? get packPctPerKg {
    final fit = weightFit;
    if (fit == null) return null;
    final mean = weightPoints.map((p) => p.effortKmh).reduce((a, b) => a + b) / weightPoints.length;
    return fit.slope / mean * 100;
  }

  /// (gain m, rating 1–5)
  final List<(double, int)> ratingPoints;

  /// rating → (average gain m, number of records)
  final Map<int, (double, int)> gainByRating;
  final PaceModel? pace;
}
