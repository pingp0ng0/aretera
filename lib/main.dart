import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient;

import 'config/env.dart';
import 'providers/core_providers.dart';
import 'screens/home_shell.dart';
import 'services/offline_tile_cache.dart';
import 'services/server_session.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 릴리스 빌드에서도 위젯 오류를 회색 화면 대신 메시지로 보여준다
  ErrorWidget.builder = (details) => _ErrorText(details.exceptionAsString());

  // 초기화 중 예외가 나면 스플래시에서 멈추지 않고 오류 화면을 띄운다
  try {
    final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 10));
    final docs = await _documentsDir();

    SupabaseClient? supabase;
    if (Env.hasSupabase) {
      try {
        await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey)
            .timeout(const Duration(seconds: 10));
        supabase = Supabase.instance.client;
        // Sign in anonymously in the background so the first server call is quick.
        // Offline is fine: functions retry the sign-in when they are used (PRD_step6).
        unawaited(ensureSignedIn(supabase).catchError((Object e) => debugPrint('anonymous sign-in later: $e')));
      } catch (e) {
        debugPrint('Supabase init failed — running local-only: $e');
      }
    }

    runApp(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          tileCacheProvider.overrideWithValue(OfflineTileCache(Directory('${docs.path}/tiles'))),
          recordsDirProvider.overrideWithValue(Directory('${docs.path}/records')),
          supabaseClientProvider.overrideWithValue(supabase),
        ],
        child: const BiviApp(),
      ),
    );
  } catch (e, st) {
    runApp(StartupErrorApp(error: e, stack: st));
  }
}

/// 앱 문서 폴더 (오프라인 타일 · 산행 기록). 못 얻으면 임시 폴더로 대체해 시작은 되게 한다.
Future<Directory> _documentsDir() async {
  try {
    return await getApplicationDocumentsDirectory().timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('documents dir unavailable, using temp: $e');
    return Directory('${Directory.systemTemp.path}/bivi');
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildBiviTheme(),
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('앱을 시작하지 못했습니다',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BiviColors.amber)),
              const SizedBox(height: 8),
              const Text('아래 내용을 캡처해서 개발자에게 보내주세요.',
                  style: TextStyle(color: BiviColors.textSecondary)),
              const SizedBox(height: 16),
              SelectableText('$error\n\n$stack', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF2A1A12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          '오류: $message',
          textDirection: TextDirection.ltr,
          style: const TextStyle(color: BiviColors.amber, fontSize: 12),
        ),
      ),
    );
  }
}

class BiviApp extends StatelessWidget {
  const BiviApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildBiviTheme();
    return MaterialApp(
      title: 'Bivi',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}
