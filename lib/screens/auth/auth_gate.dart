import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../Models/company_model.dart';
import '../../Services/auth_service.dart';
import '../../Services/biometric_auth_service.dart';
import '../../theme/app_theme.dart';
import '../dashboard_screen.dart';
import '../employer_dashboard_screen.dart';
import '../manager_dashboard_screen.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';

/// Root router: decides what a signed-in user sees based on their
/// AuthUserProfile (auth_service.dart) — which itself now reflects
/// membership status and company activation, not just "is there a user
/// doc." Session-expiry is handled implicitly: if Firebase invalidates
/// the session, authStateChanges emits null and this falls back to
/// WelcomeScreen on its own, no special-casing needed here.
///
/// Also enforces quick sign-in (Settings > Security) BEFORE the normal
/// signed-in/signed-out routing below ever runs — a StatefulWidget now
/// (it wasn't before) so it can remember, per app-process-lifetime,
/// whether this session has already cleared it, without re-prompting
/// biometrics on every unrelated rebuild.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final BiometricAuthService _biometricService = BiometricAuthService();

  bool _unlockedThisSession = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _biometricService.isEnabled(),
      builder: (context, enabledSnapshot) {
        if (enabledSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final quickSignInEnabled = enabledSnapshot.data ?? false;
        if (quickSignInEnabled && !_unlockedThisSession) {
          return _BiometricUnlockScreen(
            onUnlocked: () => setState(() => _unlockedThisSession = true),
          );
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            if (!authSnapshot.hasData) {
              // Fully signed out — any prior unlock no longer applies,
              // so the next sign-in (even by the same person) always
              // has to clear quick sign-in again rather than inheriting
              // a stale unlock.
              _unlockedThisSession = false;
              return const WelcomeScreen();
            }

            return StreamBuilder<AuthUserProfile>(
              stream: AuthService().watchCurrentUserProfile(),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingScreen();
                }

                if (profileSnapshot.hasError) {
                  return _AuthErrorScreen(
                    message: profileSnapshot.error.toString(),
                  );
                }

                final profile = profileSnapshot.data;

                if (profile == null) {
                  return const _AuthErrorScreen(
                    message: 'Unable to load user profile.',
                  );
                }

                // Each blocking condition gets its own specific message
                // (Section 2: disabled-account / archived-employee /
                // suspended-company / expired-subscription handling) rather
                // than one generic "not active" message that leaves the
                // person guessing what actually happened.
                if (!profile.isCompanyActive) {
                  return const _AuthErrorScreen(
                    message:
                        "Your company's account has been suspended. Contact your company owner or BlueField support.",
                  );
                }

                if (profile.companySubscriptionStatus ==
                    CompanySubscriptionStatus.cancelled) {
                  return const _AuthErrorScreen(
                    message:
                        "This company's subscription has ended. Contact your company owner to reactivate.",
                  );
                }

                if (profile.isMembershipArchived) {
                  return const _AuthErrorScreen(
                    message:
                        'Your access to this company has been archived. Contact your company owner.',
                  );
                }

                if (profile.isMembershipSuspended) {
                  return const _AuthErrorScreen(
                    message: 'Your account has been suspended. Contact your company owner.',
                  );
                }

                if (profile.requiresPasswordChange) {
                  return const ChangePasswordScreen();
                }

                if (profile.isOwnerRole) {
                  return const EmployerDashboardScreen();
                }

                if (profile.isManagerRole) {
                  return const ManagerDashboardScreen();
                }

                if (profile.isEmployeeRole) {
                  return const EmployeeDashboardScreen();
                }

                return _AuthErrorScreen(
                  message: 'Unknown account role: ${profile.role}',
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Shown on every cold start while quick sign-in is enabled and this
/// app process hasn't cleared it yet — whether or not Firebase still
/// has a live session underneath (BiometricAuthService.unlock handles
/// both cases). A successful check requires nothing typed at all,
/// which is the whole point; "Use Password Instead" is the fallback
/// for a changed password, a new/unenrolled device, or a biometric
/// check that just won't cooperate.
class _BiometricUnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const _BiometricUnlockScreen({required this.onUnlocked});

  @override
  State<_BiometricUnlockScreen> createState() => _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends State<_BiometricUnlockScreen> {
  final BiometricAuthService _biometricService = BiometricAuthService();
  bool _checking = false;
  bool _lastAttemptFailed = false;

  @override
  void initState() {
    super.initState();
    // Prompt immediately on arrival rather than waiting for a tap —
    // the manual button below still covers retry after a cancel/fail.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUnlock());
  }

  Future<void> _attemptUnlock() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _lastAttemptFailed = false;
    });

    final success = await _biometricService.unlock();

    if (!mounted) return;
    if (success) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _lastAttemptFailed = true;
    });
  }

  Future<void> _usePasswordInstead() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
    if (!mounted) return;
    // LoginScreen only pops itself after a successful sign-in — that's
    // equally valid proof of identity, so it clears this gate too.
    if (FirebaseAuth.instance.currentUser != null) {
      widget.onUnlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint, size: 56, color: AppTheme.blue),
                  const SizedBox(height: 18),
                  const Text(
                    'Sign In to BlueField',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _lastAttemptFailed
                        ? 'That didn\'t go through — try again, or sign in with your password.'
                        : 'Verify it\'s you with your fingerprint or Face ID.',
                    style: const TextStyle(color: AppTheme.mutedText),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _attemptUnlock,
                      icon: _checking
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.fingerprint),
                      label: Text(_checking ? 'Checking...' : 'Unlock'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _checking ? null : _usePasswordInstead,
                    child: const Text('Use Password Instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _AuthErrorScreen extends StatelessWidget {
  final String message;

  const _AuthErrorScreen({
    required this.message,
  });

  Future<void> _logout() async {
    await AuthService().logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 46,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Account Setup Problem',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _logout,
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
