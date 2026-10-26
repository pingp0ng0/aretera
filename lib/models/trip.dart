import 'package:geolocator/geolocator.dart';

import 'hike_record.dart' show PlannedRoute;

/// 기기에 캐싱되는 마지막 GPS 좌표. 오프라인 SOS 카드의 유일한 데이터 소스.
class CachedPosition {
  const CachedPosition({
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.accuracy,
    required this.timestamp,
  });

  final double lat;
  final double lng;
  final double altitude;
  final double accuracy;
  final DateTime timestamp;

  factory CachedPosition.fromPosition(Position p) => CachedPosition(
        lat: p.latitude,
        lng: p.longitude,
        altitude: p.altitude,
        accuracy: p.accuracy,
        // Fix times arrive in UTC; the SOS card and GPS card print them, so keep local time.
        timestamp: p.timestamp.toLocal(),
      );

  factory CachedPosition.fromJson(Map<String, dynamic> j) => CachedPosition(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        altitude: (j['altitude'] as num).toDouble(),
        accuracy: (j['accuracy'] as num).toDouble(),
        timestamp: DateTime.parse(j['timestamp'] as String).toLocal(),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'altitude': altitude,
        'accuracy': accuracy,
        'timestamp': timestamp.toIso8601String(),
      };
}

class SafeTripState {
  const SafeTripState({
    this.active = false,
    this.startedAt,
    this.targetTime,
    this.lastPosition,
    this.baseTempC,
    this.baseAltitudeM,
    this.windMs,
    this.weatherObservedAt,
    this.cachedTiles = 0,
    this.packWeightGrams,
    this.followedRoute,
    this.busy = false,
    this.message,
  });

  final bool active;
  final DateTime? startedAt;

  /// 예정 하산 시간 (target_time)
  final DateTime? targetTime;
  final CachedPosition? lastPosition;

  /// 기상청 격자 기온 — 산행 시작 지점(들머리) 고도 기준으로 간주
  final double? baseTempC;
  final double? baseAltitudeM;
  final double? windMs;
  final DateTime? weatherObservedAt;
  final int cachedTiles;

  /// Packed weight when the hike started (kept for the hike record, PRD_step5).
  final int? packWeightGrams;

  /// GPX route opened in "지도에서 따라가기" during this hike.
  final PlannedRoute? followedRoute;
  final bool busy;

  /// 일회성 안내 메시지 (다음 상태 변경 시 자동으로 지워짐)
  final String? message;

  SafeTripState copyWith({
    bool? active,
    DateTime? startedAt,
    DateTime? targetTime,
    CachedPosition? lastPosition,
    double? baseTempC,
    double? baseAltitudeM,
    double? windMs,
    DateTime? weatherObservedAt,
    int? cachedTiles,
    int? packWeightGrams,
    PlannedRoute? followedRoute,
    bool? busy,
    String? message,
  }) =>
      SafeTripState(
        active: active ?? this.active,
        startedAt: startedAt ?? this.startedAt,
        targetTime: targetTime ?? this.targetTime,
        lastPosition: lastPosition ?? this.lastPosition,
        baseTempC: baseTempC ?? this.baseTempC,
        baseAltitudeM: baseAltitudeM ?? this.baseAltitudeM,
        windMs: windMs ?? this.windMs,
        weatherObservedAt: weatherObservedAt ?? this.weatherObservedAt,
        cachedTiles: cachedTiles ?? this.cachedTiles,
        packWeightGrams: packWeightGrams ?? this.packWeightGrams,
        followedRoute: followedRoute ?? this.followedRoute,
        busy: busy ?? this.busy,
        message: message,
      );

  factory SafeTripState.fromJson(Map<String, dynamic> j) => SafeTripState(
        active: j['active'] as bool? ?? false,
        startedAt: _date(j['started_at']),
        targetTime: _date(j['target_time']),
        baseTempC: (j['base_temp_c'] as num?)?.toDouble(),
        baseAltitudeM: (j['base_altitude_m'] as num?)?.toDouble(),
        windMs: (j['wind_ms'] as num?)?.toDouble(),
        weatherObservedAt: _date(j['weather_observed_at']),
        cachedTiles: (j['cached_tiles'] as num?)?.toInt() ?? 0,
        packWeightGrams: (j['pack_weight_g'] as num?)?.toInt(),
        followedRoute: j['followed_route'] == null
            ? null
            : PlannedRoute.fromJson(j['followed_route'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'active': active,
        'started_at': startedAt?.toIso8601String(),
        'target_time': targetTime?.toIso8601String(),
        'base_temp_c': baseTempC,
        'base_altitude_m': baseAltitudeM,
        'wind_ms': windMs,
        'weather_observed_at': weatherObservedAt?.toIso8601String(),
        'cached_tiles': cachedTiles,
        'pack_weight_g': packWeightGrams,
        'followed_route': followedRoute?.toJson(),
      };

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
}

class MedicalInfo {
  const MedicalInfo({
    this.bloodType = '',
    this.conditions = '',
    this.allergies = '',
    this.medications = '',
    this.contactName = '',
    this.contactPhone = '',
  });

  final String bloodType;
  final String conditions;
  final String allergies;
  final String medications;
  final String contactName;
  final String contactPhone;

  bool get isEmpty =>
      bloodType.isEmpty && conditions.isEmpty && allergies.isEmpty && contactPhone.isEmpty;

  factory MedicalInfo.fromJson(Map<String, dynamic> j) => MedicalInfo(
        bloodType: j['blood_type'] as String? ?? '',
        conditions: j['conditions'] as String? ?? '',
        allergies: j['allergies'] as String? ?? '',
        medications: j['medications'] as String? ?? '',
        contactName: j['contact_name'] as String? ?? '',
        contactPhone: j['contact_phone'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'blood_type': bloodType,
        'conditions': conditions,
        'allergies': allergies,
        'medications': medications,
        'contact_name': contactName,
        'contact_phone': contactPhone,
      };
}
