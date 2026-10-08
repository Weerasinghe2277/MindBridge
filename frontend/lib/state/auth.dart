import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/quick_unlock.dart';

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
/// the app signs the user out (all data stays on the server). The device keeps whether onboarding
/// has been seen and, if the user turns it on, a quick-unlock key in secure storage that is only
/// released after fingerprint, face or screen-lock confirmation.
class AuthState extends ChangeNotifier {
  AuthStatus status = AuthStatus.unknown;

  Map<String, dynamic>? user;
  bool onboardingSeen = false;

  /// Quick unlock is set up on this phone (and whose account it opens).
  bool quickUnlockOn = false;
  String? quickUnlockName;
  String? _quickUnlockUserId;

  /// Quick unlock on this phone opens the signed-in account (shown as the settings switch).
  bool get quickUnlockForMe => quickUnlockOn && user != null && _quickUnlockUserId == user!['id'];

  /// Locked after inactivity (quick unlock users only): still signed in, screen covered until
  /// the user confirms with fingerprint, face, pattern or PIN.
  bool locked = false;

  /// Set after a password sign-in on a phone that could use quick unlock; the app offers it once.
  bool offerQuickUnlock = false;

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
  static const _offeredKey = 'quick_unlock_offered';

  Future<void> init() async {
    api.onSessionExpired = (e) {
      // With quick unlock on, an ended session just locks the app; unlocking starts a new one.
      if (e.code == 'SESSION_EXPIRED' && quickUnlockForMe) {
        lock();
      } else {
        _expire(e.message);
      }
    };
    try {
      onboardingSeen = (await SharedPreferences.getInstance()).getBool(_onboardingKey) ?? false;
    } catch (_) {} // storage unavailable: show onboarding again, nothing else depends on it
    await _loadQuickUnlock();
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
    await _signIn(r, withPassword: true);
    return LoginStep.done();
  }

  Future<void> verifyEmail(String email, String code) async {
    final r = await api.post('/auth/verify-email', {'email': email, 'code': code, 'device': device});
    await _signIn(r, withPassword: true);
  }

  Future<void> verifyTwoFactor(String email, String code) async {
    final r = await api.post('/auth/login/2fa', {'email': email, 'code': code, 'device': device});
    await _signIn(r, withPassword: true);
  }

  // ---------- Quick unlock ----------

  Future<void> _loadQuickUnlock() async {
    quickUnlockOn = await QuickUnlock.isEnabled();
    quickUnlockName = quickUnlockOn ? await QuickUnlock.who() : null;
    _quickUnlockUserId = quickUnlockOn ? await QuickUnlock.userId() : null;
  }

  /// Signs in with fingerprint, face or screen lock. Returns false if the user cancelled the
  /// prompt; throws [ApiException] if the server no longer accepts this phone's key.
  Future<bool> unlockWithDevice() async {
    final key = await QuickUnlock.key();
    if (key == null) return false;
    if (!await QuickUnlock.confirm('Unlock MindBridge')) return false;
    try {
      final r = await api.post('/auth/quick-unlock/sign-in', {'unlockKey': key, 'device': device});
      await QuickUnlock.save(r['unlockKey'] as String);
      await _signIn(r);
      return true;
    } on ApiException catch (e) {
      if (e.code == 'QUICK_UNLOCK_INVALID') {
        await QuickUnlock.clear();
        await _loadQuickUnlock();
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Turns quick unlock on for this phone, after the user confirms with the phone's own lock.
  /// Returns false if they cancelled.
  Future<bool> enableQuickUnlock() async {
    if (!await QuickUnlock.confirm('Confirm it’s you to turn on quick unlock')) return false;
    await _registerQuickUnlock();
    return true;
  }

  /// Gets a new key for this phone (e.g. after a password change turned keys off on the server).
  Future<void> renewQuickUnlock() async {
    if (quickUnlockForMe) await _registerQuickUnlock();
  }

  Future<void> _registerQuickUnlock() async {
    // One account per phone: setting it up replaces another account's key.
    final old = await QuickUnlock.key();
    if (old != null && !quickUnlockForMe) {
      try {
        await api.post('/auth/quick-unlock/remove', {'unlockKey': old});
      } catch (_) {}
    }
    final r = await api.post('/auth/quick-unlock', {'device': device});
    final u = r['user'] as Map<String, dynamic>;
    await QuickUnlock.save(r['unlockKey'] as String, who: (u['preferredName'] as String?) ?? (u['name'] as String? ?? '').split(' ').first, userId: u['id'] as String?);
    user = r['user'] as Map<String, dynamic>;
    await _loadQuickUnlock();
    notifyListeners();
  }

  Future<void> disableQuickUnlock() async {
    final key = await QuickUnlock.key();
    if (key != null) {
      try {
        await api.post('/auth/quick-unlock/remove', {'unlockKey': key});
      } catch (_) {} // the key expires on the server anyway
    }
    await QuickUnlock.clear();
    await _loadQuickUnlock();
    if (status == AuthStatus.signedIn) await refreshUser();
    notifyListeners();
  }

  Future<void> _maybeOfferQuickUnlock() async {
    if (quickUnlockForMe || !await QuickUnlock.isAvailable()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_offeredKey) == true) return;
      await prefs.setBool(_offeredKey, true);
      offerQuickUnlock = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _signIn(Map<String, dynamic> r, {bool withPassword = false}) async {
    api.token = r['token'] as String;
    user = r['user'] as Map<String, dynamic>;
    expiredMessage = null;
    status = AuthStatus.signedIn;
    _loadConfig();
    markOnboardingSeen(); // anyone who has signed in skips onboarding from now on
    notifyListeners();
    if (withPassword) _maybeOfferQuickUnlock();
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

  /// Client-side mirror of the server's inactivity sign-out. With quick unlock on, the app locks
  /// instead, so the user keeps their place and unlocks with fingerprint, face, pattern or PIN.
  void expireForInactivity(int minutes) {
    if (quickUnlockForMe) {
      lock();
    } else {
      _expire('For your privacy, MindBridge signs you out after $minutes minutes of inactivity.');
    }
  }

  void lock() {
    if (status != AuthStatus.signedIn || locked) return;
    locked = true;
    notifyListeners();
  }

  /// Unlocks with the phone's lock check and a fresh session from the quick-unlock key, keeping
  /// the current screen. Returns false if the user cancelled the prompt.
  Future<bool> unlock() async {
    final key = await QuickUnlock.key();
    if (key == null) {
      _expire('Sign in with your password to continue.');
      return false;
    }
    if (!await QuickUnlock.confirm('Unlock MindBridge')) return false;
    try {
      final r = await api.post('/auth/quick-unlock/sign-in', {'unlockKey': key, 'device': device});
      await QuickUnlock.save(r['unlockKey'] as String);
      api.token = r['token'] as String; // the old session ends on the server by itself
      user = r['user'] as Map<String, dynamic>;
      locked = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isNetwork) rethrow;
      if (e.code == 'QUICK_UNLOCK_INVALID') {
        await QuickUnlock.clear();
        await _loadQuickUnlock();
      }
      locked = false;
      _expire(e.message);
      return false;
    }
  }

  Future<void> _clear() async {
    api.token = null;
    user = null;
    locked = false;
    status = AuthStatus.signedOut;
  }
}
