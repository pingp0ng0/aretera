import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../models/campsite.dart';
import '../models/gear_item.dart';
import '../models/trip.dart';
import 'seed_data.dart';

List<Campsite> _parseCampsites(String raw) => (jsonDecode(raw) as List)
    .map((e) => Campsite.fromJson(e as Map<String, dynamic>))
    .toList();

/// 합법 야영지: Supabase → 로컬 캐시 → 앱 번들(assets/data/campsites.json) → 시드 순으로 폴백.
/// 번들이 있어 산속 오프라인 첫 실행에서도 핀이 뜬다.
class CampsiteRepository {
  CampsiteRepository(this.prefs, this.client);

  static const _cacheKey = 'campsites_cache_v2';
  static const _bundleAsset = 'assets/data/campsites.json';

  /// Review-based spots (personal use, PRD_step2). Always bundled, never synced.
  static const _reviewAsset = 'assets/data/blog_spots.json';
  static const _pageSize = 1000; // PostgREST 기본 최대 행 수
  final SharedPreferences prefs;
  final SupabaseClient? client;

  Future<List<Campsite>> fetchAll() async {
    final registered = await _fetchRegistered();
    try {
      final reviews = await compute(_parseCampsites, await rootBundle.loadString(_reviewAsset));
      return [...registered, ...reviews];
    } catch (e) {
      debugPrint('review spots unavailable: $e');
      return registered;
    }
  }

  Future<List<Campsite>> _fetchRegistered() async {
    final c = client;
    if (c != null) {
      try {
        final rows = <Map<String, dynamic>>[];
        for (var from = 0;; from += _pageSize) {
          final page = await c.from('campsites').select().order('id').range(from, from + _pageSize - 1);
          rows.addAll(page);
          if (page.length < _pageSize) break;
        }
        if (rows.isNotEmpty) {
          final list = rows.map(Campsite.fromJson).toList();
          await prefs.setString(_cacheKey, jsonEncode(rows));
          return list;
        }
      } catch (e) {
        debugPrint('campsites fetch failed, falling back to cache: $e');
      }
    }
    final cached = prefs.getString(_cacheKey);
    if (cached != null) return compute(_parseCampsites, cached);
    try {
      return await compute(_parseCampsites, await rootBundle.loadString(_bundleAsset));
    } catch (e) {
      debugPrint('bundled campsites missing: $e');
      return seedCampsites;
    }
  }
}

/// 내 장비: 로컬 우선 저장. Supabase 로그인 세션이 있으면 백그라운드로 upsert.
class GearRepository {
  GearRepository(this.prefs, this.client);

  static const _key = 'my_gear_v1';
  final SharedPreferences prefs;
  final SupabaseClient? client;

  List<GearItem> loadLocal() {
    final raw = prefs.getString(_key);
    if (raw == null) {
      final seed = buildSeedGear();
      saveLocal(seed);
      return seed;
    }
    return (jsonDecode(raw) as List)
        .map((e) => GearItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveLocal(List<GearItem> items) =>
      prefs.setString(_key, jsonEncode([for (final g in items) g.toJson()]));

  static const _categoriesKey = 'gear_categories_v1';

  /// User-editable categories (device only). First run gets the built-in set.
  List<GearCategory> loadCategories() {
    final raw = prefs.getString(_categoriesKey);
    if (raw == null) return [...defaultGearCategories];
    return (jsonDecode(raw) as List)
        .map((e) => GearCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCategories(List<GearCategory> categories) =>
      prefs.setString(_categoriesKey, jsonEncode([for (final c in categories) c.toJson()]));

  Future<void> upsertRemote(List<GearItem> items) async {
    final c = client;
    final user = c?.auth.currentUser;
    // Anonymous accounts can't be recovered after a reinstall, so syncing them backs up nothing (PRD_step6).
    if (c == null || user == null || user.isAnonymous || items.isEmpty) return;
    try {
      await c.from('my_gear').upsert([
        for (final g in items) {...g.toJson(), 'user_id': user.id},
      ]);
    } catch (e) {
      debugPrint('my_gear sync failed (will retry on next change): $e');
    }
  }

  Future<void> deleteRemote(String id) async {
    final c = client;
    final user = c?.auth.currentUser;
    if (c == null || user == null || user.isAnonymous) return;
    try {
      await c.from('my_gear').delete().eq('id', id);
    } catch (e) {
      debugPrint('my_gear delete failed: $e');
    }
  }
}

/// 산행 상태 · 마지막 GPS 좌표 · 의료 정보 — 전부 기기 로컬에만 저장 (오프라인 SOS 용)
class SafeTripStore {
  SafeTripStore(this.prefs);

  static const _tripKey = 'safe_trip_v1';
  static const _positionKey = 'last_position_v1';
  static const _medicalKey = 'medical_info_v1';
  final SharedPreferences prefs;

  SafeTripState load() {
    final raw = prefs.getString(_tripKey);
    final base = raw == null
        ? const SafeTripState()
        : SafeTripState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return base.copyWith(lastPosition: loadPosition());
  }

  Future<void> save(SafeTripState s) => prefs.setString(_tripKey, jsonEncode(s.toJson()));

  CachedPosition? loadPosition() {
    final raw = prefs.getString(_positionKey);
    return raw == null ? null : CachedPosition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> savePosition(CachedPosition p) =>
      prefs.setString(_positionKey, jsonEncode(p.toJson()));

  MedicalInfo loadMedical() {
    final raw = prefs.getString(_medicalKey);
    return raw == null
        ? const MedicalInfo()
        : MedicalInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveMedical(MedicalInfo m) => prefs.setString(_medicalKey, jsonEncode(m.toJson()));
}
