import '../models/campsite.dart';
import '../models/gear_item.dart';
import '../utils/format.dart';

// ⚠️ 아래 야영지 좌표·시설·검증일은 개발용 샘플입니다.
// 배포 전 국립공원공단 / 산림청(숲나들e) 공식 자료로 반드시 재검증 후 supabase/schema.sql 시드를 교체하세요.
final seedCampsites = <Campsite>[
  Campsite(
    id: 'b1e2c3d4-0000-4000-8000-000000000001',
    name: '지리산 세석대피소',
    lat: 35.3168,
    lng: 127.6658,
    isLegal: true,
    lastVerifiedDate: DateTime(2026, 9, 12),
    facilities: const Facilities(water: true, toilet: true, shelter: true),
    type: CampsiteType.shelter,
    source: '국립공원공단 국립공원예약시스템',
    region: '지리산국립공원 · 경남 산청',
    note: '사전 예약제 대피소. 대피소 외 텐트 야영은 불가합니다.',
  ),
  Campsite(
    id: 'b1e2c3d4-0000-4000-8000-000000000002',
    name: '지리산 장터목대피소',
    lat: 35.3335,
    lng: 127.7213,
    isLegal: true,
    lastVerifiedDate: DateTime(2026, 9, 12),
    facilities: const Facilities(water: true, toilet: true, shelter: true),
    type: CampsiteType.shelter,
    source: '국립공원공단 국립공원예약시스템',
    region: '지리산국립공원 · 경남 산청',
    note: '천왕봉 일출 산행 거점. 동계 결빙 시 식수 확보 어려움.',
  ),
  Campsite(
    id: 'b1e2c3d4-0000-4000-8000-000000000003',
    name: '덕유산 향적봉대피소',
    lat: 35.8597,
    lng: 127.7461,
    isLegal: true,
    lastVerifiedDate: DateTime(2025, 11, 3),
    facilities: const Facilities(water: false, toilet: true, shelter: true),
    type: CampsiteType.shelter,
    source: '국립공원공단 국립공원예약시스템',
    region: '덕유산국립공원 · 전북 무주',
    note: '식수 공급 불안정 — 충분한 물을 지참하세요.',
  ),
  Campsite(
    id: 'b1e2c3d4-0000-4000-8000-000000000004',
    name: '덕유대 야영장',
    lat: 35.8930,
    lng: 127.7700,
    isLegal: true,
    lastVerifiedDate: DateTime(2026, 8, 20),
    facilities: const Facilities(water: true, toilet: true, shelter: false),
    type: CampsiteType.campground,
    source: '국립공원공단 국립공원예약시스템',
    region: '덕유산국립공원 · 전북 무주',
  ),
  Campsite(
    id: 'b1e2c3d4-0000-4000-8000-000000000005',
    name: '설악동 야영장',
    lat: 38.1748,
    lng: 128.5050,
    isLegal: true,
    lastVerifiedDate: DateTime(2026, 7, 30),
    facilities: const Facilities(water: true, toilet: true, shelter: false),
    type: CampsiteType.campground,
    source: '국립공원공단 국립공원예약시스템',
    region: '설악산국립공원 · 강원 속초',
  ),
  Campsite(
    id: 'b1e2c3d4-0000-4000-8000-000000000006',
    name: '국립 유명산자연휴양림',
    lat: 37.5847,
    lng: 127.4886,
    isLegal: true,
    lastVerifiedDate: DateTime(2026, 9, 1),
    facilities: const Facilities(water: true, toilet: true, shelter: false),
    type: CampsiteType.forest,
    source: '산림청 국립자연휴양림관리소 (숲나들e)',
    region: '경기 가평',
    note: '야영데크 예약제. 데크 외 설영 금지.',
  ),
  Campsite(
    id: 'b1e2c3d4-0000-4000-8000-000000000007',
    name: '국립 중미산자연휴양림',
    lat: 37.5717,
    lng: 127.4325,
    isLegal: true,
    lastVerifiedDate: DateTime(2026, 6, 15),
    facilities: const Facilities(water: true, toilet: true, shelter: false),
    type: CampsiteType.forest,
    source: '산림청 국립자연휴양림관리소 (숲나들e)',
    region: '경기 양평',
  ),
  Campsite(
    id: 'b1e2c3d4-0000-4000-8000-000000000008',
    name: '설악산 대청봉 일대',
    lat: 38.1194,
    lng: 128.4656,
    isLegal: false,
    lastVerifiedDate: DateTime(2026, 9, 5),
    facilities: const Facilities(),
    type: CampsiteType.restricted,
    source: '자연공원법 제27조 · 국립공원공단',
    region: '설악산국립공원 · 강원 양양/인제',
    note: '국립공원 지정 야영장 외 야영·취사는 과태료 부과 대상입니다.',
  ),
];

