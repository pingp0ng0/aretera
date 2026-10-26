import 'package:bivi/models/gear_item.dart';
import 'package:bivi/models/trip.dart';
import 'package:bivi/services/kma_weather_service.dart';
import 'package:bivi/services/offline_tile_cache.dart';
import 'package:bivi/services/temperature_service.dart';
import 'package:bivi/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TemperatureService', () {
    test('1000m 상승 시 6.5°C 하강', () {
      final t = TemperatureService.altitudeCorrected(
          baseTempC: 10, baseAltitudeM: 200, currentAltitudeM: 1200);
      expect(t, closeTo(3.5, 1e-9));
    });

    test('바람이 약하면 체감온도 = 기온', () {
      expect(TemperatureService.feelsLike(-5, 1), -5);
    });

    test('강풍 시 체감온도가 더 낮다', () {
      expect(TemperatureService.feelsLike(-5, 10), lessThan(-5));
    });
  });

  test('기상청 격자 변환: 서울시청 → (60, 127)', () {
    expect(KmaWeatherService.toGrid(37.5665, 126.9780), (60, 127));
  });

  test('weather Edge Function reply → local observation time', () {
    final obs = KmaObservation.fromServer(
        {'temp_c': 21.5, 'wind_ms': 1.4, 'observed_at': '2026-10-23T07:00:00.000Z'});
    expect(obs.tempC, 21.5);
    expect(obs.windMs, 1.4);
    expect(obs.observedAt.isUtc, isFalse);
    expect(obs.observedAt.isAtSameMomentAs(DateTime.utc(2026, 10, 23, 7)), isTrue);
  });

  test('타일 좌표 변환은 범위 안에 있다', () {
    final (x, y) = OfflineTileCache.tileOf(35.3369, 127.7306, 14);
    expect(x, inInclusiveRange(0, (1 << 14) - 1));
    expect(y, inInclusiveRange(0, (1 << 14) - 1));
  });

  test('uuidV4 형식', () {
    expect(uuidV4(), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  test('GearItem JSON 왕복 (my_gear 컬럼명 일치)', () {
    const g = GearItem(id: 'x', name: 'MYOG 스터프 색', categoryId: 'myog', weightGrams: 9);
    final j = g.toJson();
    expect(j.keys, containsAll(['id', 'name', 'category', 'weight_grams', 'is_packed']));
    final back = GearItem.fromJson(j);
    expect(back.categoryId, 'myog');
    expect(back.weightGrams, 9);
  });

  test('saved GPS fix time is shown in local time even if stored in UTC', () {
    final utc = DateTime.utc(2026, 10, 23, 7, 3);
    final p = CachedPosition.fromJson(
        {'lat': 37.4, 'lng': 127.1, 'altitude': 123, 'accuracy': 18, 'timestamp': utc.toIso8601String()});
    expect(p.timestamp.isUtc, isFalse);
    expect(p.timestamp.isAtSameMomentAs(utc), isTrue);
  });

  test('DMS 변환', () {
    expect(toDms(37.5, isLat: true), '37°30\'00.0" N');
  });
}
