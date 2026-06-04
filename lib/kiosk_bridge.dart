import 'package:flutter/services.dart';

class KioskBridge {
  static const _ch = MethodChannel('com.mdm.test/kiosk');
  static const _events = EventChannel('com.mdm.test/events');

  static Future<String> getLaunchReason() async =>
      await _ch.invokeMethod('getLaunchReason') ?? 'unknown';

  static Future<bool> isDeviceOwner() async =>
      await _ch.invokeMethod('isDeviceOwner') ?? false;

  static Future<bool> isAdminActive() async =>
      await _ch.invokeMethod('isAdminActive') ?? false;

  static Future<Map<String, String>> getAppVersion() async {
    final res = await _ch.invokeMapMethod<String, String>('getAppVersion');
    return res ?? {};
  }

  static Future<Map<String, String>> getManagedConfig() async {
    final res = await _ch.invokeMapMethod<String, String>('getManagedConfig');
    return res ?? {};
  }

  static Stream<Map<String, dynamic>> get mdmEventStream =>
      _events.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));

  static Future<void> enterKiosk() => _ch.invokeMethod('enterKiosk');
  static Future<void> exitKiosk() => _ch.invokeMethod('exitKiosk');
}
