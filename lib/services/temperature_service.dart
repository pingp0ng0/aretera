import 'dart:math';

/// 결로 예측 대신 제공하는 '보수적' 지표: 고도 보정 기온 + 풍속 냉각(체감) 온도.
class TemperatureService {
  TemperatureService._();

  /// 표준 대기 기온 감률: 100m 상승당 약 0.65°C 하강
  static const lapseRatePer100m = 0.65;

  static double altitudeCorrected({
    required double baseTempC,
    required double baseAltitudeM,
    required double currentAltitudeM,
  }) =>
      baseTempC - (currentAltitudeM - baseAltitudeM) / 100 * lapseRatePer100m;

  /// 기상청 체감온도(겨울철) 식. 기온 10°C 이하 · 풍속 4.8km/h 이상에서만 유효.
  static double? windChill(double tempC, double windMs) {
    final v = windMs * 3.6;
    if (tempC > 10 || v < 4.8) return null;
    final v16 = pow(v, 0.16).toDouble();
    return 13.12 + 0.6215 * tempC - 11.37 * v16 + 0.3965 * v16 * tempC;
  }

  static double feelsLike(double tempC, double windMs) => windChill(tempC, windMs) ?? tempC;
}
