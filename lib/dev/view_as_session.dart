import 'package:flutter/foundation.dart';

/// Tracks an in-progress "View As" session for the demo tooling — the
/// Owner has signed the app OUT of their own account and INTO a seeded
/// employee's real account (see view_as_screen.dart) so every screen
/// genuinely behaves as that employee, with no separate preview mode
/// or plumbing anywhere else in the app.
///
/// The one thing that approach doesn't get for free is getting BACK to
/// the Owner's account afterward — Firebase Auth has no "switch back"
/// primitive, and this tool never has the Owner's real password on
/// hand to sign back in with. So the Owner is asked to re-enter it
/// once, right before switching away, and it's held ONLY in memory
/// (never written to Firestore or disk) for the return trip, then
/// cleared as soon as it's successfully used.
///
/// [activeNotifier] backs a small persistent banner wired up in
/// main.dart's MaterialApp.builder — a ValueNotifier rather than
/// static fields alone, since that banner has to react live to
/// begin()/clear() from wherever it sits in the widget tree at the
/// time (top of a rebuilt Navigator stack, not a descendant of
/// whatever called begin()).
class ViewAsSession {
  ViewAsSession._();

  static String? _ownerEmail;
  static String? _ownerPassword;
  static String? employeeLabel;

  static final ValueNotifier<bool> activeNotifier = ValueNotifier<bool>(false);

  static bool get isActive => activeNotifier.value;

  static void begin({
    required String ownerEmail,
    required String ownerPassword,
    required String employeeLabel,
  }) {
    _ownerEmail = ownerEmail;
    _ownerPassword = ownerPassword;
    ViewAsSession.employeeLabel = employeeLabel;
    activeNotifier.value = true;
  }

  /// Looks at the cached owner credentials without clearing them, so a
  /// failed sign-back-in attempt (e.g. the Owner mistyped their
  /// password when starting "View As") can be retried from the banner
  /// instead of losing the only way back. Call [clear] explicitly once
  /// the sign-in actually succeeds.
  static ({String email, String password})? peekOwnerCredentials() {
    final email = _ownerEmail;
    final password = _ownerPassword;
    if (email == null || password == null) return null;
    return (email: email, password: password);
  }

  static void clear() {
    _ownerEmail = null;
    _ownerPassword = null;
    employeeLabel = null;
    activeNotifier.value = false;
  }
}
