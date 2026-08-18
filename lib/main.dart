import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../dev/view_as_session.dart';
import '../firebase_options.dart';
import '../screens/auth/auth_gate.dart';
import '../Services/auth_service.dart';
import '../theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const BlueFieldApp());
}

class BlueFieldApp extends StatelessWidget {
  const BlueFieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueField',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
      // Overlays a persistent "Return to Owner View" banner above
      // WHATEVER screen/route is currently showing, for as long as a
      // demo "View As" session (lib/dev/view_as_screen.dart) is
      // active — builder wraps the entire Navigator, so this stays
      // visible even as the impersonated employee navigates deeper
      // into the app, not just on the first screen after switching.
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const _ViewAsBanner(),
          ],
        );
      },
    );
  }
}

class _ViewAsBanner extends StatelessWidget {
  const _ViewAsBanner();

  Future<void> _returnToOwner(BuildContext context) async {
    final creds = ViewAsSession.peekOwnerCredentials();
    if (creds == null) return;
    try {
      await AuthService().logout();
      await AuthService().login(email: creds.email, password: creds.password);
      ViewAsSession.clear();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not switch back: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ViewAsSession.activeNotifier,
      builder: (context, isActive, _) {
        if (!isActive) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.darkText,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_outlined, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Viewing as ${ViewAsSession.employeeLabel ?? 'employee'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _returnToOwner(context),
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('Return to Owner'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
