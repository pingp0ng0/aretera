import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../providers/gpx_provider.dart';
import '../providers/records_provider.dart';
import '../providers/report_provider.dart';
import '../services/hike_insights.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/charts.dart';
import '../widgets/report_text.dart';
import '../widgets/star_rating.dart';
import '../widgets/summary_stat.dart';
import 'record_detail_screen.dart' show SlopeRow;

/// 기록 → 분석 tab: statistics computed on the device from saved hikes (PRD_step5 5-3).
class InsightsView extends ConsumerWidget {
  const InsightsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = ref.watch(hikeInsightsProvider);
    final hasServer = ref.watch(supabaseClientProvider) != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (hasServer) ...[
          _AiReportCard(canGenerate: i.eligibleCount > 0),
          const SizedBox(height: 12),
        ],
        _TotalsCard(insights: i),
        const SizedBox(height: 12),
        _NextCourseCard(pace: i.pace),
        const SizedBox(height: 12),
        _Card(
          title: '오르막 · 내리막 페이스',
          footnote: i.eligibleCount == 0
              ? '거리 500m · 이동 10분 이상인 기록부터 계산해요.'
              : '기록 ${i.eligibleCount}개의 구간을 합쳐 계산 (경사 ±5% 기준).',
          child: Column(
            children: [
              SlopeRow(label: '오르막', icon: Icons.trending_up, totals: i.up, sign: '+'),
              SlopeRow(label: '내리막', icon: Icons.trending_down, totals: i.down, sign: '−'),
              SlopeRow(label: '평지', icon: Icons.trending_flat, totals: i.flat),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _RestCard(insights: i),
        const SizedBox(height: 12),
        _WeightCard(insights: i),
        const SizedBox(height: 12),
        _DifficultyCard(insights: i),
        const SizedBox(height: 12),
        const Text(
          '노력거리 = 거리(km) + 상승 고도(m) ÷ 100. 오르막 100m 를 평지 1km 만큼의 힘으로 환산해 '
          '코스 난이도가 달라도 속도를 비교할 수 있게 한 값이에요.',
          style: TextStyle(color: BiviColors.textSecondary, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.footnote});

  final String title;
  final Widget child;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: BiviColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          child,
          if (footnote != null) ...[
            const SizedBox(height: 8),
            Text(footnote!, style: const TextStyle(color: BiviColors.textSecondary, fontSize: 12, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

const _muted = TextStyle(color: BiviColors.textSecondary, height: 1.5);

/// AI interpretation of the numbers below (PRD_step6 6-3). Online only; the last report stays on the device.
class _AiReportCard extends ConsumerWidget {
  const _AiReportCard({required this.canGenerate});

  /// At least one record long enough for statistics.
  final bool canGenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(aiReportProvider);
    final report = s.report;
    final stale = report != null && report.input != jsonEncode(ref.watch(reportInputProvider));
    final label = report == null ? 'AI 리포트 만들기' : (stale ? '새 기록으로 다시 만들기' : '다시 만들기');

    return _Card(
      title: 'AI 리포트',
      footnote: 'AI(무료 모델)가 아래 숫자를 읽고 쓴 해석이라 틀릴 수 있어요. '
          '보내는 건 요약 숫자뿐이에요(위치·장소 이름·메모·정확한 날짜는 보내지 않아요).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report == null && !s.busy)
            Text(
              canGenerate
                  ? '내 기록 숫자를 AI 가 읽고 잘하는 점과 다음 산행 제안을 글로 정리해 드려요.'
                  : '거리 500m · 이동 10분 이상인 기록이 있으면 만들 수 있어요.',
              style: _muted,
            ),
          if (report != null) ...[
            ReportText(report.text),
            const SizedBox(height: 6),
            Text(
              '${report.modelLabel} · ${formatDate(report.createdAt)} ${formatTime(report.createdAt)}',
              style: const TextStyle(color: BiviColors.textSecondary, fontSize: 12),
            ),
            if (stale)
              const Text('이 리포트를 만든 뒤 기록이 바뀌었어요.',
                  style: TextStyle(color: BiviColors.amber, fontSize: 12)),
          ],
          if (s.busy) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                SizedBox(width: 10),
                Expanded(child: Text('AI 가 기록을 읽고 있어요… 무료 모델이라 1분 넘게 걸릴 수 있어요.', style: _muted)),
              ],
            ),
          ],
          if (s.error != null) ...[
            const SizedBox(height: 8),
            Text(s.error!, style: const TextStyle(color: BiviColors.amber, height: 1.4)),
          ],
          const SizedBox(height: 10),
          if (report == null)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: BiviColors.forest, minimumSize: const Size.fromHeight(44)),
              onPressed: canGenerate && !s.busy ? () => ref.read(aiReportProvider.notifier).generate() : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(label),
            )
          else
            TextButton.icon(
              onPressed: canGenerate && !s.busy ? () => ref.read(aiReportProvider.notifier).generate() : null,
              icon: const Icon(Icons.refresh),
              label: Text(label),
            ),
        ],
      ),
    );
  }
}

