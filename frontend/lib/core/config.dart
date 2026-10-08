import 'package:flutter/foundation.dart';

/// Where the MindBridge API lives.
///
/// Debug runs (VS Code / emulator) use the API on this computer; release builds
/// use the deployed server.
/// Override at build time with:
///   flutter run --dart-define=API_URL=http://192.168.1.20:4000/api
class AppConfig {
  static const _fromEnv = String.fromEnvironment('API_URL');

  /// The deployed API on Render, used by release builds (APK / web).
  static const productionApiUrl = 'https://mindbridge-api-s4xi.onrender.com/api';

  static String get apiBaseUrl {
    if (_fromEnv.isNotEmpty) return _fromEnv;
    if (kReleaseMode) return productionApiUrl;
    if (kIsWeb) return 'http://localhost:4000/api';
    // The Android emulator reaches the host machine through 10.0.2.2.
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:4000/api';
    return 'http://localhost:4000/api';
  }

  /// Origin of the API, used to open one-time download links.
  static String get apiOrigin => apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');

  static const helplineNumber = '1926';
  static const childWomenHelpline = '1929';
}
