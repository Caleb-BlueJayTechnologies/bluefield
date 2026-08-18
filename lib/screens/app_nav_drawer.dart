import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/company_settings_model.dart';
import '../Services/company_settings_service.dart';
import '../Services/platform_admin_service.dart';
import '../theme/app_theme.dart';
import 'Vehicles_screen.dart';
import 'admin/admin_gate_screen.dart';
import 'announcements_screen.dart';
import 'crews_screen.dart';
import 'employee_notifications_screen.dart';
import 'employees_screen.dart';
import 'equipment_screen.dart';
import 'job_history_screen.dart';
import 'jobs_screen.dart';
import 'my_tickets_screen.dart';
import 'my_time_history_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'team_time_screen.dart';
import 'time_off_requests_screen.dart';
import 'employee_time_off_request_screen.dart';

/// Shared side navigation drawer — the "task bar pop out" requested in
/// feedback. Consolidates everything a role can reach into one place,
/// since a lot of screens were previously only reachable via a
/// specific dashboard stat card and nowhere else. Content adapts by
/// role rather than being one fixed list for everyone.
class AppNavDrawer extends StatefulWidget {
  final String role;
  final String companyId;
  final String crewLabel;

  const AppNavDrawer({
    super.key,
    required this.role,
    required this.companyId,
    this.crewLabel = 'Crew',
  });

  @override
  State<AppNavDrawer> createState() => _AppNavDrawerState();
}

class _AppNavDrawerState extends State<AppNavDrawer> {
  bool _isPlatformAdmin = false;
  final CompanySettingsService _settingsService = CompanySettingsService();

  @override
  void initState() {
    super.initState();
    // Admin access is a separate platform-level grant, not just "is
    // this person a company owner" — same check used to decide
    // whether the Admin tab shows on the dashboard, so the drawer
    // stays consistent with that.
    PlatformAdminService().getCurrentAdmin().then((admin) {
      if (mounted && admin != null) {
        setState(() => _isPlatformAdmin = true);
      }
    });
  }

  bool get _isEmployee => widget.role == FSRoles.employee;
  bool get _canManage => widget.role == FSRoles.owner || widget.role == FSRoles.manager;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        // Was a fixed list that never looked at company settings at
        // all, so disabling a module in Company Settings had zero
        // effect here — every tile stayed visible regardless. This
        // subscribes live to company settings so a toggle flip is
        // reflected immediately, no app restart needed, matching the
        // same live-settings pattern already used by the dashboards.
        child: StreamBuilder<CompanySettingsModel>(
          stream: _settingsService.watchCompanySettings(widget.companyId),
          builder: (context, settingsSnapshot) {
            final settings = settingsSnapshot.data ??
                CompanySettingsModel.defaults(companyId: widget.companyId);

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  color: AppTheme.blue,
                  child: const Row(
                    children: [
                      Icon(Icons.apps, color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Text('Menu', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (_settingsService.isFeatureEnabled(settings, 'jobs'))
                  _tile(context, Icons.work_outline, 'Jobs & Schedule', () => const JobsScreen()),
                if (_settingsService.isFeatureEnabled(settings, 'announcements'))
                  _tile(context, Icons.campaign_outlined, 'Announcements', () => const AnnouncementsScreen()),
                if (_isEmployee) ...[
                  if (_settingsService.isFeatureEnabled(settings, 'timeOff'))
                    _tile(context, Icons.event_busy_outlined, 'Request Time Off', () => const EmployeeTimeOffRequestScreen()),
                  if (_settingsService.isFeatureEnabled(settings, 'teamTime'))
                    _tile(context, Icons.history_outlined, 'My Time History', () => const MyTimeHistoryScreen()),
                  _tile(context, Icons.notifications_outlined, 'Notifications', () => const EmployeeNotificationsScreen()),
                  if (_settingsService.isFeatureEnabled(settings, 'jobs'))
                    _tile(context, Icons.checklist_outlined, 'Job History', () => const JobHistoryScreen()),
                ],
                if (_canManage) ...[
                  _tile(context, Icons.people_outline, 'Employees', () => const EmployeesScreen()),
                  if (_settingsService.isFeatureEnabled(settings, 'crews'))
                    _tile(context, Icons.group_work_outlined, '${widget.crewLabel}s', () => const CrewsScreen()),
                  if (_settingsService.isFeatureEnabled(settings, 'vehicles'))
                    _tile(context, Icons.local_shipping_outlined, 'Vehicles', () => const VehiclesScreen()),
                  _tile(context, Icons.construction_outlined, 'Equipment', () => const EquipmentScreen()),
                  if (_settingsService.isFeatureEnabled(settings, 'teamTime'))
                    _tile(context, Icons.access_time_outlined, 'Team Time', () => const TeamTimeScreen()),
                  if (_settingsService.isFeatureEnabled(settings, 'timeOff'))
                    _tile(context, Icons.event_busy_outlined, 'Time Off Requests', () => const TimeOffRequestsScreen()),
                ],
                const Divider(height: 24),
                _tile(context, Icons.person_outline, 'Profile', () => const ProfileScreen()),
                if (_settingsService.isFeatureEnabled(settings, 'feedback'))
                  _tile(context, Icons.support_agent_outlined, 'Support & Feedback', () => const MyTicketsScreen()),
                if (_canManage) _tile(context, Icons.settings_outlined, 'Company Settings', () => const SettingsScreen()),
                if (_isPlatformAdmin) ...[
                  const Divider(height: 24),
                  _tile(context, Icons.admin_panel_settings_outlined, 'Admin Panel', () => const AdminGateScreen()),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, Widget Function() screenBuilder) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.blue),
      title: Text(label, style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.w600)),
      onTap: () {
        Navigator.pop(context); // close the drawer first
        Navigator.push(context, MaterialPageRoute(builder: (context) => screenBuilder()));
      },
    );
  }
}
