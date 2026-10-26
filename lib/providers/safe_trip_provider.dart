import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/repositories.dart';
import '../models/campsite.dart';
import '../models/gpx_route.dart';
import '../models/hike_record.dart';
import '../models/trip.dart';
import '../services/battery_guard.dart';
import '../services/hike_analysis.dart';
import '../services/kma_weather_service.dart';
import '../utils/format.dart';
import 'campsite_provider.dart';
import 'core_providers.dart';
import 'gear_provider.dart';
import 'records_provider.dart';

final safeTripStoreProvider = Provider((ref) => SafeTripStore(ref.watch(sharedPrefsProvider)));

final safeTripProvider = NotifierProvider<SafeTripNotifier, SafeTripState>(SafeTripNotifier.new);

class SafeTripNotifier extends Notifier<SafeTripState> {
  late SafeTripStore _store;
  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeat;

  Timer? _resumeTimer;

  @override
  SafeTripState build() {
    _store = ref.watch(safeTripStoreProvider);
    ref.onDispose(() {
      _resumeTimer?.cancel();
      _stopTracking();
    });
    final restored = _store.load();
    // 앱이 재시작되어도 산행 중이었다면 위치 캐싱을 이어서 재개.
    // Wait a moment: geolocator binds its Android foreground service asynchronously, and a stream
    // opened before that silently never delivers ("background service has not started correctly").
    if (restored.active) {
      _resumeTimer = Timer(const Duration(seconds: 2), () {
        if (state.active && _positionSub == null) {
          _startTracking();
          _reportRecordingGap();
          // The 2 s head start isn't always enough (a locked phone binds the service slower, and a stream
          // opened too early never delivers). If nothing came yet, subscribe once more.
          _resumeTimer = Timer(const Duration(seconds: 15), () {
            if (state.active && !_streamDelivered) _startTracking();
          });
        }
      });
    }
    return restored;
  }

  /// Whether the position stream has delivered since it was (re)opened.
  bool _streamDelivered = false;

  /// After the app was killed mid-hike: say how long nothing was recorded (PRD_step5 5-5).
  Future<void> _reportRecordingGap() async {
    final track = await ref.read(hikeRecordStoreProvider).readActiveTrack();
    if (track.isEmpty) return;
    final last = track.map((p) => p.time).reduce((a, b) => a.isAfter(b) ? a : b);
    final now = DateTime.now();
    if (now.difference(last) < maxGap) return;
    state = state.copyWith(
      message: '앱이 꺼져 있던 ${formatTime(last)}~${formatTime(now)} 동안 위치가 기록되지 않았어요. '
          '이 구간은 거리·이동 시간에서 빠져요.',
    );
  }

  void setTargetTime(DateTime target) {
    state = state.copyWith(targetTime: target);
    _store.save(state);
  }

  void extendTarget(Duration by) {
    final base = state.targetTime ?? DateTime.now();
    final from = base.isBefore(DateTime.now()) ? DateTime.now() : base;
    setTargetTime(from.add(by));
  }

  /// 산행 시작: 권한 확인 → 현재 좌표 캐싱 → 위치 스트림 구독 → 주변 타일 · 기상 프리패치
  Future<void> start() async {
    if (state.targetTime == null) {
      state = state.copyWith(message: '예정 하산 시간을 먼저 설정하세요.');
      return;
    }
    state = state.copyWith(busy: true);

    if (!await _ensurePermission()) {
      state = state.copyWith(busy: false, message: '위치 권한이 필요합니다. 설정에서 \'항상 허용\'을 권장합니다.');
      return;
    }

    CachedPosition? first;
    Position? firstFix;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      first = CachedPosition.fromPosition(p);
      await _store.savePosition(first);
      firstFix = p;
    } catch (e) {
      debugPrint('initial fix failed: $e');
      first = state.lastPosition;
    }

