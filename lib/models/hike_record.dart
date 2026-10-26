import 'package:geolocator/geolocator.dart';

/// One GPS fix recorded during a hike (PRD_step5).
class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.time,
    this.alt,
  });

  final double lat;
  final double lng;

  /// Metres. null when the fix had no altitude.
  final double? alt;

  /// Horizontal accuracy (m).
  final double accuracy;
  final DateTime time;

  factory TrackPoint.fromPosition(Position p) => TrackPoint(
        lat: p.latitude,
        lng: p.longitude,
        // geolocator_android 4.6.2 drops `hasAltitude` (always false on Android), and a missing
        // altitude arrives as exactly 0.0 — so a non-zero value means it was measured.
        alt: p.hasAltitude || p.altitude != 0 ? p.altitude : null,
        accuracy: p.accuracy,
        time: p.timestamp.toLocal(), // fixes arrive in UTC
      );

  /// Compact form: [lat, lng, alt, accuracy, epochMs].
  List<num?> toJson() => [
        _round(lat, 1e6),
        _round(lng, 1e6),
        alt == null ? null : _round(alt!, 10),
        accuracy.round(),
        time.millisecondsSinceEpoch,
      ];

  factory TrackPoint.fromJson(List<dynamic> j) => TrackPoint(
        lat: (j[0] as num).toDouble(),
        lng: (j[1] as num).toDouble(),
        alt: (j[2] as num?)?.toDouble(),
        accuracy: (j[3] as num).toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch((j[4] as num).toInt()),
      );

  static double _round(double v, double scale) => (v * scale).roundToDouble() / scale;
}

/// Distance / time / vertical totals for one slope class (uphill, downhill or flat).
class SlopeTotals {
  const SlopeTotals({this.distanceM = 0, this.seconds = 0, this.verticalM = 0});

  final double distanceM;
  final int seconds;

  /// Metres climbed (uphill) or descended (downhill), always positive.
  final double verticalM;

  static const zero = SlopeTotals();

  SlopeTotals operator +(SlopeTotals o) => SlopeTotals(
        distanceM: distanceM + o.distanceM,
        seconds: seconds + o.seconds,
        verticalM: verticalM + o.verticalM,
      );

  /// Horizontal speed (km/h), null without enough data.
  double? get kmh => seconds < 60 || distanceM < 50 ? null : distanceM / 1000 / (seconds / 3600);

  /// Vertical speed (m/h), null without enough data.
  double? get verticalPerHour => seconds < 60 ? null : verticalM / (seconds / 3600);

  Map<String, dynamic> toJson() => {
        'distance_m': distanceM.round(),
        'seconds': seconds,
        'vertical_m': verticalM.round(),
      };

  factory SlopeTotals.fromJson(Map<String, dynamic>? j) => j == null
      ? zero
      : SlopeTotals(
          distanceM: (j['distance_m'] as num? ?? 0).toDouble(),
          seconds: (j['seconds'] as num? ?? 0).toInt(),
          verticalM: (j['vertical_m'] as num? ?? 0).toDouble(),
        );
}

/// Numbers derived from a track by `analyzeTrack` (lib/services/hike_analysis.dart).
class HikeStats {
  const HikeStats({
    this.distanceM = 0,
    this.gainM = 0,
    this.lossM = 0,
    this.maxAltM,
    this.minAltM,
    this.movingSec = 0,
    this.restSec = 0,
    this.restCount = 0,
    this.up = SlopeTotals.zero,
    this.down = SlopeTotals.zero,
    this.flat = SlopeTotals.zero,
    this.gapSec = 0,
    this.gapCount = 0,
    this.gapDistanceM = 0,
  });

  final double distanceM;
  final double gainM;
  final double lossM;
  final double? maxAltM;
  final double? minAltM;
  final int movingSec;
  final int restSec;
  final int restCount;
  final SlopeTotals up;
  final SlopeTotals down;
  final SlopeTotals flat;

  /// Recording interruptions (app closed, phone off): no fix for 10+ min while the position changed.
  /// Their time and straight-line distance are kept out of distance, moving time and paces (PRD_step5 5-5).
  final int gapSec;
  final int gapCount;
  final double gapDistanceM;

  Duration get moving => Duration(seconds: movingSec);
  Duration get rest => Duration(seconds: restSec);
  Duration get gap => Duration(seconds: gapSec);

  /// "Effort distance" in km: every 100 m of climbing counts as 1 flat km (ITRA km-effort).
  double get effortKm => distanceM / 1000 + gainM / 100;

