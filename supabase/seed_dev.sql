-- Development sample data only (PRD_step6). Do NOT run on the real Supabase project.

-- ─────────────────────────────────────────────
-- 시드 데이터 (⚠️ 개발용 샘플 — 배포 전 국립공원공단 / 산림청 공식 자료로 재검증 필수)
-- lib/data/seed_data.dart 와 동일한 내용입니다.
-- ─────────────────────────────────────────────
insert into public.campsites
  (id, name, lat, lng, is_legal, last_verified_date, facilities, type, source, region, note)
values
  ('b1e2c3d4-0000-4000-8000-000000000001', '지리산 세석대피소', 35.3168, 127.6658, true, '2026-09-12',
   '{"water": true, "toilet": true, "shelter": true}', 'shelter', '국립공원공단 국립공원예약시스템',
   '지리산국립공원 · 경남 산청', '사전 예약제 대피소. 대피소 외 텐트 야영은 불가합니다.'),
  ('b1e2c3d4-0000-4000-8000-000000000002', '지리산 장터목대피소', 35.3335, 127.7213, true, '2026-09-12',
   '{"water": true, "toilet": true, "shelter": true}', 'shelter', '국립공원공단 국립공원예약시스템',
   '지리산국립공원 · 경남 산청', '천왕봉 일출 산행 거점. 동계 결빙 시 식수 확보 어려움.'),
  ('b1e2c3d4-0000-4000-8000-000000000003', '덕유산 향적봉대피소', 35.8597, 127.7461, true, '2025-11-03',
   '{"water": false, "toilet": true, "shelter": true}', 'shelter', '국립공원공단 국립공원예약시스템',
   '덕유산국립공원 · 전북 무주', '식수 공급 불안정 — 충분한 물을 지참하세요.'),
  ('b1e2c3d4-0000-4000-8000-000000000004', '덕유대 야영장', 35.8930, 127.7700, true, '2026-08-20',
   '{"water": true, "toilet": true, "shelter": false}', 'campground', '국립공원공단 국립공원예약시스템',
   '덕유산국립공원 · 전북 무주', null),
  ('b1e2c3d4-0000-4000-8000-000000000005', '설악동 야영장', 38.1748, 128.5050, true, '2026-07-30',
   '{"water": true, "toilet": true, "shelter": false}', 'campground', '국립공원공단 국립공원예약시스템',
   '설악산국립공원 · 강원 속초', null),
  ('b1e2c3d4-0000-4000-8000-000000000006', '국립 유명산자연휴양림', 37.5847, 127.4886, true, '2026-09-01',
   '{"water": true, "toilet": true, "shelter": false}', 'forest', '산림청 국립자연휴양림관리소 (숲나들e)',
   '경기 가평', '야영데크 예약제. 데크 외 설영 금지.'),
  ('b1e2c3d4-0000-4000-8000-000000000007', '국립 중미산자연휴양림', 37.5717, 127.4325, true, '2026-06-15',
   '{"water": true, "toilet": true, "shelter": false}', 'forest', '산림청 국립자연휴양림관리소 (숲나들e)',
   '경기 양평', null),
  ('b1e2c3d4-0000-4000-8000-000000000008', '설악산 대청봉 일대', 38.1194, 128.4656, false, '2026-09-05',
   '{"water": false, "toilet": false, "shelter": false}', 'restricted', '자연공원법 제27조 · 국립공원공단',
   '설악산국립공원 · 강원 양양/인제', '국립공원 지정 야영장 외 야영·취사는 과태료 부과 대상입니다.')
on conflict (id) do nothing;
