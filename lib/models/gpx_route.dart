import 'dart:math' as math;

import 'package:xml/xml.dart';

class GpxPoint {
  const GpxPoint(this.lat, this.lng, [this.ele]);

  final double lat;
  final double lng;
  final double? ele;

  List<num?> toJson() => [lat, lng, ele];

  factory GpxPoint.fromJson(List<dynamic> j) =>
      GpxPoint((j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num?)?.toDouble());
}

class GpxWaypoint {
  const GpxWaypoint(this.point, this.name);

  final GpxPoint point;
  final String name;

  Map<String, dynamic> toJson() => {'p': point.toJson(), 'name': name};

  factory GpxWaypoint.fromJson(Map<String, dynamic> j) =>
      GpxWaypoint(GpxPoint.fromJson(j['p'] as List), j['name'] as String);
}

/// GPX 트랙(또는 루트) 한 개. 구간별 누적 거리를 미리 계산해 둔다.
class GpxRoute {
  GpxRoute({required this.name, required this.points, this.waypoints = const []})
      : cumulative = _cumulative(points);

  final String name;
  final List<GpxPoint> points;
  final List<GpxWaypoint> waypoints;

  /// points[i] 까지의 누적 거리(m)
  final List<double> cumulative;

  double get totalMeters => cumulative.isEmpty ? 0 : cumulative.last;

  /// 누적 상승 고도(m). 3m 미만 흔들림은 무시.
  double get elevationGain {
    var gain = 0.0;
    double? last;
    for (final p in points) {
      final e = p.ele;
      if (e == null) continue;
      if (last != null && e - last > 3) {
        gain += e - last;
        last = e;
      } else if (last == null || e < last) {
        last = e;
      }
    }
    return gain;
  }

  static List<double> _cumulative(List<GpxPoint> pts) {
    final out = <double>[];
    var d = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) d += haversine(pts[i - 1], pts[i]);
      out.add(d);
    }
    return out;
  }

  /// GPX 1.0/1.1 문자열 파싱. 트랙(trkpt) 우선, 없으면 루트(rtept).
  factory GpxRoute.parse(String xml, {required String fallbackName}) {
    final doc = XmlDocument.parse(xml);
    Iterable<XmlElement> byName(String local) =>
        doc.descendantElements.where((e) => e.name.local == local);

    GpxPoint toPoint(XmlElement e) {
      final ele = e.childElements.where((c) => c.name.local == 'ele').firstOrNull;
      return GpxPoint(
        double.parse(e.getAttribute('lat')!),
        double.parse(e.getAttribute('lon')!),
        ele == null ? null : double.tryParse(ele.innerText.trim()),
      );
    }

    var pts = byName('trkpt').map(toPoint).toList();
    if (pts.isEmpty) pts = byName('rtept').map(toPoint).toList();
    if (pts.length < 2) throw const FormatException('GPX 에 트랙 포인트가 없습니다');

    String? textOf(XmlElement? e) {
      final t = e?.childElements.where((c) => c.name.local == 'name').firstOrNull?.innerText.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final name = textOf(byName('metadata').firstOrNull) ??
        textOf(byName('trk').firstOrNull) ??
        textOf(byName('rte').firstOrNull) ??
        fallbackName;

    final wpts = [
      for (final w in byName('wpt')) GpxWaypoint(toPoint(w), textOf(w) ?? '지점'),
    ];
    return GpxRoute(name: name, points: pts, waypoints: wpts);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'points': [for (final p in points) p.toJson()],
        'waypoints': [for (final w in waypoints) w.toJson()],
      };

  factory GpxRoute.fromJson(Map<String, dynamic> j) => GpxRoute(
        name: j['name'] as String,
        points: [for (final p in j['points'] as List) GpxPoint.fromJson(p as List)],
        waypoints: [
          for (final w in (j['waypoints'] as List? ?? const []))
            GpxWaypoint.fromJson(w as Map<String, dynamic>),
        ],
      );
}

double haversine(GpxPoint a, GpxPoint b) {
  const r = 6371000.0;
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLng = (b.lng - a.lng) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.lat * math.pi / 180) * math.cos(b.lat * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// 현재 위치를 경로 위에 투영한 결과
class RouteProgress {
  const RouteProgress({
    required this.segmentIndex,
    required this.snapped,
    required this.offRouteMeters,
    required this.doneMeters,
    required this.totalMeters,
  });

  /// 투영된 구간의 시작 인덱스 (points[i] → points[i+1])
  final int segmentIndex;
  final GpxPoint snapped;

  /// 경로까지의 최단 거리(m)
  final double offRouteMeters;
  final double doneMeters;
  final double totalMeters;

  double get remainingMeters => math.max(0, totalMeters - doneMeters);
  double get ratio => totalMeters == 0 ? 0 : (doneMeters / totalMeters).clamp(0.0, 1.0);

  /// 위치를 경로에 투영한다. 왕복·교차 경로에서 진행 위치가 튀지 않도록
  /// 직전 구간 근처([hint] ±150)에서 충분히 가까우면 그쪽을 우선한다.
  static RouteProgress compute(GpxRoute route, GpxPoint pos, {int? hint}) {
    final pts = route.points;

    (int, double, double, GpxPoint) best(int from, int to) {
      var bi = from;
      var bd = double.infinity;
      var bt = 0.0;
      var bp = pts[from];
      for (var i = from; i < to; i++) {
        final (d, t, p) = _projectOnSegment(pos, pts[i], pts[i + 1]);
        if (d < bd) {
          bi = i;
          bd = d;
          bt = t;
          bp = p;
        }
      }
      return (bi, bd, bt, bp);
    }

    var result = best(0, pts.length - 1);
    if (hint != null) {
      final local = best(math.max(0, hint - 150), math.min(pts.length - 1, hint + 150));
      if (local.$2 <= result.$2 + 30) result = local;
    }
    final (i, d, t, p) = result;
    final segLen = route.cumulative[i + 1] - route.cumulative[i];
    return RouteProgress(
      segmentIndex: i,
      snapped: p,
      offRouteMeters: d,
      doneMeters: route.cumulative[i] + segLen * t,
      totalMeters: route.totalMeters,
    );
  }

  /// 짧은 구간이므로 위도 기준 등장방형 근사(m)로 투영
  static (double, double, GpxPoint) _projectOnSegment(GpxPoint p, GpxPoint a, GpxPoint b) {
    final kx = 111320 * math.cos(p.lat * math.pi / 180);
    const ky = 110540.0;
    final ax = (a.lng - p.lng) * kx, ay = (a.lat - p.lat) * ky;
    final bx = (b.lng - p.lng) * kx, by = (b.lat - p.lat) * ky;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    final snapped = GpxPoint(p.lat + cy / ky, p.lng + cx / kx);
    return (math.sqrt(cx * cx + cy * cy), t, snapped);
  }
}
