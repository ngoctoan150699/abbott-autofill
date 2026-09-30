import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppPreferences {
  static const MethodChannel _channel =
      MethodChannel('abbott_helper/preferences');
  static final Map<String, String> _memoryCache = <String, String>{};
  static bool _isInitialized = false;

  static File? _getFile() {
    try {
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ??
            Platform.environment['LOCALAPPDATA'] ??
            Directory.current.path;
        final dir = Directory('$appData\\abbott_helper');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return File('${dir.path}\\preferences.json');
      }
    } catch (e) {
      debugPrint('Error getting preferences file: $e');
    }
    return null;
  }

  static Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (Platform.isWindows) {
      try {
        final file = _getFile();
        if (file != null && file.existsSync()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            final Map<String, dynamic> decoded = jsonDecode(content);
            decoded.forEach((key, value) {
              if (value != null) {
                _memoryCache[key] = value.toString();
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading preferences from disk on Windows: $e');
      }
    }
  }

  static Future<String?> getString(String key) async {
    if (!_isInitialized) {
      await init();
    }

    if (Platform.isWindows) {
      return _memoryCache[key];
    }

    try {
      final value =
          await _channel.invokeMethod<String>('getString', {'key': key});
      if (value != null) {
        _memoryCache[key] = value;
      }
      return value ?? _memoryCache[key];
    } catch (_) {
      return _memoryCache[key];
    }
  }

  static Future<void> setString(String key, String value) async {
    if (!_isInitialized) {
      await init();
    }

    _memoryCache[key] = value;

    if (Platform.isWindows) {
      try {
        final file = _getFile();
        if (file != null) {
          await file.writeAsString(jsonEncode(_memoryCache), flush: true);
        }
      } catch (e) {
        debugPrint('Error saving preferences to disk on Windows: $e');
      }
      return;
    }

    try {
      await _channel
          .invokeMethod<void>('setString', {'key': key, 'value': value});
    } catch (_) {
      // Fallback: save to file if channel fails on any other platform
      try {
        final file = _getFile();
        if (file != null) {
          await file.writeAsString(jsonEncode(_memoryCache), flush: true);
        }
      } catch (_) {}
    }
  }
}
