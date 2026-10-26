// `flutter create` 직후 1회 실행: 위치 권한 / 백그라운드 위치 / 인터넷 권한을 네이티브 설정에 추가합니다.
//
//   flutter create . --project-name bivi --org com.bivi --platforms android,ios
//   dart run tool/setup_platform.dart
import 'dart:io';

void main() {
  _patchAndroid();
  _patchProguard();
  _patchIos();
  stdout.writeln('완료. 이제 `flutter pub get` 후 `flutter run` 하세요.');
}

void _patchAndroid() {
  final file = File('android/app/src/main/AndroidManifest.xml');
  if (!file.existsSync()) {
    stderr.writeln('[android] AndroidManifest.xml 없음 — flutter create 를 먼저 실행하세요.');
    return;
  }
  var xml = file.readAsStringSync();
  const permissions = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.WAKE_LOCK',
    // Battery-optimization exemption prompt for long hike recordings (PRD_step5 5-5).
    'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
  ];
  final missing = permissions
      .where((p) => !xml.contains('"$p"'))
      .map((p) => '    <uses-permission android:name="$p"/>')
      .join('\n');
  if (missing.isEmpty) {
    stdout.writeln('[android] 이미 적용됨');
    return;
  }
  final idx = xml.indexOf('<application');
  xml = '${xml.substring(0, idx)}${missing.trimLeft()}\n\n    ${xml.substring(idx)}';
  file.writeAsStringSync(xml);
  stdout.writeln('[android] 권한 추가 완료');
}

/// 릴리스 빌드의 R8 이 JNI 로만 호출되는 플러그인 · 코틀린 코루틴 클래스를 지워
/// 앱이 스플래시에서 멈추는 문제를 막는다 (shared_preferences_android 등).
void _patchProguard() {
  final gradle = File('android/app/build.gradle.kts');
  if (!gradle.existsSync()) return;
  File('android/app/proguard-rules.pro').writeAsStringSync('''
-keep class io.flutter.plugins.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
''');
  var s = gradle.readAsStringSync();
  if (s.contains('proguard-rules.pro')) return;
  const anchor = 'signingConfig = signingConfigs.getByName("debug")';
  s = s.replaceFirst(anchor, '''$anchor
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )''');
  gradle.writeAsStringSync(s);
  stdout.writeln('[android] R8 keep 규칙 추가 완료');
}

void _patchIos() {
  final file = File('ios/Runner/Info.plist');
  if (!file.existsSync()) {
    stderr.writeln('[ios] Info.plist 없음 — iOS 플랫폼을 생성하지 않았다면 무시하세요.');
    return;
  }
  var plist = file.readAsStringSync();
  if (plist.contains('NSLocationWhenInUseUsageDescription')) {
    stdout.writeln('[ios] 이미 적용됨');
    return;
  }
  const entries = '''
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>산행 모드에서 현재 좌표와 고도를 기기에 저장해 오프라인 SOS 카드에 표시합니다.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>화면이 꺼져 있어도 산행 중 위치를 주기적으로 기기에 저장해 비상 시 좌표를 제공합니다.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>location</string>
	</array>
''';
  final idx = plist.lastIndexOf('</dict>');
  plist = '${plist.substring(0, idx)}$entries${plist.substring(idx)}';
  file.writeAsStringSync(plist);
  stdout.writeln('[ios] Info.plist 권한 설명 추가 완료');
}
