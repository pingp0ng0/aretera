import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_records.dart';
import '../data/hike_record_store.dart';
import '../models/hike_record.dart';
import '../services/hike_analysis.dart';
import '../services/hike_insights.dart';
import 'core_providers.dart';

final hikeRecordStoreProvider = Provider(
  (ref) => HikeRecordStore(ref.watch(sharedPrefsProvider), ref.watch(recordsDirProvider)),
);

/// Saved hikes, newest first (summaries only).
final hikeRecordsProvider =
    NotifierProvider<HikeRecordsNotifier, List<HikeRecord>>(HikeRecordsNotifier.new);

class HikeRecordsNotifier extends Notifier<List<HikeRecord>> {
  @override
  List<HikeRecord> build() {
    final records = ref.watch(hikeRecordStoreProvider).loadAll();
    if (records.any((r) => r.statsVersion < hikeStatsVersion)) Future.microtask(upgradeOldStats);
    return records;
  }

  HikeRecordStore get _store => ref.read(hikeRecordStoreProvider);

  Future<void>? _upgrading;

  /// Recomputes the numbers of records saved by an older analysis from their tracks (PRD_step5 5-5).
  /// Place, rating, memo and the track itself are kept. Runs once; later calls wait for that run.
  Future<void> upgradeOldStats() => _upgrading ??= _upgrade();

  Future<void> _upgrade() async {
    final store = _store;
    for (final r in store.loadAll().where((r) => r.statsVersion < hikeStatsVersion)) {
      try {
        final track = await store.loadTrack(r.id);
        await store.update(r.withStats(analyzeTrack(track, start: r.startedAt, end: r.endedAt)));
      } catch (e) {
        debugPrint('could not recompute ${r.id}: $e');
      }
    }
    state = store.loadAll();
  }

  Future<void> add(HikeRecord record, List<TrackPoint> track) async {
    await _store.add(record, track);
    state = _store.loadAll();
  }

  Future<void> update(HikeRecord record) async {
    await _store.update(record);
    state = _store.loadAll();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    state = _store.loadAll();
    ref.invalidate(hikeTrackProvider(id));
  }

  /// Demo builds only (Env.demoRecords).
  Future<void> addDemo() async {
    for (final (record, track) in buildDemoHikes(DateTime.now())) {
      await _store.add(record, track);
    }
    state = _store.loadAll();
  }

  Future<void> removeDemo() async {
    for (final r in state.where((r) => r.id.startsWith(demoIdPrefix)).toList()) {
      await _store.delete(r.id);
    }
    state = _store.loadAll();
  }
}

/// Full track of one saved hike (detail screen).
final hikeTrackProvider = FutureProvider.autoDispose.family<List<TrackPoint>, String>(
  (ref, id) => ref.read(hikeRecordStoreProvider).loadTrack(id),
);

final hikeInsightsProvider = Provider<HikeInsights>(
  (ref) => HikeInsights.from(ref.watch(hikeRecordsProvider)),
);
