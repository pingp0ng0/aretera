import 'package:bivi/models/gpx_route.dart';
import 'package:flutter_test/flutter_test.dart';

const _gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>지리산 화대종주 일부</name></metadata>
  <wpt lat="35.3335" lon="127.7213"><name>장터목대피소</name></wpt>
  <trk><trkseg>
    <trkpt lat="35.3300" lon="127.7100"><ele>1500</ele></trkpt>
    <trkpt lat="35.3300" lon="127.7200"><ele>1600</ele></trkpt>
    <trkpt lat="35.3400" lon="127.7200"><ele>1700</ele></trkpt>
  </trkseg></trk>
</gpx>''';

void main() {
  final route = GpxRoute.parse(_gpx, fallbackName: 'x');

  test('네임스페이스가 있는 GPX 1.1 파싱', () {
    expect(route.name, '지리산 화대종주 일부');
    expect(route.points.length, 3);
    expect(route.waypoints.single.name, '장터목대피소');
    expect(route.elevationGain, closeTo(200, 1e-9));
  });

  test('누적 거리 ≈ 동쪽 0.01° + 북쪽 0.01°', () {
    // 위도 35.33 에서 경도 0.01° ≈ 908m, 위도 0.01° ≈ 1112m
    expect(route.totalMeters, closeTo(908 + 1112, 15));
  });

  test('경로 위 위치 → 진행 거리 · 이탈 0m', () {
    final p = RouteProgress.compute(route, const GpxPoint(35.3300, 127.7150));
    expect(p.segmentIndex, 0);
    expect(p.offRouteMeters, lessThan(1));
    expect(p.doneMeters, closeTo(454, 10));
  });

  test('경로에서 떨어진 위치 → 이탈 거리', () {
    // 첫 구간 중간에서 북쪽으로 약 111m
    final p = RouteProgress.compute(route, const GpxPoint(35.3310, 127.7150));
    expect(p.offRouteMeters, closeTo(110, 5));
  });

  test('JSON 저장 왕복', () {
    final back = GpxRoute.fromJson(route.toJson());
    expect(back.points.length, 3);
    expect(back.totalMeters, closeTo(route.totalMeters, 1e-6));
  });

  test('트랙 포인트 없으면 오류', () {
    expect(() => GpxRoute.parse('<gpx></gpx>', fallbackName: 'x'), throwsFormatException);
  });
}
