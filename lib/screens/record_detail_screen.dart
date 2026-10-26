import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import '../models/hike_record.dart';
import '../providers/core_providers.dart';
import '../providers/records_provider.dart';
import '../services/hike_analysis.dart';
import '../services/offline_tile_cache.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/charts.dart';
import '../widgets/map_interaction.dart';
import '../widgets/mapbox_logo.dart';
import '../widgets/star_rating.dart';
import '../widgets/summary_stat.dart';

const _trackColor = Color(0xFFE5398A); // same magenta as GPX follow

/// One saved hike: route on the map, elevation profile and numbers (PRD_step5 5-2).
class RecordDetailScreen extends ConsumerWidget {
  const RecordDetailScreen({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(hikeRecordsProvider).where((r) => r.id == recordId).firstOrNull;
    if (record == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('기록을 찾을 수 없습니다.')));
    }
    final track = ref.watch(hikeTrackProvider(recordId));
    final s = record.stats;

    return Scaffold(
      appBar: AppBar(
        title: Text(record.displayPlace, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '수정',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(context, ref, record),
          ),
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref, record),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            '${formatDateWeekday(record.startedAt)} · ${formatTime(record.startedAt)} – ${formatTime(record.endedAt)}',
            style: const TextStyle(color: BiviColors.textSecondary),
          ),
          if (record.rating != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                StarRatingView(value: record.rating!, size: 18),
                const SizedBox(width: 6),
                Text('체감 ${difficultyLabels[record.rating! - 1]}',
                    style: const TextStyle(color: BiviColors.textSecondary)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          track.when(
            data: (points) => _MapPreview(record: record, points: drawableTrack(points)),
            loading: () => const _MapBox(child: Center(child: CircularProgressIndicator())),
            error: (e, _) => _MapBox(child: Center(child: Text('경로를 불러오지 못했습니다: $e'))),
          ),
          if (s.gapSec > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: BiviColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BiviColors.amber.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.link_off, color: BiviColors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '위치 기록이 ${s.gapCount}번 끊겼어요 · ${formatDuration(s.gap)} (직선 ${formatDistance(s.gapDistanceM)}). '
                      '앱이 꺼져 있던 구간이라 지도에 점선으로 표시하고, 거리·이동 시간·페이스에서는 뺐어요.',
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Section(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: SummaryStat(label: '소요 시간', value: formatDuration(record.duration))),
                    Expanded(child: SummaryStat(label: '거리', value: formatDistance(s.distanceM))),
                    Expanded(child: SummaryStat(label: '상승 고도', value: '${s.gainM.round()} m')),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: SummaryStat(label: '이동 시간', value: formatDuration(s.moving))),
                    Expanded(child: SummaryStat(label: '휴식', value: '${formatDuration(s.rest)} · ${s.restCount}회')),
                    Expanded(
                      child: SummaryStat(label: '최고 고도', value: s.maxAltM == null ? '-' : '${s.maxAltM!.round()} m'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: SummaryStat(label: '하강 고도', value: '${s.lossM.round()} m')),
                    Expanded(
                      child: SummaryStat(
                        label: '배낭 무게',
                        value: record.packWeightGrams == null ? '-' : '${formatKg(record.packWeightGrams!, digits: 1)} kg',
                      ),
                    ),
                    Expanded(
                      child: SummaryStat(
                        label: '평균 속도(이동)',
                        value: s.movingSec < 60 ? '-' : '${(s.distanceM / 1000 / (s.movingSec / 3600)).toStringAsFixed(1)} km/h',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: '고도 그래프',
            child: track.when(
              data: (points) => ElevationChart(profile: elevationProfile(points)),
              loading: () => const SizedBox(height: 170),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: '구간별 페이스',
            child: Column(
              children: [
                SlopeRow(label: '오르막', icon: Icons.trending_up, totals: s.up, sign: '+'),
                SlopeRow(label: '내리막', icon: Icons.trending_down, totals: s.down, sign: '−'),
                SlopeRow(label: '평지', icon: Icons.trending_flat, totals: s.flat),
              ],
            ),
          ),
          if (record.route != null) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'GPX 경로',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.route!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    '계획 ${formatDistance(record.route!.distanceM)} · 상승 ${record.route!.gainM.round()} m\n'
                    '실제 ${formatDistance(s.distanceM)} · 상승 ${s.gainM.round()} m',
                    style: const TextStyle(color: BiviColors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
          if (record.memo.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(title: '메모', child: Text(record.memo, style: const TextStyle(height: 1.5))),
          ],
          const SizedBox(height: 12),
          const Text(
            '거리·고도는 휴대폰 GPS 기준 추정치입니다. 고도는 흔들림을 걸러 계산해 실제와 다를 수 있어요.',
            style: TextStyle(color: BiviColors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, HikeRecord record) async {
    final updated = await showDialog<HikeRecord>(
      context: context,
      builder: (_) => _EditDialog(record: record),
    );
    if (updated != null) await ref.read(hikeRecordsProvider.notifier).update(updated);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, HikeRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 기록을 삭제할까요?'),
        content: Text('"${record.displayPlace}" 의 경로와 통계가 기기에서 지워지며 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(hikeRecordsProvider.notifier).delete(record.id);
    navigator.pop();
  }
}

/// Uphill / downhill / flat line: pace, speed and vertical rate.
class SlopeRow extends StatelessWidget {
  const SlopeRow({super.key, required this.label, required this.icon, required this.totals, this.sign});

  final String label;
  final IconData icon;
  final SlopeTotals totals;

  /// '+' or '−' to show the vertical rate (m/h); null for flat.
  final String? sign;

  @override
  Widget build(BuildContext context) {
    final kmh = totals.kmh;
    final vph = totals.verticalPerHour;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: BiviColors.forestLight),
          const SizedBox(width: 8),
          SizedBox(width: 52, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: kmh == null
                ? const Text('데이터 부족', style: TextStyle(color: BiviColors.textSecondary))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${formatPace(3600 / kmh)} · ${kmh.toStringAsFixed(1)} km/h',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      Text(
                        [
                          '${formatDistance(totals.distanceM)} · ${formatDuration(Duration(seconds: totals.seconds))}',
                          if (sign != null && vph != null) '시간당 $sign${vph.round()} m',
                        ].join(' · '),
                        style: const TextStyle(color: BiviColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.title});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(color: BiviColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _MapBox extends StatelessWidget {
  const _MapBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(height: 240, child: ColoredBox(color: BiviColors.surface, child: child)),
    );
  }
}

/// Fixed (non-scrollable) map in the page; tap opens the full-screen map.
class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.record, required this.points});

  final HikeRecord record;
  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _MapBox(
        child: Center(child: Text('저장된 이동 경로가 없어요', style: TextStyle(color: BiviColors.textSecondary))),
      );
    }
    return _MapBox(
      child: Stack(
        children: [
          TrackMap(points: points, interactive: false),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _FullMapScreen(title: record.displayPlace, points: points),
                )),
              ),
            ),
          ),
          const Positioned(
            right: 10,
            top: 10,
            child: Icon(Icons.open_in_full, color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
          ),
        ],
      ),
    );
  }
}

