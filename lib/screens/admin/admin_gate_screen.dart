import 'package:flutter/material.dart';

import '../../Models/platform_admin_model.dart';
import '../../Services/platform_admin_service.dart';
import '../../theme/app_theme.dart';
import 'environment_indicator.dart';
import 'admin_dashboard_screen.dart';

/// The entry point into the BlueJay Admin Panel. Linked from the nav
/// drawer, but only shown there to users AppNavDrawer independently
/// confirms are platform admins — and even then, that's just a UI
/// convenience. The real enforcement is entirely below: a live check
/// against platformAdmins/{uid} via PlatformAdminService.watchCurrentAdmin().
/// Being an Owner of any number of companies grants nothing here.
class AdminGateScreen extends StatelessWidget {
  const AdminGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const EnvironmentIndicator(),
            Expanded(
              child: StreamBuilder<PlatformAdminModel?>(
                stream: PlatformAdminService().watchCurrentAdmin(),
                builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final admin = snapshot.data;

            if (admin == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 48, color: AppTheme.mutedText),
                      const SizedBox(height: 16),
                      const Text(
                        'You do not have access to the BlueJay Admin Panel.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: AppTheme.mutedText),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Company ownership does not grant platform-admin access. Contact a super admin if you believe this is a mistake.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppTheme.mutedText),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return AdminDashboardScreen(admin: admin);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
