import 'dart:convert';
import 'dart:io';

import 'package:bivi/data/hike_record_store.dart';
import 'package:bivi/models/hike_record.dart';
import 'package:bivi/models/trip.dart';
import 'package:bivi/providers/core_providers.dart';
import 'package:bivi/providers/records_provider.dart';
import 'package:bivi/providers/safe_trip_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hike_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bivi_records_test');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('HikeRecordStore', () {
    test('active track appends, skips a half-written line, and is discarded', () async {
      SharedPreferences.setMockInitialValues({});
      final store = HikeRecordStore(await SharedPreferences.getInstance(), dir);
      final b = TrackBuilder()..walk(300, 5, 10);

      await store.beginTrack();
      final pending = [for (final p in b.points.take(10)) store.appendPoint(p)]; // queued, kept in order
      await pending.last;
      // App killed mid-write, then restarted and still appending.
      await File('${dir.path}/active_track.jsonl').writeAsString('\n[37.1, 127', mode: FileMode.append);
      for (final p in b.points.skip(10)) {
        await store.appendPoint(p);
      }
      final read = await store.readActiveTrack();
      expect(read.length, b.points.length);
      expect([for (final p in read) p.time], [for (final p in b.points) p.time]);

      await store.discardActiveTrack();
      expect(await store.readActiveTrack(), isEmpty);
    });

    test('add / update / delete keep the index and track file in step', () async {
      SharedPreferences.setMockInitialValues({});
      final store = HikeRecordStore(await SharedPreferences.getInstance(), dir);
      final b = TrackBuilder()..walk(300, 5, 10);
      final older = fakeRecord(id: 'old', start: DateTime(2026, 9, 1));
      final newer = fakeRecord(id: 'new', start: DateTime(2026, 10, 1), place: '북한산');

      await store.add(older, b.points);
      await store.add(newer, b.points);
      expect([for (final r in store.loadAll()) r.id], ['new', 'old']);
      expect((await store.loadTrack('new')).length, b.points.length);

      final r = store.loadAll().first;
      await store.update(HikeRecord(
        id: r.id,
        startedAt: r.startedAt,
        endedAt: r.endedAt,
        stats: r.stats,
        place: '북한산 백운대',
        rating: 4,
      ));
      expect(store.loadAll().first.place, '북한산 백운대');
      expect(store.loadAll().first.rating, 4);

      await store.delete('new');
      expect([for (final r in store.loadAll()) r.id], ['old']);
      expect(await File('${dir.path}/new.json').exists(), isFalse);
    });
  });

  test('SafeTripState keeps pack weight and followed route across restarts', () {
    final s = SafeTripState(
      active: true,
      startedAt: DateTime(2026, 10, 3, 8),
      packWeightGrams: 7400,
      followedRoute: const PlannedRoute(name: '백운대 코스', distanceM: 6200, gainM: 640),
    );
    final back = SafeTripState.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.packWeightGrams, 7400);
    expect(back.followedRoute!.name, '백운대 코스');
    expect(back.followedRoute!.gainM, 640);
  });

  test('finishing a restored hike saves a record from the active track', () async {
    final b = TrackBuilder()
      ..walk(2000, 40, 400)
      ..rest(10)
      ..walk(2000, 30, -400);
    final start = b.points.first.time;
    final end = b.points.last.time;
    SharedPreferences.setMockInitialValues({
      'safe_trip_v1': jsonEncode(SafeTripState(
        active: true,
        startedAt: start,
        targetTime: end.add(const Duration(hours: 2)),
        packWeightGrams: 8200,
        followedRoute: const PlannedRoute(name: '백운대 코스', distanceM: 4100, gainM: 420),
      ).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = HikeRecordStore(prefs, dir);
    await store.beginTrack();
    for (final p in b.points) {
      await store.appendPoint(p);
    }

    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      recordsDirProvider.overrideWithValue(dir),
    ]);
    addTearDown(container.dispose);
    expect(container.read(safeTripProvider).active, isTrue);
    final notifier = container.read(safeTripProvider.notifier);

    final preview = await notifier.previewFinish(end);
    expect(preview.suggestedPlace, '백운대 코스');
    expect(preview.stats.distanceM, closeTo(4000, 120));
    expect(preview.pointCount, b.points.length);

    final record = await notifier.finish(
      save: true,
      end: end,
      place: ' 북한산 백운대 ',
      rating: 3,
      memo: '정상 바람 강함',
      route: container.read(safeTripProvider).followedRoute,
    );
    expect(record, isNotNull);
    expect(record!.place, '북한산 백운대');
    expect(record.packWeightGrams, 8200);
    expect(record.route!.name, '백운대 코스');
    expect(record.stats.restCount, 1);
    expect(record.duration, end.difference(start));

    expect(container.read(safeTripProvider).active, isFalse);
    expect(container.read(hikeRecordsProvider).single.id, record.id);
    expect((await container.read(hikeRecordStoreProvider).loadTrack(record.id)).length, b.points.length);
    expect(await File('${dir.path}/active_track.jsonl').exists(), isFalse);
  });

  test('records saved by the old analysis are recomputed from their track (gap kept out)', () async {
    final b = TrackBuilder()
      ..walk(1000, 20, 0)
      ..jump(12000, 240)
      ..walk(1000, 20, 0);
    final start = b.points.first.time, end = b.points.last.time;
    // What version 1 saved for such a track: the whole gap as moving time, no version field.
    final old = HikeRecord(id: 'old', startedAt: start, endedAt: end, place: '판교', rating: 3,
        stats: const HikeStats(distanceM: 14000, movingSec: 280 * 60)).toJson()
      ..remove('stats_version');
    SharedPreferences.setMockInitialValues({'hike_records_v1': jsonEncode([old])});
    final prefs = await SharedPreferences.getInstance();
    final store = HikeRecordStore(prefs, dir);
    await dir.create(recursive: true);
    await File('${dir.path}/old.json').writeAsString(jsonEncode([for (final p in b.points) p.toJson()]));
    expect(store.loadAll().single.statsVersion, 1);

    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      recordsDirProvider.overrideWithValue(dir),
    ]);
    addTearDown(container.dispose);
    container.read(hikeRecordsProvider);
    await container.read(hikeRecordsProvider.notifier).upgradeOldStats();

    final r = container.read(hikeRecordsProvider).single;
    expect(r.statsVersion, hikeStatsVersion);
    expect(r.stats.gapCount, 1);
    expect(r.stats.distanceM, closeTo(2000, 80));
    expect(r.stats.movingSec, closeTo(40 * 60, 60));
    expect(r.place, '판교'); // user input is kept
    expect(r.rating, 3);
  });

  test('restoring a hike after the app was closed for a while says what was missed', () async {
    final last = DateTime.now().subtract(const Duration(hours: 1));
    SharedPreferences.setMockInitialValues({
      'safe_trip_v1': jsonEncode(SafeTripState(active: true, startedAt: last).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = HikeRecordStore(prefs, dir);
    await store.beginTrack();
    await store.appendPoint(TrackPoint(lat: 37.4, lng: 127.1, alt: 100, accuracy: 8, time: last));

    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      recordsDirProvider.overrideWithValue(dir),
    ]);
    addTearDown(container.dispose);
    final messages = <String>[];
    container.listen<String?>(safeTripProvider.select((s) => s.message), (_, m) {
      if (m != null) messages.add(m);
    });
    await Future<void>.delayed(const Duration(milliseconds: 2600)); // resume waits 2 s
    expect(messages.any((m) => m.contains('동안 위치가 기록되지 않았어요')), isTrue, reason: '$messages');
  });

  test('finishing without saving leaves no record and clears the track', () async {
    SharedPreferences.setMockInitialValues({
      'safe_trip_v1': jsonEncode(SafeTripState(active: true, startedAt: DateTime(2026, 10, 3, 8)).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = HikeRecordStore(prefs, dir);
    await store.beginTrack();
    await store.appendPoint((TrackBuilder()..walk(30, 1, 0)).points.first);

    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      recordsDirProvider.overrideWithValue(dir),
    ]);
    addTearDown(container.dispose);
    container.read(safeTripProvider);
    final record = await container.read(safeTripProvider.notifier).finish(save: false);

    expect(record, isNull);
    expect(container.read(hikeRecordsProvider), isEmpty);
    expect(container.read(safeTripProvider).active, isFalse);
    expect(await store.readActiveTrack(), isEmpty);
  });
}
