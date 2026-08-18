import 'package:bluefield_test/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The one test that matters most before shipping to a platform this
/// app has never actually run on: does it even launch? This calls the
/// real app.main() — the exact same bootstrap a real device runs,
/// including Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
/// — so a missing/broken platform case in firebase_options.dart (the
/// bug that made this app crash instantly on iOS the first time this
/// was checked) fails loudly right here instead of silently shipping.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches to the Welcome screen without crashing', (tester) async {
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
  });
}
