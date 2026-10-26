# Bivi (비비) — MVP v1.0

> 안전한 야영지 탐색부터 초경량 스마트 패킹까지, 백패커를 위한 단 하나의 베이스캠프

Flutter + Riverpod + Supabase. **API 키 없이도 바로 실행**됩니다 (로컬 시드 데이터 + OpenTopoMap 등고선 지형도로 자동 폴백).

## 빠른 시작

```bash
# 1) 플랫폼 폴더 생성 (lib/, pubspec.yaml 등 기존 파일은 덮어쓰지 않음)
flutter create . --project-name bivi --org com.bivi --platforms android,ios

# 2) 위치·백그라운드·인터넷 권한을 AndroidManifest / Info.plist 에 추가
dart run tool/setup_platform.dart

# 3) 실행
flutter pub get
flutter run
```

키를 연결하려면 `env.example.json` 을 `env.json` 으로 복사해 값을 채운 뒤:

```bash
flutter run --dart-define-from-file=env.json
```

| 키 | 없을 때 동작 |
|---|---|
| `MAPBOX_TOKEN`, `MAPBOX_STYLE` | OpenTopoMap 등고선 지형도 + 다크 필터 |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | 번들 시드 야영지 사용, 장비는 기기에만 저장 |
| `KMA_API_KEY` (공공데이터포털 **Decoding** 키) | 산행 모드에서 기준 기온을 직접 입력 |

Supabase 는 `supabase/schema.sql` 을 SQL Editor 에서 실행하면 테이블 · RLS · 시드가 생성됩니다.

## 구조

```
lib/
  main.dart                     앱 진입점 · ProviderScope overrides (prefs, 타일 캐시, Supabase)
  config/env.dart               --dart-define 설정 · 지도 타일 소스 선택
  theme/app_theme.dart          다크 테마 (#121212 · #1E2420 · #2E5A44 · #FF6B35)
  models/                       Campsite · GearItem · SafeTripState · CachedPosition · MedicalInfo
  data/seed_data.dart           시드 야영지 · 동계/MYOG 더미 장비 · 경량 대체품
  data/repositories.dart        Supabase → 로컬 캐시 → 시드 폴백, 로컬 우선 저장
  providers/                    Riverpod (campsite / gear / safe_trip / core)
  services/                     고도 보정 기온 · 기상청 실황 API · 오프라인 타일 캐시
  widgets/topo.dart             등고선 패턴 페인터 · 'B' 로고 · Empty State
  screens/
    home_shell.dart             4탭 NavigationBar (IndexedStack)
    map_screen.dart             Tab1 합법 야영지 지도 + 필터 + 상세 바텀 시트
    packing_screen.dart         Tab2 원형 무게 게이지 · 안전 장비 누락 배너 · 대체품 슬롯
    safe_trip_screen.dart       Tab3 하산 카운트다운 · 고도 보정 체감온도 · GPS 캐시
    sos_card_screen.dart        오프라인 SOS 고대비 카드 (좌표 · 고도 · 의료 정보 · 119)
    records_screen.dart         Tab4 (v1.5 예정 Empty State)
supabase/schema.sql             campsites · my_gear · trips 테이블, RLS, 시드
tool/setup_platform.dart        네이티브 권한 패치 스크립트
```

## PRD 대비 구현 메모

- **지도**: PRD 의 Mapbox 를 `flutter_map` + Mapbox Styles 래스터 타일로 연동했습니다. 네이티브 SDK 설정(다운로드 토큰 등) 없이 바로 빌드되도록 한 선택입니다. 벡터 스타일·3D 지형이 필요해지면 `mapbox_maps_flutter` 로 교체하세요.
- **오프라인 타일**: 산행 시작 시 주변 약 68장(z12–15)을 내려받는 프로토타입입니다. Mapbox 타일을 프로덕션에서 오프라인 저장하려면 약관상 Mapbox SDK 의 공식 오프라인(TileStore)을 써야 합니다.
- **고도 보정 체감온도**: 기상청 초단기실황 기온을 *들머리(산행 시작 지점) 고도 기준*으로 보고, 현재 GPS 고도 차이에 100m당 0.65°C 를 적용합니다. 풍속이 있으면 기상청 겨울철 체감온도식을 추가 적용합니다. 결로 예측은 PRD 결정대로 제외했습니다.
- **백그라운드 위치**: Android 는 포그라운드 서비스 알림, iOS 는 Background Modes(location)로 화면이 꺼져도 좌표를 저장합니다. 정지 상태에서도 1분마다 강제 측위합니다.
- **의료 정보**: 기기에만 저장되며 서버로 전송하지 않습니다.
- **보호자 미도착 알림**: 클라이언트 카운트다운·초과 경고까지 구현했습니다. 실제 알림 발송은 서버가 필요하므로 `trips` 테이블만 준비해 두었습니다 (Edge Function + pg_cron 으로 구현 예정).
- **장비 동기화**: 로컬 우선. Supabase 로그인 세션이 있을 때만 `my_gear` 로 upsert 됩니다 (로그인 UI 는 MVP 범위 밖).

> ⚠️ 시드 야영지의 좌표 · 시설 · 검증일은 개발용 샘플입니다. 배포 전 국립공원공단 · 산림청 공식 자료로 반드시 재검증하세요.
