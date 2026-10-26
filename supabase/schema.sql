-- Bivi MVP v1.0 — Supabase (PostgreSQL) 스키마
-- Supabase 대시보드 > SQL Editor 에 붙여넣어 실행하세요.

-- ─────────────────────────────────────────────
-- 1) campsites : 합법 야영지 · 대피소 (모든 사용자 읽기 전용)
-- ─────────────────────────────────────────────
create table if not exists public.campsites (
  id                 uuid primary key default gen_random_uuid(),
  name               varchar not null,
  lat                float8  not null,
  lng                float8  not null,
  is_legal           boolean not null default true,
  last_verified_date date    not null,
  facilities         jsonb   not null default '{"water": false, "toilet": false, "shelter": false}',
  -- PRD 6.2 확장 컬럼: 필터 · 출처 표기용
  type               varchar not null default 'campground'
                       check (type in ('shelter', 'forest', 'campground', 'restricted')),
  source             varchar not null,
  region             varchar,
  note               text,
  tel                varchar,
  url                varchar,   -- 예약 페이지 또는 홈페이지
  created_at         timestamptz not null default now()
);
-- 이전 버전 스키마로 이미 만든 경우
alter table public.campsites add column if not exists tel varchar;
alter table public.campsites add column if not exists url varchar;
-- facilities 의 값이 null 이면 '출처에 정보 없음' (고캠핑 미입력 항목)

-- 공간 쿼리가 필요해지면 PostGIS 를 켜고 geography 컬럼 + GIST 인덱스를 추가하세요.
-- create extension if not exists postgis;
-- alter table public.campsites add column geog geography(Point, 4326);
-- update public.campsites set geog = st_setsrid(st_makepoint(lng, lat), 4326)::geography;
-- create index on public.campsites using gist (geog);

alter table public.campsites enable row level security;
drop policy if exists "campsites readable by everyone" on public.campsites;
create policy "campsites readable by everyone"
  on public.campsites for select using (true);

-- ─────────────────────────────────────────────
-- 2) my_gear : 내 장비 (로컬 우선, 로그인 사용자만 클라우드 동기화)
-- ─────────────────────────────────────────────
create table if not exists public.my_gear (
  id           uuid primary key,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name         varchar not null,
  -- Category id: built-in ones (shelter, sleep, …) or a user-made category's UUID (PRD_step3).
  category     varchar not null,
  weight_grams int4 not null check (weight_grams >= 0),
  is_packed    boolean not null default false,
  updated_at   timestamptz not null default now()
);
-- Tables created with the earlier schema still have the fixed-list check; drop it.
alter table public.my_gear drop constraint if exists my_gear_category_check;
create index if not exists my_gear_user_idx on public.my_gear (user_id);

alter table public.my_gear enable row level security;
drop policy if exists "own gear" on public.my_gear;
create policy "own gear" on public.my_gear
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- 3) trips : (다음 단계) 하산 미도착 보호자 알림용 산행 계획
--    Edge Function + pg_cron 으로 target_time + 유예시간 초과 & finished_at null 이면 SMS/푸시 발송
-- ─────────────────────────────────────────────
create table if not exists public.trips (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  started_at       timestamptz not null default now(),
  target_time      timestamptz not null,
  finished_at      timestamptz,
  guardian_phone   varchar,
  last_lat         float8,
  last_lng         float8,
  last_altitude_m  float8,
  last_seen_at     timestamptz
);
alter table public.trips enable row level security;
drop policy if exists "own trips" on public.trips;
create policy "own trips" on public.trips
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Dev sample campsites live in seed_dev.sql — never run it on the real project:
-- the app prefers server campsites, so 8 samples would hide the 2,803 bundled ones (PRD_step6).
