import 'package:flutter/services.dart';

class AppPreferences {
  static const MethodChannel _channel = MethodChannel('abbott_helper/preferences');
  static final Map<String, String> _memoryCache = <String, String>{};

  static Future<String?> getString(String key) async {
    try {
      final value = await _channel.invokeMethod<String>('getString', {'key': key});
      if (value != null) {
        _memoryCache[key] = value;
      }
      return value ?? _memoryCache[key];
    } catch (_) {
      return _memoryCache[key];
    }
  }

  static Future<void> setString(String key, String value) async {
    _memoryCache[key] = value;
    try {
      await _channel.invokeMethod<void>('setString', {'key': key, 'value': value});
    } catch (_) {
      // Keep the value in memory if native storage is temporarily unavailable.
    }
  }
}
