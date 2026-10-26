import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../models/hike_record.dart';
import '../providers/records_provider.dart';
import '../providers/report_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/mascot.dart';
import '../widgets/star_rating.dart';
import '../widgets/topo.dart';
import 'home_shell.dart';
import 'insights_view.dart';
import 'record_detail_screen.dart';

/// Tab 4: 기록 — saved hikes and their statistics (PRD_step5).
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(hikeRecordsProvider);
    final empty = EmptyState(
      icon: Icons.insights_outlined,
      illustration: const MascotImage(Mascot.viewing, height: 150),
      title: '아직 산행 기록이 없어요',
      message: '산행 모드에서 "산행 시작"을 누르고\n하산 완료 때 저장하면 여기에 쌓여요.',
      action: OutlinedButton.icon(
        onPressed: () => ref.read(homeTabProvider.notifier).state = 2,
        icon: const Icon(Icons.hiking),
        label: const Text('산행 모드로 가기'),
      ),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('기록'),
          actions: [
            if (Env.demoRecords)
              PopupMenuButton<bool>(
                tooltip: '데모 기록',
                icon: const Icon(Icons.science_outlined),
                onSelected: (add) async {
                  if (add) return ref.read(hikeRecordsProvider.notifier).addDemo();
                  await ref.read(hikeRecordsProvider.notifier).removeDemo();
                  // A report made while demo hikes existed is demo-based too.
                  await ref.read(aiReportProvider.notifier).clear();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('데모 기록 추가')),
                  PopupMenuItem(value: false, child: Text('데모 기록 모두 삭제')),
                ],
              ),
          ],
          bottom: const TabBar(
            indicatorColor: BiviColors.forestLight,
            labelColor: BiviColors.textPrimary,
            unselectedLabelColor: BiviColors.textSecondary,
            tabs: [Tab(text: '목록'), Tab(text: '분석')],
          ),
        ),
        body: TabBarView(
          children: [
            if (records.isEmpty) empty else _RecordList(records: records),
            if (records.isEmpty) empty else const InsightsView(),
          ],
        ),
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.records});

  final List<HikeRecord> records;

  @override
  Widget build(BuildContext context) {
    // Newest first, with a header whenever the month changes.
    final items = <Widget>[];
    String? month;
    for (final r in records) {
      final m = '${r.startedAt.year}년 ${r.startedAt.month}월';
      if (m != month) {
        month = m;
        items.add(Padding(
          padding: EdgeInsets.fromLTRB(4, items.isEmpty ? 4 : 16, 4, 8),
          child: Text(m, style: const TextStyle(color: BiviColors.textSecondary, fontWeight: FontWeight.w700)),
        ));
      }
      items.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: _RecordTile(record: r)));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: items);
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final HikeRecord record;

  @override
  Widget build(BuildContext context) {
    final s = record.stats;
    return Material(
      color: BiviColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RecordDetailScreen(recordId: record.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${formatDateWeekday(record.startedAt)} ${formatTime(record.startedAt)}',
                    style: const TextStyle(color: BiviColors.textSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  if (record.rating != null) StarRatingView(value: record.rating!),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                record.displayPlace,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _Fact(icon: Icons.schedule, text: formatDuration(record.duration)),
                  _Fact(icon: Icons.straighten, text: formatDistance(s.distanceM)),
                  _Fact(icon: Icons.terrain, text: '+${s.gainM.round()} m'),
                  if (record.route != null) const _Fact(icon: Icons.route, text: 'GPX'),
                  if (s.gapSec > 0) const _Fact(icon: Icons.link_off, text: '기록 끊김', color: BiviColors.amber),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.color = BiviColors.forestLight});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
