import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// True quick sign-in via the device's fingerprint/Face ID sensor: a
/// successful biometric check alone gets you into the app, with
/// nothing typed. This is NOT a second factor layered on top of a
/// password — it's a faster way to supply the same email/password
/// Firebase Auth already requires, or (when a session is already
/// alive, which is the common case since Firebase persists sign-in
/// across app restarts on its own) simply confirming it's really the
/// account holder before showing that already-signed-in session.
///
/// The credential is what actually authenticates; biometrics only gate
/// LOCAL retrieval of it from the OS-level secure store (Keychain on
/// iOS, an encrypted Keystore-backed store on Android via
/// flutter_secure_storage) — the same "unlock a stored password with
/// your fingerprint" pattern used by password managers and most
/// banking apps' quick-login, not a custom auth scheme.
class BiometricAuthService {
  static const _emailKey = 'biometricLogin.email';
  static const _passwordKey = 'biometricLogin.password';
  static const _enabledKey = 'biometricLogin.enabled';

  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;
  final FirebaseAuth _firebaseAuth;

  BiometricAuthService({
    LocalAuthentication? localAuth,
    FlutterSecureStorage? secureStorage,
    FirebaseAuth? firebaseAuth,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  /// Whether THIS device has usable biometric hardware with at least
  /// one fingerprint/face already enrolled in the OS. False on
  /// desktop/web, devices with no sensor, or a sensor nothing is
  /// enrolled on — in any of those cases there's nothing for [unlock]
  /// to actually check against, so quick sign-in should never even
  /// offer itself as an option.
  Future<bool> isDeviceSupported() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final deviceSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !deviceSupported) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Per-device by design (secure storage is device-local) — enabling
  /// it on a phone never enables it on a tablet.
  Future<bool> isEnabled() async {
    final value = await _secureStorage.read(key: _enabledKey);
    return value == 'true';
  }

  /// Stores the just-verified credentials behind the device's
  /// biometric sensor for next time. Requires a fresh biometric
  /// success right here, separate from whatever login just happened —
  /// turning this on always means the person holding the device right
  /// now proved it's them, not just whoever happened to type the
  /// password. Returns false (without storing anything) if that check
  /// fails or is cancelled.
  Future<bool> enable({required String email, required String password}) async {
    final verified = await _promptBiometric(
      reason: 'Confirm it\'s you to enable quick sign-in.',
    );
    if (!verified) return false;

    await _secureStorage.write(key: _emailKey, value: email);
    await _secureStorage.write(key: _passwordKey, value: password);
    await _secureStorage.write(key: _enabledKey, value: 'true');
    return true;
  }

  /// Wipes the stored credential entirely — not just flipping the
  /// enabled flag off, so nothing sensitive is left behind in secure
  /// storage once someone turns this off.
  Future<void> disable() async {
    await _secureStorage.delete(key: _emailKey);
    await _secureStorage.delete(key: _passwordKey);
    await _secureStorage.write(key: _enabledKey, value: 'false');
  }

  /// The one entry point both AuthGate (opening the app while a
  /// Firebase session is still alive) and LoginScreen (opening the app
  /// after an explicit sign-out, when there's no session to fall back
  /// on) call — same biometric check either way, just a different
  /// amount of work behind it depending on whether Firebase already
  /// has a signed-in user:
  ///   - already signed in: the biometric check alone is enough to
  ///     let that session through — no need to touch Firebase again.
  ///   - signed out: retrieves the stored credential and actually
  ///     signs in with it, exactly like typing it in would have.
  /// Returns false if quick sign-in isn't enabled, the biometric
  /// prompt fails/is cancelled, the stored credential is missing (e.g.
  /// cleared externally), or the resulting sign-in attempt fails (e.g.
  /// the password was changed elsewhere since it was stored).
  Future<bool> unlock() async {
    if (!await isEnabled()) return false;

    final verified = await _promptBiometric(reason: 'Sign in to BlueField.');
    if (!verified) return false;

    if (_firebaseAuth.currentUser != null) {
      return true;
    }

    final email = await _secureStorage.read(key: _emailKey);
    final password = await _secureStorage.read(key: _passwordKey);
    if (email == null || password == null) return false;

    try {
      await _firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _promptBiometric({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        // biometricOnly is deliberate: this must never silently fall
        // back to the device's PIN/pattern (the OS-level screen lock —
        // anyone who knows it can unlock the whole phone), since that's
        // not proof it's specifically the account holder standing there.
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
