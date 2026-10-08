import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Quick unlock: sign in again with fingerprint, face, pattern, PIN or password of the phone.
///
/// When it's turned on, the API gives this phone a long random key. The key is kept in the
/// phone's secure storage (Android Keystore / iOS Keychain) and is only read after the user passes
/// the phone's own lock check. The server swaps the key on every use and can revoke it.
class QuickUnlock {
  QuickUnlock._();

  static final _auth = LocalAuthentication();
  static const _store = FlutterSecureStorage();
  static const _keyName = 'mb_unlock_key';
  static const _whoName = 'mb_unlock_who';
  static const _uidName = 'mb_unlock_uid';

  /// True when this phone has a screen lock or biometrics the app can use.
  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// True when quick unlock is set up on this phone.
  static Future<bool> isEnabled() async => (await _read(_keyName)) != null;

  /// First name of the account quick unlock opens, for the sign-in screen.
  static Future<String?> who() => _read(_whoName);

  /// Id of the account quick unlock opens (one account per phone).
  static Future<String?> userId() => _read(_uidName);

  /// Shows the phone's fingerprint / face / screen-lock prompt. False if the user cancels or fails.
  static Future<bool> confirm(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> key() => _read(_keyName);

  static Future<void> save(String key, {String? who, String? userId}) async {
    await _store.write(key: _keyName, value: key);
    if (who != null) await _store.write(key: _whoName, value: who);
    if (userId != null) await _store.write(key: _uidName, value: userId);
  }

  static Future<void> clear() async {
    try {
      await _store.delete(key: _keyName);
      await _store.delete(key: _whoName);
      await _store.delete(key: _uidName);
    } catch (_) {}
  }

  static Future<String?> _read(String name) async {
    if (kIsWeb) return null;
    try {
      return await _store.read(key: name);
    } catch (_) {
      return null; // storage unavailable (e.g. widget tests): behave as if it's off
    }
  }
}
