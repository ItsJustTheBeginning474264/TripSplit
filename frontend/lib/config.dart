import 'package:flutter/foundation.dart';

class AppConfig {
  /// Set this at build/run time to override the automatic choice:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5000
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Address of the Flask backend.
  ///  * Chrome / Edge (web), Windows / macOS / Linux desktop, iOS simulator -> http://127.0.0.1:5000
  ///  * Android emulator -> http://10.0.2.2:5000 (10.0.2.2 is the host computer)
  ///  * Real phone       -> pass --dart-define=API_BASE_URL=http://<your-PC-LAN-IP>:5000
  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://127.0.0.1:5000';
  }
}