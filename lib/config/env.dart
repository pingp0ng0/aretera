/// 빌드 타임 설정. `flutter run --dart-define-from-file=env.json` 으로 주입합니다.
/// 키가 비어 있어도 앱은 로컬 시드 데이터 + 무료 지형도로 바로 실행됩니다.
class Env {
  Env._();

  static const appId = 'com.bivi.bivi';
  static const userAgent = 'Bivi/1.0 ($appId)';

  static const mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
  static const mapboxStyle =
      String.fromEnvironment('MAPBOX_STYLE', defaultValue: 'mapbox/outdoors-v12');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Publishable (public) key. The env name stays SUPABASE_ANON_KEY for existing env.json files.
  /// The KMA key is no longer in the app: weather goes through the `weather` Edge Function (PRD_step6).
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Shows "add/remove demo hikes" in the records tab, for testing on a phone (PRD_step5).
  static const demoRecords = bool.fromEnvironment('DEMO_RECORDS');

  static bool get hasMapbox => mapboxToken.isNotEmpty;
  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// 오프라인 타일 캐시 디렉터리 구분용 (소스가 바뀌면 캐시도 분리)
  static String get tileSourceKey =>
      hasMapbox ? 'mapbox_${mapboxStyle.replaceAll('/', '_')}' : 'opentopomap';

  static String get tileUrlTemplate => hasMapbox
      ? 'https://api.mapbox.com/styles/v1/$mapboxStyle/tiles/256/{z}/{x}/{y}@2x?access_token=$mapboxToken'
      : 'https://tile.opentopomap.org/{z}/{x}/{y}.png';

  static int get maxNativeZoom => hasMapbox ? 18 : 17;

  /// 기본은 컬러 지형도. MAP_DARK=true 이면 차콜 톤 필터로 야간 눈부심을 줄인다.
  static const mapDark = bool.fromEnvironment('MAP_DARK');
  static bool get applyDarkFilter => mapDark && !mapboxStyle.contains('dark');

  static String get attribution => hasMapbox
      ? '© Mapbox © OpenStreetMap'
      : '© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)';
}
