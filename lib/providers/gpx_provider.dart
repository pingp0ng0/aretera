import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gpx_route.dart';
import 'core_providers.dart';

class GpxState {
  const GpxState({this.route, this.tilesDone = 0, this.tilesTotal = 0, this.tilesSaved = 0, this.message});

  final GpxRoute? route;

  /// 경로 주변 오프라인 지도 저장 진행 상황
  final int tilesDone;
  final int tilesTotal;
  final int tilesSaved;
  final String? message;

  bool get prefetching => tilesTotal > 0 && tilesDone < tilesTotal;
}

final gpxProvider = NotifierProvider<GpxNotifier, GpxState>(GpxNotifier.new);

/// 불러온 GPX 경로 1개를 기기에 보관한다 (오프라인에서도 따라가기 가능)
class GpxNotifier extends Notifier<GpxState> {
  static const _key = 'gpx_route_v1';

  @override
  GpxState build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    if (raw == null) return const GpxState();
    try {
      return GpxState(route: GpxRoute.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    } catch (e) {
      debugPrint('stored gpx unreadable: $e');
      return const GpxState();
    }
  }

  /// 파일 선택 → 파싱 → 저장 → 경로 주변 지도 타일 프리패치
  Future<void> importFromPicker() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    if (file.extension?.toLowerCase() != 'gpx') {
      state = GpxState(route: state.route, message: 'GPX 파일(.gpx)만 불러올 수 있습니다.');
      return;
    }

    final GpxRoute route;
    try {
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final fallbackName = file.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), '');
      // 수만 포인트 GPX 도 UI 가 멈추지 않도록 백그라운드 isolate 에서 파싱
      route = await compute((String s) => GpxRoute.parse(s, fallbackName: fallbackName), text);
    } catch (e) {
      state = GpxState(route: state.route, message: 'GPX 를 읽지 못했습니다: $e');
      return;
    }

    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(route.toJson()));
    state = GpxState(route: route, message: '"${route.name}" 경로를 불러왔습니다.');
    await _prefetch(route);
  }

  Future<void> retryPrefetch() async {
    final route = state.route;
    if (route != null) await _prefetch(route);
  }

  Future<void> clear() async {
    await ref.read(sharedPrefsProvider).remove(_key);
    state = const GpxState();
  }

  Future<void> _prefetch(GpxRoute route) async {
    final saved = await ref.read(tileCacheProvider).prefetchAlong(
      [for (final p in route.points) (p.lat, p.lng)],
      onProgress: (done, total) {
        if (done % 10 == 0 || done == total) {
          state = GpxState(route: route, tilesDone: done, tilesTotal: total, tilesSaved: state.tilesSaved);
        }
      },
    );
    state = GpxState(route: route, tilesDone: state.tilesTotal, tilesTotal: state.tilesTotal, tilesSaved: saved);
  }
}
