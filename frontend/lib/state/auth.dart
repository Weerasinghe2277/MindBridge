import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Result of the first sign-in step: either signed in, or another code is needed.
class LoginStep {
  LoginStep.done() : kind = 'done', email = '', devOtp = null;
  LoginStep.verify(this.email, this.devOtp) : kind = 'verify';
  LoginStep.twoFactor(this.email, this.devOtp) : kind = '2fa';
  final String kind;
  final String email;
  final String? devOtp;
}

/// No personal data is saved on the device: the sign-in token lives in memory only, so closing
/// the app signs the user out (all data stays on the server). The only thing kept on the device is
/// whether onboarding has been seen, so it shows once per install rather than on every launch.
class AuthState extends ChangeNotifier {
  AuthStatus status = AuthStatus.unknown;

  Map<String, dynamic>? user;
  bool onboardingSeen = false;

  /// Shown once on the sign-in screen after an automatic sign-out (NFR4).
  String? expiredMessage;

  /// Inactivity limit set by Student Affairs (mirrors the server's sign-out rule).
  int autoSignOutMinutes = 15;

  Future<void> _loadConfig() async {
    try {
      final r = await api.get('/config', background: true);
      autoSignOutMinutes = (r['autoSignOutMinutes'] as num?)?.toInt() ?? 15;
    } catch (_) {}
  }

  String get role => user?['role'] as String? ?? '';
  String get firstName => (user?['preferredName'] as String?) ?? (user?['name'] as String? ?? '').split(' ').first;
  bool get isVerifiedStaff => (user?['verification']?['status']) == 'approved';
  bool get isStaff => role == 'counsellor' || role == 'doctor';

  static String get device {
    if (kIsWeb) return 'Web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android phone',
      TargetPlatform.iOS => 'iPhone',
      _ => 'Device',
    };
  }

  static const _onboardingKey = 'onboarding_seen';

  Future<void> init() async {
    api.onSessionExpired = (e) => _expire(e.message);
    try {
      onboardingSeen = (await SharedPreferences.getInstance()).getBool(_onboardingKey) ?? false;
    } catch (_) {} // storage unavailable: show onboarding again, nothing else depends on it
    await _loadConfig();
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> markOnboardingSeen() async {
    if (!onboardingSeen) {
      onboardingSeen = true;
      notifyListeners();
    }
    try {
      await (await SharedPreferences.getInstance()).setBool(_onboardingKey, true);
    } catch (_) {}
  }

  Future<LoginStep> login(String email, String password) async {
    final r = await api.post('/auth/login', {'email': email.trim(), 'password': password, 'device': device});
    if (r['needsVerification'] == true) return LoginStep.verify(r['email'] as String, r['devOtp'] as String?);
    if (r['twoFactor'] == true) return LoginStep.twoFactor(r['email'] as String, r['devOtp'] as String?);
    await _signIn(r);
    return LoginStep.done();
  }

  Future<void> verifyEmail(String email, String code) async {
    final r = await api.post('/auth/verify-email', {'email': email, 'code': code, 'device': device});
    await _signIn(r);
  }

  Future<void> verifyTwoFactor(String email, String code) async {
    final r = await api.post('/auth/login/2fa', {'email': email, 'code': code, 'device': device});
    await _signIn(r);
  }

  Future<void> _signIn(Map<String, dynamic> r) async {
    api.token = r['token'] as String;
    user = r['user'] as Map<String, dynamic>;
    expiredMessage = null;
    status = AuthStatus.signedIn;
    _loadConfig();
    markOnboardingSeen(); // anyone who has signed in skips onboarding from now on
    notifyListeners();
  }

  Future<void> refreshUser() async {
    try {
      final r = await api.get('/me');
      user = r['user'] as Map<String, dynamic>;
      notifyListeners();
    } catch (_) {}
  }

  void setUser(Map<String, dynamic> u) {
    user = u;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {}
    await _clear();
    notifyListeners();
  }

  void _expire(String message) {
    if (status != AuthStatus.signedIn) return;
    expiredMessage = message;
    _clear().then((_) => notifyListeners());
  }

  /// Client-side mirror of the server's inactivity sign-out.
  void expireForInactivity(int minutes) =>
      _expire('For your privacy, MindBridge signs you out after $minutes minutes of inactivity.');

  Future<void> _clear() async {
    api.token = null;
    user = null;
    status = AuthStatus.signedOut;
  }
}
