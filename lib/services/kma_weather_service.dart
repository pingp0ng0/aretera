import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException, SupabaseClient;

import 'server_session.dart';

class KmaObservation {
  const KmaObservation({required this.tempC, required this.windMs, required this.observedAt});
  final double tempC;
  final double windMs;
  final DateTime observedAt;

  /// Reply of the `weather` Edge Function: {temp_c, wind_ms, observed_at (UTC ISO)}.
  factory KmaObservation.fromServer(Map<String, dynamic> j) => KmaObservation(
        tempC: (j['temp_c'] as num).toDouble(),
        windMs: (j['wind_ms'] as num? ?? 0).toDouble(),
        observedAt: DateTime.parse(j['observed_at'] as String).toLocal(),
      );
}

class KmaException implements Exception {
  KmaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 기상청 초단기실황 — through the `weather` Edge Function so the KMA key stays on the server.
/// Only the 5 km grid cell is sent, never the exact position (PRD_step6 6-2).
class KmaWeatherService {
  KmaWeatherService(this.client);

  final SupabaseClient client;

  Future<KmaObservation> fetchCurrent(double lat, double lng) async {
    final (nx, ny) = toGrid(lat, lng);
    try {
      await ensureSignedIn(client);
      final res = await client.functions
          .invoke('weather', body: {'nx': nx, 'ny': ny})
          .timeout(const Duration(seconds: 20));
      return KmaObservation.fromServer(res.data as Map<String, dynamic>);
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      throw KmaException(switch (code) {
        'login_required' => '서버 로그인이 만료되었습니다. 앱을 다시 열어 주세요.',
        'kma_error' => '기상청: ${(e.details as Map)['message']}',
        'kma_bad_response' => '서버의 기상청 인증키를 확인하세요.',
        _ => '날씨 서버 오류 (${code ?? 'HTTP ${e.status}'})',
      });
    }
  }

  /// 위경도 → 기상청 동네예보 격자(5km, Lambert Conformal Conic)
  static (int nx, int ny) toGrid(double lat, double lng) {
    const re = 6371.00877, grid = 5.0, slat1 = 30.0, slat2 = 60.0;
    const olon = 126.0, olat = 38.0, xo = 43.0, yo = 136.0;
    const degrad = pi / 180.0;

    final reGrid = re / grid;
    final s1 = slat1 * degrad, s2 = slat2 * degrad, ol = olon * degrad, oa = olat * degrad;

    var sn = tan(pi * 0.25 + s2 * 0.5) / tan(pi * 0.25 + s1 * 0.5);
    sn = log(cos(s1) / cos(s2)) / log(sn);
    var sf = tan(pi * 0.25 + s1 * 0.5);
    sf = pow(sf, sn).toDouble() * cos(s1) / sn;
    var ro = tan(pi * 0.25 + oa * 0.5);
    ro = reGrid * sf / pow(ro, sn).toDouble();

    var ra = tan(pi * 0.25 + lat * degrad * 0.5);
    ra = reGrid * sf / pow(ra, sn).toDouble();
    var theta = lng * degrad - ol;
    if (theta > pi) theta -= 2.0 * pi;
    if (theta < -pi) theta += 2.0 * pi;
    theta *= sn;

    return (
      (ra * sin(theta) + xo + 0.5).floor(),
      (ro - ra * cos(theta) + yo + 0.5).floor(),
    );
  }
}
