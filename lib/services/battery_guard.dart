import 'package:flutter/services.dart';

/// Battery-optimization exemption on Android, through MainActivity's "bivi/battery" channel
/// (PRD_step5 5-5). Exempt apps are much less likely to be killed during a long hike.
class BatteryGuard {
  BatteryGuard._();

  static const _channel = MethodChannel('bivi/battery');

  /// true = exempt, false = optimized, null = unknown (not Android, or no channel as in tests).
  static Future<bool?> isUnrestricted() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoringOptimizations');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Opens the system "allow / deny" dialog; the user decides.
  static Future<void> requestUnrestricted() async {
    try {
      await _channel.invokeMethod<void>('requestIgnoreOptimizations');
    } on MissingPluginException {
      // Not available on this platform.
    } on PlatformException {
      // Dialog couldn't be opened; the tip stays visible.
    }
  }
}