/// 첫 실행 시 '내 배낭' 더미 데이터 — 동계 경량 장비 + MYOG 자작 장비.
/// Category ids match [defaultGearCategories].
List<GearItem> buildSeedGear() {
  GearItem g(String name, String categoryId, int w, {bool packed = false}) =>
      GearItem(id: uuidV4(), name: name, categoryId: categoryId, weightGrams: w, isPacked: packed);

  return [
    g('1인용 싱글월 텐트 (트레킹폴 피칭)', 'shelter', 650, packed: true),
    g('4계절 더블월 텐트 (동계용)', 'shelter', 1850),
    g('다이니마 그라운드시트', 'shelter', 80, packed: true),
    g('동계용 구스다운 침낭 (-15°C)', 'sleep', 1350, packed: true),
    g('에어 매트 (R-value 4.5)', 'sleep', 450, packed: true),
    g('접이식 폼 매트', 'sleep', 280),
    g('구스다운 패딩 자켓', 'clothing', 380, packed: true),
    g('메리노 울 베이스레이어', 'clothing', 190, packed: true),
    g('방수 쉘 자켓', 'clothing', 340),
    g('다운 부티', 'clothing', 120),
    g('티타늄 코펠 750ml', 'cook', 105, packed: true),
    g('경량 가스 스토브', 'cook', 85, packed: true),
    g('이소부탄 가스 230g (동계용)', 'cook', 360, packed: true),
    g('티타늄 스푼', 'cook', 18, packed: true),
    g('구급약 키트', 'safety', 180),
    g('헤드랜턴 + 여분 배터리', 'safety', 95),
    g('비상용 은박 담요', 'safety', 55),
    g('호루라기', 'safety', 10),
    g('MYOG 다이니마 스터프 색 (S)', 'myog', 9, packed: true),
    g('MYOG 실넥 침낭용 스터프 색', 'myog', 22, packed: true),
    g('MYOG 캔 알코올 스토브', 'myog', 12),
    g('보조배터리 10,000mAh', 'etc', 180, packed: true),
    g('카본 트레킹 폴 (1조)', 'etc', 480),
  ];
}

class LightAlternative {
  const LightAlternative({
    required this.name,
    required this.weightGrams,
    required this.note,
    this.affiliateUrl,
  });

  final String name;
  final int weightGrams;
  final String note;

  /// 제휴 커머스 링크 슬롯 (MVP 에서는 비워둠)
  final String? affiliateUrl;
}

/// 이 무게 이상인 '패킹된' 장비에 대해 경량 대체품 추천 슬롯을 노출한다.
const heavyItemThresholdGrams = 800;

/// Keyed by built-in category id; user-made categories have no suggestions.
const lightAlternatives = <String, List<LightAlternative>>{
  'shelter': [
    LightAlternative(name: '초경량 싱글월 텐트', weightGrams: 550, note: '트레킹폴 겸용 · 삼계절'),
    LightAlternative(name: '다이니마 타프 + 비비색 조합', weightGrams: 420, note: 'UL 숙련자용'),
  ],
  'sleep': [
    LightAlternative(name: '850FP 다운 퀼트 (-10°C)', weightGrams: 780, note: '지퍼·후드 제거로 경량화'),
    LightAlternative(name: '900FP 동계 머미 침낭', weightGrams: 1050, note: '-15°C 컴포트 기준'),
  ],
  'clothing': [
    LightAlternative(name: '800FP 초경량 다운 자켓', weightGrams: 240, note: '보온 레이어 대체'),
  ],
  'cook': [
    LightAlternative(name: '티타늄 일체형 스토브 세트', weightGrams: 210, note: '코펠+버너 통합'),
  ],
  'etc': [
    LightAlternative(name: '카본 Z-폴 (접이식)', weightGrams: 300, note: '트레킹폴 대체'),
  ],
};
