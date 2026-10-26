import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hike_record.dart';
import '../providers/gpx_provider.dart';
import '../providers/safe_trip_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/mascot.dart';
import '../widgets/star_rating.dart';
import '../widgets/summary_stat.dart';
import '../widgets/topo.dart';
import 'home_shell.dart';
import 'record_detail_screen.dart';

/// "하산 완료": review the hike, add place / difficulty / memo, then save or discard (PRD_step5).
/// Closing the screen keeps the hike going.
class FinishTripScreen extends ConsumerStatefulWidget {
  const FinishTripScreen({super.key});

  @override
  ConsumerState<FinishTripScreen> createState() => _FinishTripScreenState();
}

class _FinishTripScreenState extends ConsumerState<FinishTripScreen> {
  /// The hike ends when this screen opens, not when the form is submitted.
  final _end = DateTime.now();
  final _place = TextEditingController();
  final _memo = TextEditingController();
  HikeFinishPreview? _preview;
  int? _rating;
  late bool _includeRoute = ref.read(safeTripProvider).followedRoute != null;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(safeTripProvider.notifier).previewFinish(_end).then((p) {
      if (!mounted) return;
      setState(() {
        _preview = p;
        if (_place.text.isEmpty) _place.text = p.suggestedPlace;
      });
    });
  }

  @override
  void dispose() {
    _place.dispose();
    _memo.dispose();
    super.dispose();
  }

  /// The route to attach: the one followed during the hike, else the loaded GPX (off by default).
  PlannedRoute? _routeCandidate() {
    final followed = ref.read(safeTripProvider).followedRoute;
    if (followed != null) return followed;
    final gpx = ref.read(gpxProvider).route;
    return gpx == null
        ? null
        : PlannedRoute(name: gpx.name, distanceM: gpx.totalMeters, gainM: gpx.elevationGain);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // The snackbar outlives this screen, so don't touch `ref` from its action.
    final tab = ref.read(homeTabProvider.notifier);
    try {
      final record = await ref.read(safeTripProvider.notifier).finish(
            save: true,
            end: _end,
            place: _place.text,
            rating: _rating,
            memo: _memo.text,
            route: _includeRoute ? _routeCandidate() : null,
          );
      navigator.pop();
      if (record == null) return;
      messenger.showSnackBar(SnackBar(
        content: Text('"${record.displayPlace}" 기록을 저장했어요'),
        action: SnackBarAction(
          label: '보기',
          onPressed: () {
            tab.state = recordsTabIndex;
            navigator.push(MaterialPageRoute(builder: (_) => RecordDetailScreen(recordId: record.id)));
          },
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('기록을 저장하지 못했습니다: $e')));
    }
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록 없이 종료할까요?'),
        content: const Text('이번 산행의 이동 경로와 입력한 내용이 저장되지 않습니다. '
            '마지막 좌표는 SOS 카드에 계속 남아 있습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('기록 없이 종료')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await ref.read(safeTripProvider.notifier).finish(save: false);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final packGrams = ref.watch(safeTripProvider.select((s) => s.packWeightGrams));
    final route = _routeCandidate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('산행 완료'),
        leading: IconButton(
          tooltip: '계속 산행',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: preview == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Summary(preview: preview),
                const SizedBox(height: 20),
                TextField(
                  controller: _place,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '장소',
                    hintText: '예: 북한산 백운대',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('체감 난이도', style: TextStyle(fontWeight: FontWeight.w700)),
                StarRatingInput(value: _rating, onChanged: (v) => setState(() => _rating = v)),
                const SizedBox(height: 12),
                TextField(
                  controller: _memo,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '메모',
                    hintText: '길 상태, 물 보충, 다음에 챙길 것…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                if (route != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _includeRoute,
                    onChanged: (v) => setState(() => _includeRoute = v),
                    title: const Text('GPX 경로를 따라갔어요'),
                    subtitle: Text('${route.name} · ${formatDistance(route.distanceM)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                if (packGrams != null && packGrams > 0)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.backpack_outlined, color: BiviColors.forestLight),
                    title: Text('배낭 ${formatKg(packGrams)} kg'),
                    subtitle: const Text('산행 시작 때 "내 배낭"에 패킹된 무게'),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: BiviColors.forest,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('기록 저장하고 종료'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _discard,
                  child: const Text('기록 없이 종료', style: TextStyle(color: BiviColors.textSecondary)),
                ),
              ],
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.preview});

  final HikeFinishPreview preview;

  @override
  Widget build(BuildContext context) {
    final s = preview.stats;
    return TopoCard(
      seed: 7,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('수고했어요!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                      '${formatDateWeekday(preview.startedAt)} '
                      '${formatTime(preview.startedAt)} – ${formatTime(preview.endedAt)}',
                      style: const TextStyle(color: BiviColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const MascotImage(Mascot.happy, height: 64),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: SummaryStat(label: '소요 시간', value: formatDuration(preview.duration))),
              Expanded(child: SummaryStat(label: '거리', value: formatDistance(s.distanceM))),
              Expanded(child: SummaryStat(label: '상승 고도', value: '${s.gainM.round()} m')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '이동 ${formatDuration(s.moving)} · 휴식 ${formatDuration(s.rest)} (${s.restCount}회)',
            style: const TextStyle(color: BiviColors.textSecondary),
          ),
          if (s.gapSec > 0) ...[
            const SizedBox(height: 8),
            Text(
              '위치 기록이 끊긴 시간 ${formatDuration(s.gap)}(${s.gapCount}번) — 거리·이동 시간에서 뺐어요.',
              style: const TextStyle(color: BiviColors.amber, height: 1.4),
            ),
          ],
          if (preview.pointCount < 2) ...[
            const SizedBox(height: 8),
            const Text(
              '저장된 위치가 거의 없어 거리·고도가 0으로 기록될 수 있어요.',
              style: TextStyle(color: BiviColors.amber, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
