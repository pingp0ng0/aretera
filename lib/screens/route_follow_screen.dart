import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import '../models/gpx_route.dart';
import '../providers/core_providers.dart';
import '../providers/gpx_provider.dart';
import '../providers/safe_trip_provider.dart';
import '../services/offline_tile_cache.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/map_interaction.dart';
import '../widgets/mapbox_logo.dart';

/// 이 거리 이상 벗어나면 경로 이탈 경고 (GPS 오차가 더 크면 오차를 기준으로)
const _offRouteMeters = 50.0;
const _routeColor = Color(0xFFE5398A); // 지형도 위에서 잘 보이는 마젠타

/// GPX 경로 따라가기: 지도 위에 경로 · 현재 위치 · 남은 거리 · 이탈 경고
class RouteFollowScreen extends ConsumerStatefulWidget {
  const RouteFollowScreen({super.key});

  @override
  ConsumerState<RouteFollowScreen> createState() => _RouteFollowScreenState();
}

class _RouteFollowScreenState extends ConsumerState<RouteFollowScreen> {
  final _map = MapController();
  late final CachedTileProvider _tiles = CachedTileProvider(ref.read(tileCacheProvider));
  StreamSubscription<Position>? _sub;
  Position? _pos;
  RouteProgress? _progress;
  bool _followMe = true;
  bool _rotated = false;
  bool _wasOffRoute = false;
  String? _gpsError;

