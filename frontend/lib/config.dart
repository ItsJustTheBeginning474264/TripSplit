class AppConfig {
  /// Address of the Flask backend.
  ///  * Android emulator  -> http://10.0.2.2:5000   (10.0.2.2 is the host computer)
  ///  * iOS simulator / desktop / web -> http://127.0.0.1:5000
  ///  * real phone        -> http://<your-computer-LAN-IP>:5000
  /// Override without editing code:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );
}
