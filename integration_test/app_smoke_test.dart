import 'package:bluefield_test/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The two things that matter most before shipping to a platform this
/// app has never actually run on: does it even launch, and can a real
/// person actually sign in and reach their dashboard? This calls the
/// real app.main() — the exact same bootstrap a real device runs,
/// including Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
/// — so a missing/broken platform case in firebase_options.dart (the
/// bug that made this app crash instantly on iOS the first time this
/// was checked) fails loudly right here instead of silently shipping.
///
/// The sign-in portion only runs when TEST_EMAIL/TEST_PASSWORD are
/// supplied via --dart-define (set as secret environment variables in
/// Codemagic, never committed to this repo) — without them it's
/// skipped so the launch check still runs cleanly for anyone building
/// locally without CI credentials configured. Use one of the seeded
/// demo accounts (see lib/dev/demo_constants.dart /
/// lib/dev/demo_data_seeder.dart) for this — they're synthetic,
/// isolated from any real company's data, and safe to sign into
/// repeatedly from automation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testEmail = String.fromEnvironment('TEST_EMAIL');
  const testPassword = String.fromEnvironment('TEST_PASSWORD');

  testWidgets('app launches, and signs in to reach a real dashboard', (tester) async {
    app.main();

    // Generous settle window — first launch does real Firebase/network
    // work before the first frame that matters renders.
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // Signed out on a fresh simulator install, so AuthGate should land
    // on WelcomeScreen — these strings only ever appear there.
    expect(find.text('BlueField'), findsWidgets);
    expect(find.text('Sign In'), findsWidgets);

    // Also click through to the sign-in screen itself, since that's
    // the very next thing every real user actually reaches.
    await tester.tap(find.text('Sign In').first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Welcome Back'), findsOneWidget);

    if (testEmail.isEmpty || testPassword.isEmpty) {
      // No CI test account configured yet — the launch check above is
      // still real coverage, just stop here rather than fail on
      // credentials nobody supplied.
      return;
    }

    // Email field, then password field — in that order on this form.
    final formFields = find.byType(TextFormField);
    await tester.enterText(formFields.at(0), testEmail);
    await tester.enterText(formFields.at(1), testPassword);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);

    // Real sign-in: a Firebase Auth round trip, then Firestore reads
    // for the user's profile/membership/employee doc before a
    // dashboard can render — slower than local navigation, so a
    // longer settle window than the steps above.
    await tester.pumpAndSettle(const Duration(seconds: 15));

    // A successful sign-in may offer to enable biometric quick
    // sign-in — dismiss it if it shows up so it doesn't block the
    // dashboard assertion below.
    final notNow = find.text('Not Now');
    if (notNow.evaluate().isNotEmpty) {
      await tester.tap(notNow);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // Every role (owner/manager/employee) lands on a Scaffold with a
    // bottom NavigationBar — the one thing all three dashboards share,
    // so this proves a real sign-in reached a real, rendered dashboard
    // without hardcoding which role the test account happens to have.
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
