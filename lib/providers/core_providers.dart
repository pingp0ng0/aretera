import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../services/offline_tile_cache.dart';

/// main() 에서 비동기 초기화 후 override 되는 싱글턴들
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main()에서 override 해야 합니다'),
);

final tileCacheProvider = Provider<OfflineTileCache>(
  (ref) => throw UnimplementedError('main()에서 override 해야 합니다'),
);

/// Folder for hike tracks (`<documents>/records`), overridden in main().
final recordsDirProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('main()에서 override 해야 합니다'),
);

/// Supabase 키가 없거나 초기화에 실패하면 null → 로컬 전용 모드
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

/// 카운트다운 · 'N분 전' 표시용 1초 틱
final nowProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);