  Map<String, dynamic> toJson() => {
        'distance_m': distanceM.round(),
        'gain_m': gainM.round(),
        'loss_m': lossM.round(),
        'max_alt_m': maxAltM?.round(),
        'min_alt_m': minAltM?.round(),
        'moving_sec': movingSec,
        'rest_sec': restSec,
        'rest_count': restCount,
        'up': up.toJson(),
        'down': down.toJson(),
        'flat': flat.toJson(),
        'gap_sec': gapSec,
        'gap_count': gapCount,
        'gap_distance_m': gapDistanceM.round(),
      };

  factory HikeStats.fromJson(Map<String, dynamic> j) => HikeStats(
        distanceM: (j['distance_m'] as num? ?? 0).toDouble(),
        gainM: (j['gain_m'] as num? ?? 0).toDouble(),
        lossM: (j['loss_m'] as num? ?? 0).toDouble(),
        maxAltM: (j['max_alt_m'] as num?)?.toDouble(),
        minAltM: (j['min_alt_m'] as num?)?.toDouble(),
        movingSec: (j['moving_sec'] as num? ?? 0).toInt(),
        restSec: (j['rest_sec'] as num? ?? 0).toInt(),
        restCount: (j['rest_count'] as num? ?? 0).toInt(),
        up: SlopeTotals.fromJson(j['up'] as Map<String, dynamic>?),
        down: SlopeTotals.fromJson(j['down'] as Map<String, dynamic>?),
        flat: SlopeTotals.fromJson(j['flat'] as Map<String, dynamic>?),
        gapSec: (j['gap_sec'] as num? ?? 0).toInt(),
        gapCount: (j['gap_count'] as num? ?? 0).toInt(),
        gapDistanceM: (j['gap_distance_m'] as num? ?? 0).toDouble(),
      );
}

/// The GPX route the user followed during the hike (plan, not the actual track).
class PlannedRoute {
  const PlannedRoute({required this.name, required this.distanceM, required this.gainM});

  final String name;
  final double distanceM;
  final double gainM;

  Map<String, dynamic> toJson() => {'name': name, 'distance_m': distanceM.round(), 'gain_m': gainM.round()};

  factory PlannedRoute.fromJson(Map<String, dynamic> j) => PlannedRoute(
        name: j['name'] as String,
        distanceM: (j['distance_m'] as num).toDouble(),
        gainM: (j['gain_m'] as num).toDouble(),
      );
}

/// One saved hike, without its track (the track lives in its own file).
/// Bump when `analyzeTrack` changes so saved records get recomputed.
/// 2: recording gaps are kept out of distance / moving time (PRD_step5 5-5).
const hikeStatsVersion = 2;

class HikeRecord {
  const HikeRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.stats,
    this.place = '',
    this.packWeightGrams,
    this.rating,
    this.memo = '',
    this.route,
    this.pointCount = 0,
    this.statsVersion = hikeStatsVersion,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final HikeStats stats;
  final String place;

  /// Packed weight on the pack screen when the hike started.
  final int? packWeightGrams;

  /// Perceived difficulty, 1 (easy) – 5 (very hard).
  final int? rating;
  final String memo;
  final PlannedRoute? route;
  final int pointCount;

  /// Version of `analyzeTrack` that produced [stats]; older records are recomputed from their track.
  final int statsVersion;

  HikeRecord withStats(HikeStats newStats) => HikeRecord(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt,
        stats: newStats,
        place: place,
        packWeightGrams: packWeightGrams,
        rating: rating,
        memo: memo,
        route: route,
        pointCount: pointCount,
      );

  Duration get duration => endedAt.difference(startedAt);

  String get displayPlace => place.trim().isEmpty ? '이름 없는 산행' : place.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'place': place,
        'pack_weight_g': packWeightGrams,
        'rating': rating,
        'memo': memo,
        'route': route?.toJson(),
        'point_count': pointCount,
        'stats_version': statsVersion,
        'stats': stats.toJson(),
      };

  factory HikeRecord.fromJson(Map<String, dynamic> j) => HikeRecord(
        id: j['id'] as String,
        startedAt: DateTime.parse(j['started_at'] as String),
        endedAt: DateTime.parse(j['ended_at'] as String),
        place: j['place'] as String? ?? '',
        packWeightGrams: (j['pack_weight_g'] as num?)?.toInt(),
        rating: (j['rating'] as num?)?.toInt(),
        memo: j['memo'] as String? ?? '',
        route: j['route'] == null ? null : PlannedRoute.fromJson(j['route'] as Map<String, dynamic>),
        pointCount: (j['point_count'] as num? ?? 0).toInt(),
        // Records saved before versioning were made by version 1.
        statsVersion: (j['stats_version'] as num? ?? 1).toInt(),
        stats: HikeStats.fromJson(j['stats'] as Map<String, dynamic>),
      );
}