enum _MonthMetric { distance, gain, count }

class _TotalsCard extends StatefulWidget {
  const _TotalsCard({required this.insights});

  final HikeInsights insights;

  @override
  State<_TotalsCard> createState() => _TotalsCardState();
}

class _TotalsCardState extends State<_TotalsCard> {
  _MonthMetric _metric = _MonthMetric.distance;

  @override
  Widget build(BuildContext context) {
    final i = widget.insights;
    final values = [
      for (final m in i.months)
        switch (_metric) {
          _MonthMetric.distance => m.distanceM / 1000,
          _MonthMetric.gain => m.gainM,
          _MonthMetric.count => m.count.toDouble(),
        },
    ];
    String fmt(double v) => switch (_metric) {
          _MonthMetric.distance => v.toStringAsFixed(v >= 10 ? 0 : 1),
          _MonthMetric.gain => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}',
          _MonthMetric.count => '${v.round()}',
        };

    return _Card(
      title: '누적 기록',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SummaryStat(label: '산행', value: '${i.count}회')),
              Expanded(child: SummaryStat(label: '거리', value: formatDistance(i.distanceM))),
              Expanded(child: SummaryStat(label: '상승 고도', value: '${i.gainM.round()} m')),
            ],
          ),
          const SizedBox(height: 6),
          Text('총 ${formatDuration(i.duration)} 동안 걸었어요', style: _muted),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('최근 12개월', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              SegmentedButton<_MonthMetric>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: _MonthMetric.distance, label: Text('km')),
                  ButtonSegment(value: _MonthMetric.gain, label: Text('상승')),
                  ButtonSegment(value: _MonthMetric.count, label: Text('횟수')),
                ],
                selected: {_metric},
                onSelectionChanged: (s) => setState(() => _metric = s.first),
              ),
            ],
          ),
          const SizedBox(height: 10),
          BarChart(
            values: values,
            labels: [for (final m in i.months) '${m.month.month}'],
            format: fmt,
          ),
        ],
      ),
    );
  }
}

class _RestCard extends StatelessWidget {
  const _RestCard({required this.insights});

  final HikeInsights insights;

  @override
  Widget build(BuildContext context) {
    final ratio = insights.movingRatio;
    return _Card(
      title: '이동 vs 휴식',
      footnote: '30m 안에 3분 이상 머문 때를 휴식 1회로 셉니다.',
      child: ratio == null
          ? const Text('아직 계산할 기록이 없어요.', style: _muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: (ratio * 1000).round(),
                        child: Container(height: 14, color: BiviColors.forestLight),
                      ),
                      Expanded(
                        flex: ((1 - ratio) * 1000).round(),
                        child: Container(height: 14, color: BiviColors.amber.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '이동 ${(ratio * 100).round()}% · 휴식 ${(100 - ratio * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '산행 한 번에 평균 ${insights.restsPerHike!.toStringAsFixed(1)}번 쉬고'
                  '${insights.avgRest == null ? '' : ', 한 번에 ${formatDuration(insights.avgRest!)}쯤 쉬어요'}.',
                  style: _muted,
                ),
              ],
            ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.insights});

  final HikeInsights insights;

