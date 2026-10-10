import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');
  static String? _customUrl;

  static const String defaultLanIp = '192.168.78.102';

  static String get customUrl => _customUrl ?? '';

  static Future<void> loadCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _customUrl = prefs.getString('custom_api_base_url');
  }

  static Future<void> setCustomUrl(String url) async {
    _customUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    if (_customUrl!.isEmpty) {
      await prefs.remove('custom_api_base_url');
      _customUrl = null;
    } else {
      await prefs.setString('custom_api_base_url', _customUrl!);
    }
  }

  static String get baseUrl {
    if (_customUrl != null && _customUrl!.isNotEmpty) {
      return _customUrl!;
    }
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        return 'http://$host:5000';
      }
      return 'http://127.0.0.1:5000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://$defaultLanIp:5000';
    }
    return 'http://127.0.0.1:5000';
  }
}