import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hike_record.dart';

/// Hike records, device only (PRD_step5).
///
/// - Summaries (no track) live in SharedPreferences so the list and stats load fast.
/// - Each track is its own file `<dir>/<id>.json`, read only by the detail screen.
/// - The hike in progress is appended line by line to `<dir>/active_track.jsonl`
///   so nothing is lost if the app is killed mid-hike.
class HikeRecordStore {
  HikeRecordStore(this.prefs, this.dir);

  static const _indexKey = 'hike_records_v1';
  final SharedPreferences prefs;
  final Directory dir;

  File get _activeFile => File('${dir.path}/active_track.jsonl');
  File _trackFile(String id) => File('${dir.path}/$id.json');

  /// Serialises appends so lines never interleave.
  Future<void> _appendQueue = Future.value();

  /// Newest first.
  List<HikeRecord> loadAll() {
    final raw = prefs.getString(_indexKey);
    if (raw == null) return [];
    final list = <HikeRecord>[];
    for (final e in jsonDecode(raw) as List) {
      try {
        list.add(HikeRecord.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('skipping unreadable hike record: $err');
      }
    }
    return list..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  Future<void> _saveIndex(List<HikeRecord> records) =>
      prefs.setString(_indexKey, jsonEncode([for (final r in records) r.toJson()]));

  // ───────── hike in progress ─────────

  /// Starts an empty track for a new hike.
  Future<void> beginTrack() async {
    await _appendQueue;
    await dir.create(recursive: true);
    await _activeFile.writeAsString('');
  }

  Future<void> appendPoint(TrackPoint p) {
    // Leading newline: if the app died mid-write, the broken line stays on its own and is skipped.
    final line = '\n${jsonEncode(p.toJson())}';
    return _appendQueue = _appendQueue.then((_) async {
      try {
        await dir.create(recursive: true);
        await _activeFile.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (e) {
        debugPrint('track append failed: $e');
      }
    });
  }

  /// Points of the hike in progress. A half-written last line (app killed) is skipped.
  Future<List<TrackPoint>> readActiveTrack() async {
    await _appendQueue;
    if (!await _activeFile.exists()) return [];
    final points = <TrackPoint>[];
    for (final line in await _activeFile.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        points.add(TrackPoint.fromJson(jsonDecode(line) as List));
      } catch (_) {}
    }
    return points;
  }

  Future<void> discardActiveTrack() async {
    await _appendQueue;
    if (await _activeFile.exists()) await _activeFile.delete();
  }

  // ───────── saved records ─────────

  /// Writes the track file first, then adds the summary, so the list never points at a missing track.
  Future<void> add(HikeRecord record, List<TrackPoint> track) async {
    await dir.create(recursive: true);
    await _trackFile(record.id)
        .writeAsString(jsonEncode([for (final p in track) p.toJson()]), flush: true);
    await _saveIndex([record, ...loadAll().where((r) => r.id != record.id)]);
  }

  Future<List<TrackPoint>> loadTrack(String id) async {
    final f = _trackFile(id);
    if (!await f.exists()) return [];
    return [for (final p in jsonDecode(await f.readAsString()) as List) TrackPoint.fromJson(p as List)];
  }

  /// Updates the summary only (place, rating, memo).
  Future<void> update(HikeRecord record) =>
      _saveIndex([for (final r in loadAll()) if (r.id == record.id) record else r]);

  Future<void> delete(String id) async {
    await _saveIndex(loadAll().where((r) => r.id != id).toList());
    final f = _trackFile(id);
    if (await f.exists()) await f.delete();
  }
}
