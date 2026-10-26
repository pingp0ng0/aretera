# Bivi — project notes

What and why: see `PRD_step*.md`. This file covers how to run it and what to watch out for.

## Folders
- Build/working folder: `C:\dev\bivi` (ASCII path; Gradle fails on Korean paths on Windows).
- Mirror for browsing: `Documents\클로드\Vibecoding\백패킹어플` (sync after changes; never copy `env.json` there).

## Toolchain (installed under C:\dev)
- Flutter `C:\dev\flutter` · JDK 21 `C:\dev\jdk` · Android SDK `C:\dev\android`
- PowerShell: `$env:PATH = "C:\dev\flutter\bin;C:\dev\jdk\bin;" + $env:PATH; $env:JAVA_HOME = "C:\dev\jdk"`

## Secrets
- `env.json` (gitignored) holds keys; `env.example.json` is the empty template.
- Build: `flutter build apk --release --dart-define-from-file=env.json`
- Never print key values. Check env.json with names only (`set`/`empty`).
- `KMA_API_KEY` and `OPENROUTER_API_KEY` live only in Supabase Edge Function secrets (PRD_step6), not in the app.

## Supabase (PRD_step6)
- CLI: `C:\dev\supabase-cli\node_modules\.bin\supabase.cmd` (the user's PowerShell blocks `npm`/`npx` scripts by
  execution policy — don't change it). Logged in already. Project ref = the subdomain of `SUPABASE_URL` in env.json.
- Deploy: `supabase.cmd functions deploy <name> --project-ref <ref> --use-api` (no Docker on this PC).
- Functions check login in code (`supabase/functions/_shared/http.ts`); keep `verify_jwt = false` per function in `supabase/config.toml`.
- Secrets: the user sets them in the dashboard (Edge Functions → Secrets). Verify with `secrets list`, printing names only.
- Never run `supabase/seed_dev.sql` on the real project (8 samples would hide the 2,803 bundled campsites).
- Test build with sample hikes: add `--dart-define=DEMO_RECORDS=true` (flask menu in the 기록 tab adds/removes 6 fake hikes).
  Remove the demo hikes on the phone afterwards and reinstall a normal build — never ship it.

## Hike records (PRD_step5)
- Device only: summaries in SharedPreferences `hike_records_v1`, tracks in `<app documents>/records/<id>.json`,
  the hike in progress in `records/active_track.jsonl`. Release builds aren't debuggable, so `adb run-as` can't read them.
- Analysis tuning constants are at the top of `lib/services/hike_analysis.dart`; change PRD_step5 "계산 규칙" with them.

## Data scripts
- `dart run tool/import_campsites.dart` → `assets/data/campsites.json`, `supabase/campsites_import.sql`
- `dart run tool/import_blog_spots.dart` → review list, then `assets/data/blog_spots.json` (Step 2)
- Pass Korean text via UTF-8 files, not command-line args (encoding breaks).
- `dart run tool/extract_character_assets.dart` → `assets/character/*` from `assets_src/character_sheet.webp`.
- Logo: edit `design/bivi_badge_dawn.svg` (chosen option 2). `python -I design/put_mascot_in_badge.py` re-embeds the mascot.
  Render PNGs with headless Edge (pages in `build/icon_render/*.html`, `msedge --headless=new --screenshot=… --window-size=…
  --default-background-color=00000000`) → `assets/images/bivi_badge.png`, `assets_src/icon/*.png`,
  then `dart run flutter_launcher_icons`. flutter_svg can't render the curved (textPath) text, so ship PNGs.
- In Bash, never put Markdown backticks inside double-quoted strings — they run as commands.

## Gotchas
- Release R8 strips JNI-called plugin classes → keep rules in `android/app/proguard-rules.pro` (added by `tool/setup_platform.dart`). Symptom: app stuck on splash.
- Mapbox custom styles must be Classic (Static Tiles API). Mapbox logo must stay visible on every map.
- Test on device: `C:\dev\android\platform-tools\adb.exe`, use `--user 0` for install/start.
  User's phones: Galaxy S23+ (R3CW202Q3PV, Vulkan) and Galaxy S10 5G (R3CM509YDKZ, OpenGLES — slower;
  reproduced the "no pins until the map moves" bug). Pass `-s <serial>` when both are connected.
  The S10 also has unrelated `com.bivi.app` / `com.bivi.app.staging` apps — don't touch them.
- New code: English comments. Existing comments are Korean.
- `MainActivity.kt` keeps one cached Flutter engine for the process (PRD_step5 5-5). Don't revert to the default
  per-activity engine: closing the app from recents would stop the location service and hike recording.
- Hike recording check on a device: swipe the app away mid-hike → `dumpsys activity services com.bivi.bivi` should still show
  `isForeground=true` and `cmd appops get com.bivi.bivi` MONITOR_HIGH_POWER_LOCATION "(running)".
- Changing `analyzeTrack` results → bump `hikeStatsVersion` (lib/models/hike_record.dart) so saved records get recomputed.