  @override
  void initState() {
    super.initState();
    _startGps();
    // The hike record notes which GPX route was followed (PRD_step5).
    final route = ref.read(gpxProvider).route;
    if (route != null) ref.read(safeTripProvider.notifier).markRouteFollowed(route);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() => _gpsError = '위치 권한이 없어 현재 위치를 표시할 수 없습니다.');
      return;
    }
    // 화면을 보고 있는 동안은 촘촘하게 갱신 (백그라운드 저장은 산행 모드가 담당)
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3),
    ).listen(_onPosition, onError: (Object e) {
      if (mounted) setState(() => _gpsError = 'GPS 신호를 찾는 중…');
    });
  }

  void _onPosition(Position p) {
    final route = ref.read(gpxProvider).route;
    final progress = route == null
        ? null
        : RouteProgress.compute(route, GpxPoint(p.latitude, p.longitude), hint: _progress?.segmentIndex);
    final offRoute = progress != null && progress.offRouteMeters > _threshold(p);
    if (offRoute && !_wasOffRoute) HapticFeedback.heavyImpact();
    _wasOffRoute = offRoute;

    setState(() {
      _pos = p;
      _progress = progress;
      _gpsError = null;
    });
    if (_followMe) {
      try {
        _map.move(LatLng(p.latitude, p.longitude), _map.camera.zoom);
      } catch (_) {
        // 지도가 아직 붙기 전의 첫 위치 — 다음 갱신에서 따라간다
      }
    }
  }

  double _threshold(Position p) => p.accuracy > _offRouteMeters ? p.accuracy : _offRouteMeters;

  void _fitRoute(GpxRoute route) {
    setState(() => _followMe = false);
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([for (final p in route.points) LatLng(p.lat, p.lng)]),
      padding: const EdgeInsets.fromLTRB(40, 180, 40, 140),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(gpxProvider).route;
    if (route == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('불러온 GPX 경로가 없습니다.')));
    }
    final progress = _progress;
    final pos = _pos;
    final offRoute = progress != null && pos != null && progress.offRouteMeters > _threshold(pos);
    final split = progress == null ? 0 : progress.segmentIndex + 1;
    final all = [for (final p in route.points) LatLng(p.lat, p.lng)];
    final done = [...all.take(split), if (progress != null) LatLng(progress.snapped.lat, progress.snapped.lng)];
    final ahead = [if (progress != null) LatLng(progress.snapped.lat, progress.snapped.lng), ...all.skip(split)];

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(all),
                padding: const EdgeInsets.fromLTRB(40, 180, 40, 140),
              ),
              minZoom: 6,
              maxZoom: 18,
              interactionOptions: biviMapInteraction,
              // 사용자가 지도를 직접 움직이면 자동 따라가기를 끈다
              onPositionChanged: (camera, hasGesture) {
                final rotated = camera.rotation.abs() > 0.5;
                if ((hasGesture && _followMe) || rotated != _rotated) {
                  setState(() {
                    if (hasGesture) _followMe = false;
                    _rotated = rotated;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: Env.tileUrlTemplate,
                userAgentPackageName: Env.appId,
                tileProvider: _tiles,
                maxNativeZoom: Env.maxNativeZoom,
              ),
              PolylineLayer(
                polylines: [
                  Polyline(points: all, color: _routeColor, strokeWidth: 6, borderColor: Colors.white, borderStrokeWidth: 2),
                  if (done.length >= 2) Polyline(points: done, color: Colors.grey.shade600, strokeWidth: 6),
                  if (ahead.length >= 2 && progress != null)
                    Polyline(points: ahead, color: _routeColor, strokeWidth: 6),
                  // 이탈 시 경로까지의 최단 연결선
                  if (offRoute)
                    Polyline(
                      points: [LatLng(pos.latitude, pos.longitude), LatLng(progress.snapped.lat, progress.snapped.lng)],
                      color: BiviColors.amber,
                      strokeWidth: 3,
                      pattern: StrokePattern.dashed(segments: const [8, 6]),
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final w in route.waypoints)
                    Marker(
                      point: LatLng(w.point.lat, w.point.lng),
                      width: 120,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: _WaypointLabel(name: w.name),
                    ),
                  Marker(point: all.first, width: 34, height: 34, child: const _EndPin(start: true)),
                  Marker(point: all.last, width: 34, height: 34, child: const _EndPin(start: false)),
                  if (pos != null)
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 40,
                      height: 40,
                      child: _MyPosition(heading: pos.speed > 0.5 ? pos.heading : null),
                    ),
                ],
              ),
            ],
          ),
          const Positioned(left: 10, bottom: 96, child: MapboxLogo()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _Hud(route: route, progress: progress, pos: pos, offRoute: offRoute, gpsError: _gpsError),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'close',
                    backgroundColor: BiviColors.surface,
                    onPressed: () => Navigator.pop(context),
                    child: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  if (_rotated) ...[
                    NorthUpButton(
                      rotation: _map.camera.rotation,
                      onPressed: () {
                        _map.rotate(0);
                        setState(() => _rotated = false);
                      },
                    ),
                    const SizedBox(width: 10),
                  ],
                  FloatingActionButton.small(
                    heroTag: 'fit',
                    backgroundColor: BiviColors.surface,
                    onPressed: () => _fitRoute(route),
                    child: const Icon(Icons.zoom_out_map),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'follow',
                    backgroundColor: _followMe ? BiviColors.forest : BiviColors.surface,
                    foregroundColor: Colors.white,
                    onPressed: () {
                      setState(() => _followMe = true);
                      final p = _pos;
                      if (p != null) _map.move(LatLng(p.latitude, p.longitude), _map.camera.zoom < 14 ? 15 : _map.camera.zoom);
                    },
                    icon: Icon(_followMe ? Icons.navigation : Icons.navigation_outlined),
                    label: Text(_followMe ? '따라가는 중' : '내 위치 따라가기'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hud extends ConsumerWidget {
  const _Hud({required this.route, required this.progress, required this.pos, required this.offRoute, this.gpsError});

  final GpxRoute route;
  final RouteProgress? progress;
  final Position? pos;
  final bool offRoute;
  final String? gpsError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripActive = ref.watch(safeTripProvider.select((s) => s.active));
    final p = progress;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: BiviColors.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(route.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BiviColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Stat(label: '남은 거리', value: formatDistance(p?.remainingMeters ?? route.totalMeters), big: true),
                  const Spacer(),
                  _Stat(label: '진행', value: '${((p?.ratio ?? 0) * 100).round()}%'),
                  const SizedBox(width: 18),
                  _Stat(label: '고도', value: pos == null ? '-' : '${pos!.altitude.round()} m'),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p?.ratio ?? 0,
                  minHeight: 6,
                  color: _routeColor,
                  backgroundColor: BiviColors.surfaceHigh,
                ),
              ),
            ],
          ),
        ),
        if (offRoute && p != null) ...[
          const SizedBox(height: 8),
          _Banner(
            color: BiviColors.amber,
            icon: Icons.wrong_location,
            text: '경로에서 ${formatDistance(p.offRouteMeters)} 벗어났습니다',
          ),
        ],
        if (gpsError != null) ...[
          const SizedBox(height: 8),
          _Banner(color: BiviColors.surfaceHigh, icon: Icons.gps_not_fixed, text: gpsError!, dark: false),
        ],
        if (!tripActive) ...[
          const SizedBox(height: 8),
          const _Banner(
            color: BiviColors.surfaceHigh,
            icon: Icons.info_outline,
            text: '산행 모드를 시작해야 화면이 꺼져도 위치가 저장됩니다.',
            dark: false,
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.big = false});

  final String label;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: BiviColors.textSecondary, fontSize: 12)),
        Text(value,
            style: TextStyle(
              fontSize: big ? 28 : 18,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text, this.dark = true});

  final Color color;
  final IconData icon;
  final String text;

  /// true 면 밝은 배경 위 검은 글씨
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.black : BiviColors.textPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _MyPosition extends StatelessWidget {
  const _MyPosition({this.heading});

  /// 이동 중일 때만 진행 방향(도)
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
      ),
    );
    final h = heading;
    if (h == null) return Center(child: dot);
    return Transform.rotate(
      angle: h * 3.1415926535 / 180,
      child: const Icon(Icons.navigation, size: 36, color: Color(0xFF1E88E5), shadows: [Shadow(color: Colors.white, blurRadius: 4)]),
    );
  }
}

class _EndPin extends StatelessWidget {
  const _EndPin({required this.start});

  final bool start;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: start ? const Color(0xFF2E7D32) : Colors.black87,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(start ? Icons.play_arrow : Icons.sports_score, color: Colors.white, size: 20),
    );
  }
}

class _WaypointLabel extends StatelessWidget {
  const _WaypointLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6)),
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        const Icon(Icons.place, size: 20, color: _routeColor),
      ],
    );
  }
}