    // A fresh track for the hike record (PRD_step5).
    final records = ref.read(hikeRecordStoreProvider);
    await records.beginTrack();
    if (firstFix != null) await records.appendPoint(TrackPoint.fromPosition(firstFix));

    state = SafeTripState(
      active: true,
      startedAt: DateTime.now(),
      targetTime: state.targetTime,
      lastPosition: first,
      baseAltitudeM: first?.altitude,
      packWeightGrams: ref.read(packedWeightProvider),
      message: first == null ? 'GPS 신호 대기 중 — 좌표가 잡히면 자동 저장됩니다.' : null,
    );
    await _store.save(state);
    _startTracking();

    if (first != null) {
      unawaited(_prefetchTiles(first));
      unawaited(refreshWeather());
    }
  }

  /// Remembers the GPX route the user is following, for the hike record.
  void markRouteFollowed(GpxRoute route) {
    if (!state.active) return;
    state = state.copyWith(
      followedRoute: PlannedRoute(
        name: route.name,
        distanceM: route.totalMeters,
        gainM: route.elevationGain,
      ),
    );
    _store.save(state);
  }

  /// Summary for the finish screen. Tracking keeps running until [finish].
  Future<HikeFinishPreview> previewFinish(DateTime end) async {
    final track = await _trackUntil(end);
    final start = state.startedAt ?? (track.isEmpty ? end : track.first.time);
    return HikeFinishPreview(
      startedAt: start,
      endedAt: end,
      stats: analyzeTrack(track, start: start, end: end),
      suggestedPlace: state.followedRoute?.name ?? await _nearbyPlaceName(track) ?? '',
      pointCount: track.length,
    );
  }

  /// Ends the hike. With [save] the track up to [end] becomes a hike record first;
  /// if saving fails, tracking keeps running and the error is rethrown.
  Future<HikeRecord?> finish({
    required bool save,
    DateTime? end,
    String place = '',
    int? rating,
    String memo = '',
    PlannedRoute? route,
  }) async {
    final records = ref.read(hikeRecordStoreProvider);
    HikeRecord? record;
    if (save) {
      final endedAt = end ?? DateTime.now();
      final track = await _trackUntil(endedAt);
      final startedAt = state.startedAt ?? (track.isEmpty ? endedAt : track.first.time);
      record = HikeRecord(
        id: uuidV4(),
        startedAt: startedAt,
        endedAt: endedAt,
        stats: analyzeTrack(track, start: startedAt, end: endedAt),
        place: place.trim(),
        packWeightGrams: state.packWeightGrams,
        rating: rating,
        memo: memo.trim(),
        route: route,
        pointCount: track.length,
      );
      await ref.read(hikeRecordsProvider.notifier).add(record, track);
    }

    _stopTracking();
    await records.discardActiveTrack();
    // 마지막 좌표는 SOS 카드용으로 유지
    state = SafeTripState(lastPosition: state.lastPosition);
    await _store.save(state);
    return record;
  }

  Future<List<TrackPoint>> _trackUntil(DateTime end) async {
    final all = await ref.read(hikeRecordStoreProvider).readActiveTrack();
    return all.where((p) => !p.time.isAfter(end)).toList()..sort((a, b) => a.time.compareTo(b.time));
  }

  /// "○○ 부근" for the app place nearest to the hike's high point (within 3 km). Offline.
  Future<String?> _nearbyPlaceName(List<TrackPoint> track) async {
    final top = highestPoint(track);
    if (top == null) return null;
    try {
      final sites = await ref.read(campsitesProvider.future).timeout(const Duration(seconds: 3));
      final here = GpxPoint(top.lat, top.lng);
      Campsite? best;
      var bestM = 3000.0;
      for (final c in sites) {
        final m = haversine(here, GpxPoint(c.lat, c.lng));
        if (m < bestM) {
          best = c;
          bestM = m;
        }
      }
      return best == null ? null : '${best.name} 부근';
    } catch (e) {
      debugPrint('nearby place lookup failed: $e');
      return null;
    }
  }

  Future<void> refreshWeather() async {
    final pos = state.lastPosition;
    if (pos == null) return;
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      state = state.copyWith(message: '날씨 서버 미연결 — 기준 기온을 직접 입력하세요.');
      return;
    }
    try {
      final obs = await KmaWeatherService(client).fetchCurrent(pos.lat, pos.lng);
      state = state.copyWith(
        baseTempC: obs.tempC,
        windMs: obs.windMs,
        weatherObservedAt: obs.observedAt,
        baseAltitudeM: state.baseAltitudeM ?? pos.altitude,
      );
      await _store.save(state);
    } catch (e) {
      state = state.copyWith(message: '기상 정보를 가져오지 못했습니다: $e');
    }
  }

  /// 통신 불가 / API 키 없음 대비 수동 입력 (기준 고도 = 현재 고도)
  void setManualWeather({required double tempC, double? windMs}) {
    state = state.copyWith(
      baseTempC: tempC,
      windMs: windMs ?? 0,
      weatherObservedAt: DateTime.now(),
      baseAltitudeM: state.lastPosition?.altitude ?? state.baseAltitudeM,
    );
    _store.save(state);
  }

  // ───────────────────────── 내부 ─────────────────────────

  void _startTracking() {
    _stopTracking();
    _streamDelivered = false;
    _positionSub = Geolocator.getPositionStream(locationSettings: _trackingSettings()).listen(
      (p) {
        _streamDelivered = true;
        _onPosition(p);
      },
      onError: (Object e) =>
          state = state.copyWith(message: 'GPS 신호 없음 — 마지막 저장 좌표를 유지합니다.'),
    );
    // 정지 상태(distanceFilter 미충족)에서도 타임스탬프가 갱신되도록 1분마다 강제 측위
    _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) async {
      try {
        _onPosition(await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        ));
      } catch (_) {}
    });
  }

  void _stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _onPosition(Position p) {
    final cached = CachedPosition.fromPosition(p);
    _store.savePosition(cached);
    if (state.active) ref.read(hikeRecordStoreProvider).appendPoint(TrackPoint.fromPosition(p));
    state = state.copyWith(
      lastPosition: cached,
      baseAltitudeM: state.baseAltitudeM ?? cached.altitude,
    );
  }

  Future<void> _prefetchTiles(CachedPosition pos) async {
    final count = await ref.read(tileCacheProvider).prefetchAround(pos.lat, pos.lng);
    state = state.copyWith(cachedTiles: count);
    await _store.save(state);
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  LocationSettings _trackingSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
          intervalDuration: const Duration(seconds: 30),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Bivi 산행 모드',
            notificationText: '현재 위치를 기기에 주기적으로 저장하고 있습니다.',
            enableWakeLock: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.fitness,
          distanceFilter: 15,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      default:
        return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15);
    }
  }
}

/// What the finish screen shows before the record is saved.
class HikeFinishPreview {
  const HikeFinishPreview({
    required this.startedAt,
    required this.endedAt,
    required this.stats,
    required this.suggestedPlace,
    required this.pointCount,
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final HikeStats stats;
  final String suggestedPlace;
  final int pointCount;

  Duration get duration => endedAt.difference(startedAt);
}

/// Whether Android exempts Bivi from battery optimization (null = unknown). Re-read on app resume.
final batteryUnrestrictedProvider =
    FutureProvider.autoDispose<bool?>((ref) => BatteryGuard.isUnrestricted());

final medicalInfoProvider =
    NotifierProvider<MedicalInfoNotifier, MedicalInfo>(MedicalInfoNotifier.new);

class MedicalInfoNotifier extends Notifier<MedicalInfo> {
  @override
  MedicalInfo build() => ref.watch(safeTripStoreProvider).loadMedical();

  void save(MedicalInfo info) {
    state = info;
    ref.read(safeTripStoreProvider).saveMedical(info);
  }
}