  @override
  Widget build(BuildContext context) {
    final pts = insights.weightPoints;
    final fit = insights.weightFit;
    String summary;
    if (fit == null) {
      summary = '배낭 무게가 1kg 이상 다른 기록이 3개 이상 쌓이면 추세를 보여드려요.';
    } else {
      final pct = insights.packPctPerKg!;
      summary = pct.abs() < 1
          ? '지금까지는 배낭 무게에 따른 속도 차이가 거의 없어요 (기록 ${fit.n}개).'
          : '배낭이 1kg 무거워질 때마다 약 ${pct.abs().toStringAsFixed(0)}% '
              '${pct < 0 ? '느려지는' : '빨라지는'} 경향이에요 (기록 ${fit.n}개 — 적으면 우연일 수 있어요).';
    }
    return _Card(
      title: '배낭 무게와 속도',
      footnote: '세로축은 노력 속도(노력거리 ÷ 이동 시간). 배낭 무게는 산행 시작 때 패킹 무게예요.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pts.isNotEmpty)
            ScatterChart(
              points: [for (final p in pts) (p.kg, p.effortKmh)],
              xLabel: '배낭 kg',
              yLabel: '노력 km/h',
              fit: fit,
            ),
          const SizedBox(height: 6),
          Text(summary, style: _muted),
        ],
      ),
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({required this.insights});

  final HikeInsights insights;

  @override
  Widget build(BuildContext context) {
    final pts = insights.ratingPoints;
    return _Card(
      title: '상승 고도와 체감 난이도',
      child: pts.isEmpty
          ? const Text('하산 완료 때 체감 난이도(별점)를 남기면 여기에 모여요.', style: _muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScatterChart(
                  points: [for (final (g, r) in pts) (g, r.toDouble())],
                  xLabel: '상승 m',
                  yLabel: '별점',
                  yRange: (1, 5),
                  yTicks: 1,
                  height: 160,
                ),
                const SizedBox(height: 8),
                for (final MapEntry(key: star, value: (avg, n)) in insights.gainByRating.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        StarRatingView(value: star),
                        const SizedBox(width: 8),
                        SizedBox(width: 64, child: Text(difficultyLabels[star - 1], style: _muted)),
                        Expanded(
                          child: Text('평균 상승 ${avg.round()} m · $n회',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Personal time estimate for the loaded GPX route, or a distance/climb typed in.
class _NextCourseCard extends ConsumerStatefulWidget {
  const _NextCourseCard({required this.pace});

  final PaceModel? pace;

  @override
  ConsumerState<_NextCourseCard> createState() => _NextCourseCardState();
}

class _NextCourseCardState extends ConsumerState<_NextCourseCard> {
  final _km = TextEditingController();
  final _gain = TextEditingController();

  @override
  void dispose() {
    _km.dispose();
    _gain.dispose();
    super.dispose();
  }

  Widget _estimate(PaceModel pace, double distanceM, double gainM) {
    final moving = pace.movingFor(distanceM, gainM);
    final rest = pace.restFor(moving);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('약 ${formatDuration(moving + rest)}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Text('이동 ${formatDuration(moving)} + 휴식 ${formatDuration(rest)}', style: _muted),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pace = widget.pace;
    final route = ref.watch(gpxProvider).route;
    final km = double.tryParse(_km.text.trim());
    final gain = double.tryParse(_gain.text.trim()) ?? 0;

    return _Card(
      title: '다음 코스 예상 소요 시간',
      footnote: pace == null
          ? null
          : '최근 기록 ${pace.basedOn}개 기준 · 노력거리 1km 에 ${formatDuration(Duration(seconds: pace.secPerEffortKm.round()))}'
              ' · 이동 1시간당 휴식 ${(pace.restRatio * 60).round()}분',
      child: pace == null
          ? const Text('거리 500m · 이동 10분 이상인 기록이 1개 이상 있으면 계산해요.', style: _muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (route != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.route, size: 18, color: BiviColors.forestLight),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(route.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  Text('${formatDistance(route.totalMeters)} · 상승 ${route.elevationGain.round()} m', style: _muted),
                  const SizedBox(height: 6),
                  _estimate(pace, route.totalMeters, route.elevationGain),
                  const Divider(height: 28),
                ],
                Text(route == null ? '거리와 상승 고도를 넣어 보세요' : '다른 코스 직접 입력',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _km,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '거리', suffixText: 'km'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _gain,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '상승 고도', suffixText: 'm'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (km != null && km > 0) ...[
                  const SizedBox(height: 10),
                  _estimate(pace, km * 1000, gain),
                ],
              ],
            ),
    );
  }
}