class _FullMapScreen extends StatelessWidget {
  const _FullMapScreen({required this.title, required this.points});

  final String title;
  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: TrackMap(points: points, interactive: true),
    );
  }
}

/// Recorded track on the topo map, with start/end pins. Uses the offline tile cache.
class TrackMap extends ConsumerStatefulWidget {
  const TrackMap({super.key, required this.points, required this.interactive});

  final List<TrackPoint> points;
  final bool interactive;

  @override
  ConsumerState<TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends ConsumerState<TrackMap> {
  late final CachedTileProvider _tiles = CachedTileProvider(ref.read(tileCacheProvider));

  @override
  Widget build(BuildContext context) {
    LatLng ll(TrackPoint p) => LatLng(p.lat, p.lng);
    final line = [for (final p in widget.points) ll(p)];
    final parts = splitAtGaps(widget.points);
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(line),
              padding: const EdgeInsets.all(32),
              maxZoom: 16,
            ),
            minZoom: 6,
            maxZoom: 18,
            interactionOptions: widget.interactive
                ? biviMapInteraction
                : const InteractionOptions(flags: InteractiveFlag.none),
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
                // Where recording stopped: a dashed straight line, not a walked path (PRD_step5 5-5).
                for (var i = 1; i < parts.length; i++)
                  Polyline(
                    points: [ll(parts[i - 1].last), ll(parts[i].first)],
                    color: Colors.grey.shade500,
                    strokeWidth: 3,
                    pattern: StrokePattern.dashed(segments: const [8, 6]),
                  ),
                for (final part in parts)
                  if (part.length >= 2)
                    Polyline(
                      points: [for (final p in part) ll(p)],
                      color: _trackColor,
                      strokeWidth: 5,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                    ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(point: line.first, width: 28, height: 28, child: const _Pin(start: true)),
                if (line.length >= 2) Marker(point: line.last, width: 28, height: 28, child: const _Pin(start: false)),
              ],
            ),
            if (widget.interactive)
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomRight,
                attributions: [TextSourceAttribution(Env.attribution)],
              ),
          ],
        ),
        const Positioned(left: 8, bottom: 8, child: MapboxLogo()),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.start});

  final bool start;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: start ? const Color(0xFF2E7D32) : Colors.black87,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(start ? Icons.play_arrow : Icons.sports_score, color: Colors.white, size: 16),
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.record});

  final HikeRecord record;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _place = TextEditingController(text: widget.record.place);
  late final _memo = TextEditingController(text: widget.record.memo);
  late int? _rating = widget.record.rating;

  @override
  void dispose() {
    _place.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('기록 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _place, decoration: const InputDecoration(labelText: '장소')),
            const SizedBox(height: 16),
            const Text('체감 난이도', style: TextStyle(color: BiviColors.textSecondary)),
            FittedBox(
              child: StarRatingInput(value: _rating, onChanged: (v) => setState(() => _rating = v)),
            ),
            TextField(
              controller: _memo,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '메모', alignLabelWithHint: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            HikeRecord(
              id: widget.record.id,
              startedAt: widget.record.startedAt,
              endedAt: widget.record.endedAt,
              stats: widget.record.stats,
              place: _place.text.trim(),
              packWeightGrams: widget.record.packWeightGrams,
              rating: _rating,
              memo: _memo.text.trim(),
              route: widget.record.route,
              pointCount: widget.record.pointCount,
            ),
          ),
          child: const Text('저장'),
        ),
      ],
    );
  }
}
