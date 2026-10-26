import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import '../models/campsite.dart';
import '../providers/campsite_provider.dart';
import '../providers/core_providers.dart';
import '../providers/safe_trip_provider.dart';
import '../services/offline_tile_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/campsite_sheet.dart';
import '../widgets/map_interaction.dart';
import '../widgets/mapbox_logo.dart';
import '../widgets/topo.dart';

/// (MAP_DARK=true 일 때) 밝은 지형도를 명도만 반전한 차콜 톤으로 — 야간 눈부심 방지.
/// 색상을 반전하면 녹지·바다가 보라·주황으로 튀므로 휘도(L)만 뒤집는다:
/// 흰 바탕(L=255) → #1E2420, 검은 글씨·등고선(L=0) → 밝은 회녹색
Widget _darkTopoTileBuilder(BuildContext context, Widget tileWidget, TileImage tile) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  const kR = (220 - 30) / 255, kG = (228 - 36) / 255, kB = (222 - 32) / 255;
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix(<double>[
      -kR * r, -kR * g, -kR * b, 0, 220, //
      -kG * r, -kG * g, -kG * b, 0, 228, //
      -kB * r, -kB * g, -kB * b, 0, 222, //
      0, 0, 0, 1, 0,
    ]),
    child: tileWidget,
  );
}

// Every site is drawn on its own — no clustering (user request).
// Below this zoom all ~2,900 sites are painted as plain dots in one CircleLayer
// pass (cheap); from this zoom up, only on-screen sites get icon widgets.
const _iconFromZoom = 9.0;

/// Draw order, bottom → top: the rarer and more important types stay visible.
const _drawOrder = [
  CampsiteType.campground,
  CampsiteType.forest,
  CampsiteType.review,
  CampsiteType.shelter,
  CampsiteType.restricted,
];

List<Campsite> _sortedForDrawing(List<Campsite> sites) =>
    [...sites]..sort((a, b) => _drawOrder.indexOf(a.type) - _drawOrder.indexOf(b.type));

/// Sites inside the current view (plus a margin so edge pins don't pop in late).
List<Campsite> _sitesInView(List<Campsite> sites, LatLngBounds? viewBounds) {
  // Right after onMapReady on slower devices the camera can report zero-size
  // bounds; treat that as "unknown" instead of hiding every pin.
  if (viewBounds == null || (viewBounds.north - viewBounds.south).abs() <= 1e-6) return sites;
  final padLat = (viewBounds.north - viewBounds.south) * 0.2;
  final padLng = (viewBounds.east - viewBounds.west) * 0.2;
  return [
    for (final s in sites)
      if (s.lat <= viewBounds.north + padLat &&
          s.lat >= viewBounds.south - padLat &&
          s.lng <= viewBounds.east + padLng &&
          s.lng >= viewBounds.west - padLng)
        s,
  ];
}

/// Icon pin size: small between zoom 9 and 11, full size from 11.
double _pinSize(double zoom) => zoom < 11 ? 24 : 38;

