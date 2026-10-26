package com.bivi.bivi

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // One Flutter engine per process instead of per screen (PRD_step5 5-5).
    // With the default engine, closing the app from the recent-apps list destroyed the engine, and the
    // location plugin then stopped its foreground service: hike recording silently stopped. The location
    // foreground service keeps the process alive, so the engine — and recording — carry on.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        FlutterEngineCache.getInstance().get(ENGINE_ID)
            ?: FlutterEngine(context.applicationContext).also {
                it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
                FlutterEngineCache.getInstance().put(ENGINE_ID, it)
            }

    override fun shouldDestroyEngineWithHost() = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Battery-optimization exemption, so the system is less likely to kill a long hike recording.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bivi/battery").setMethodCallHandler { call, result ->
            val app = applicationContext
            val power = app.getSystemService(Context.POWER_SERVICE) as PowerManager
            when (call.method) {
                "isIgnoringOptimizations" -> result.success(power.isIgnoringBatteryOptimizations(app.packageName))
                "requestIgnoreOptimizations" -> {
                    // System dialog; the user decides.
                    app.startActivity(
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${app.packageName}"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val ENGINE_ID = "bivi_main"
    }
}
