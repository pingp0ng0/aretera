import 'dart:io';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';

/// 산행 시작 시 현재 위치 주변 지형도 타일 일부를 기기에 저장한다.
///
/// MVP 프로토타입용 구현입니다. Mapbox 타일을 프로덕션에서 오프라인 저장하려면
/// 약관상 Mapbox SDK 의 공식 오프라인(TileStore) 기능으로 교체해야 합니다.
class OfflineTileCache {
  OfflineTileCache(this.root);

  final Directory root;

  Directory get _sourceDir => Directory('${root.path}/${Env.tileSourceKey}');

  File fileFor(int z, int x, int y) => File('${_sourceDir.path}/$z/$x/$y.png');

  static (int x, int y) tileOf(double lat, double lng, int z) {
    final n = 1 << z;
    final latRad = lat * pi / 180;
    final x = ((lng + 180) / 360 * n).floor();
    final y = ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * n).floor();
    return (min(max(x, 0), n - 1), min(max(y, 0), n - 1));
  }

  String _url(int z, int x, int y) => Env.tileUrlTemplate
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  /// zoom → 중심 타일 기준 반경(타일 수). 기본값 기준 약 68장, 수 MB 수준.
  Future<int> prefetchAround(
    double lat,
    double lng, {
    Map<int, int> radiusByZoom = const {12: 1, 13: 1, 14: 2, 15: 2},
  }) async {
    final tiles = <(int, int, int)>{};
    for (final MapEntry(key: z, value: r) in radiusByZoom.entries) {
      final (cx, cy) = tileOf(lat, lng, z);
      for (var dx = -r; dx <= r; dx++) {
        for (var dy = -r; dy <= r; dy++) {
          tiles.add((z, cx + dx, cy + dy));
        }
      }
    }
    return _downloadAll(tiles);
  }

  /// GPX 경로를 따라 지나가는 타일(+이웃 1칸)을 저장. 산속 오프라인 따라가기용.
  /// 타일 수가 [maxTiles] 를 넘으면 높은 줌부터 덜어낸다.
  Future<int> prefetchAlong(
    Iterable<(double lat, double lng)> points, {
    List<int> zooms = const [11, 12, 13, 14, 15],
    int maxTiles = 900,
    void Function(int done, int total)? onProgress,
  }) async {
    var usable = [...zooms];
    Set<(int, int, int)> tiles;
    do {
      tiles = {};
      for (final z in usable) {
        final pad = z >= 14 ? 1 : 0;
        for (final (lat, lng) in points) {
          final (x, y) = tileOf(lat, lng, z);
          for (var dx = -pad; dx <= pad; dx++) {
            for (var dy = -pad; dy <= pad; dy++) {
              tiles.add((z, x + dx, y + dy));
            }
          }
        }
      }
      if (tiles.length <= maxTiles || usable.length == 1) break;
      usable = usable.sublist(0, usable.length - 1);
    } while (true);
    return _downloadAll(tiles, onProgress: onProgress);
  }

  Future<int> _downloadAll(
    Set<(int, int, int)> tiles, {
    void Function(int done, int total)? onProgress,
  }) async {
    final client = http.Client();
    var saved = 0, done = 0;
    try {
      for (final (z, x, y) in tiles) {
        if (await _download(client, z, x, y)) saved++;
        onProgress?.call(++done, tiles.length);
      }
    } finally {
      client.close();
    }
    return saved;
  }

  Future<bool> _download(http.Client client, int z, int x, int y) async {
    final file = fileFor(z, x, y);
    if (await file.exists()) return true;
    try {
      final res = await client
          .get(Uri.parse(_url(z, x, y)), headers: {'User-Agent': Env.userAgent})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(res.bodyBytes);
      return true;
    } catch (_) {
      return false; // 통신 음영 구간: 받을 수 있는 만큼만 저장
    }
  }
}

/// 캐시에 타일이 있으면 파일에서, 없으면 네트워크에서 불러오는 TileProvider.
class CachedTileProvider extends TileProvider {
  CachedTileProvider(this.cache);

  final OfflineTileCache cache;
  final NetworkTileProvider _network = NetworkTileProvider(headers: {'User-Agent': Env.userAgent});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final file = cache.fileFor(coordinates.z, coordinates.x, coordinates.y);
    if (file.existsSync()) return FileImage(file);
    return _network.getImage(coordinates, options);
  }

  @override
  void dispose() {
    _network.dispose();
    super.dispose();
  }
}
