# JNI 로 Dart 에서 직접 호출되는 클래스는 R8 이 사용처를 못 봐서 지워버린다.
# (shared_preferences_android, path_provider_android 등 jnigen 기반 플러그인 + 이들이 쓰는 코루틴 런타임)
-keep class io.flutter.plugins.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