/// Tab 1: 합법 야영지 지도
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _initialZoom = 7.0;

  final _mapController = MapController();
  late final CachedTileProvider _tileProvider = CachedTileProvider(ref.read(tileCacheProvider));
  double _zoom = _initialZoom;
  double _rotation = 0;
  LatLngBounds? _bounds;
  Timer? _debounce;
  final LayerHitNotifier<Campsite> _dotHit = ValueNotifier(null);

  @override
  void dispose() {
    _debounce?.cancel();
    _dotHit.dispose();
    super.dispose();
  }

  /// 지도 이동이 멈춘 뒤에만 핀을 다시 고른다 (프레임마다 재계산 방지)
  void _onCameraChanged(MapCamera camera) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _zoom = camera.zoom;
        _rotation = camera.rotation;
        _bounds = camera.visibleBounds;
      });
    });
  }

  /// Several dots under one tap: list them and open the chosen one.
  Future<void> _pickOverlapping(List<Campsite> hits) async {
    final picked = await showModalBottomSheet<Campsite>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('이 위치에 ${hits.length}곳이 겹쳐 있어요',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final s in hits.take(12))
              ListTile(
                leading: Icon(campsiteIcon(s.type), color: siteColor(s)),
                title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(s.type.label),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) await showCampsiteSheet(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(filteredCampsitesProvider);
    final myPos = ref.watch(safeTripProvider.select((s) => s.lastPosition));
    final all = _sortedForDrawing(sites.valueOrNull ?? const []);
    final asDots = _zoom < _iconFromZoom;
    final iconSites = asDots ? const <Campsite>[] : _sitesInView(all, _bounds);
    final pinSize = _pinSize(_zoom);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(36.3, 127.9),
              initialZoom: _initialZoom,
              minZoom: 5,
              maxZoom: 17,
              interactionOptions: biviMapInteraction,
              // Measure again after the first frame, once the map has its real size.
              onMapReady: () => WidgetsBinding.instance
                  .addPostFrameCallback((_) => _onCameraChanged(_mapController.camera)),
              onPositionChanged: (camera, _) => _onCameraChanged(camera),
            ),
            children: [
              TileLayer(
                urlTemplate: Env.tileUrlTemplate,
                userAgentPackageName: Env.appId,
                tileProvider: _tileProvider,
                maxNativeZoom: Env.maxNativeZoom,
                tileBuilder: Env.applyDarkFilter ? _darkTopoTileBuilder : null,
              ),
              if (asDots)
                // Zoomed out: one canvas pass for every site; tapping a dot opens its sheet.
                GestureDetector(
                  onTap: () {
                    final hits = _dotHit.value?.hitValues ?? const <Campsite>[];
                    if (hits.isEmpty) return;
                    // hitValues are ordered top-to-bottom. Dots overlap a lot when
                    // zoomed out, so let the user pick when more than one was hit.
                    if (hits.length == 1) {
                      showCampsiteSheet(context, hits.first);
                    } else {
                      _pickOverlapping(List.of(hits));
                    }
                  },
                  child: CircleLayer<Campsite>(
                    hitNotifier: _dotHit,
                    circles: [
                      for (final s in all)
                        CircleMarker(
                          point: LatLng(s.lat, s.lng),
                          // ~2,800 campgrounds: keep their dots tiny so the terrain stays readable;
                          // rarer types are a bit larger so they stand out.
                          radius: switch (s.type) {
                            CampsiteType.shelter => 4,
                            CampsiteType.review || CampsiteType.restricted => 3,
                            _ => 2.5,
                          },
                          color: siteColor(s),
                          borderColor: Colors.white,
                          borderStrokeWidth: 0.8,
                          hitValue: s,
                        ),
                    ],
                  ),
                ),
              MarkerLayer(
                markers: [
                  for (final s in iconSites)
                    Marker(
                      point: LatLng(s.lat, s.lng),
                      width: pinSize,
                      height: pinSize,
                      child: _CampsitePin(site: s, onTap: () => showCampsiteSheet(context, s)),
                    ),
                  if (myPos != null)
                    Marker(
                      point: LatLng(myPos.lat, myPos.lng),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.lightBlueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(Env.attribution),
                  const TextSourceAttribution('야영장 데이터: 한국관광공사 고캠핑'),
                  const TextSourceAttribution('대피소: 국립공원공단 · © OpenStreetMap'),
                ],
              ),
            ],
          ),
          const Positioned(left: 10, bottom: 10, child: MapboxLogo()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BiviLogo(size: 52),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Glass(
                          child: Text(
                            sites.when(
                              data: (l) {
                                final reviews = l.where((s) => s.type == CampsiteType.review).length;
                                final legal = _formatCount(l.length - reviews);
                                if (reviews == 0) return '합법 야영지 · 대피소 $legal곳';
                                if (l.length == reviews) return '후기 박지 $reviews곳 (합법 여부 미확인)';
                                return '합법 $legal곳 · 후기 박지 $reviews곳';
                              },
                              loading: () => '야영지 불러오는 중…',
                              error: (_, __) => '데이터를 불러오지 못했습니다',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Glass(
                        padding: EdgeInsets.zero,
                        child: IconButton(
                          tooltip: '내 위치',
                          icon: const Icon(Icons.my_location),
                          onPressed: _goToMyLocation,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _FilterBar(),
                  if (_rotation.abs() > 0.5)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: NorthUpButton(
                          rotation: _rotation,
                          onPressed: () {
                            _mapController.rotate(0);
                            setState(() => _rotation = 0);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (sites.isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  static String _formatCount(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  Future<void> _goToMyLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('permission denied');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)),
      );
      _mapController.move(LatLng(p.latitude, p.longitude), 12);
    } catch (_) {
      final cached = ref.read(safeTripProvider).lastPosition;
      if (cached != null) {
        _mapController.move(LatLng(cached.lat, cached.lng), 12);
        messenger.showSnackBar(const SnackBar(content: Text('GPS 불가 — 마지막 저장 위치로 이동했습니다.')));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.')));
      }
    }
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(campsiteFilterProvider);
    void select(CampsiteType? t) => ref.read(campsiteFilterProvider.notifier).state = t;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('전체'),
            selected: selected == null,
            onSelected: (_) => select(null),
          ),
          for (final t in CampsiteType.values.where((t) => t != CampsiteType.restricted)) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              avatar: Icon(campsiteIcon(t), size: 16, color: campsiteColor(t)),
              label: Text(t.label),
              selected: selected == t,
              onSelected: (_) => select(selected == t ? null : t),
            ),
          ],
        ],
      ),
    );
  }
}

class _CampsitePin extends StatelessWidget {
  const _CampsitePin({required this.site, required this.onTap});

  final Campsite site;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = siteColor(site);
    return GestureDetector(
      onTap: onTap,
      // Size comes from the Marker; tiny pins render as plain dots without an icon.
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.maxWidth;
          return Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: size < 22 ? 1.5 : 2),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
            ),
            child: size < 22 ? null : Icon(campsiteIcon(site.type), size: size * 0.5, color: Colors.white),
          );
        },
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 11)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: BiviColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BiviColors.contour),
      ),
      child: child,
    );
  }
}
