import 'package:flutter/material.dart';

import '../../Models/platform_admin_model.dart';
import '../../Services/admin_company_service.dart';
import '../../Services/support_ticket_service.dart';
import '../../theme/app_theme.dart';
import 'admin_audit_log_screen.dart';
import 'admin_company_list_screen.dart';
import 'admin_platform_admins_screen.dart';
import 'admin_feature_flags_screen.dart';
import 'admin_founding_commitments_screen.dart';
import 'admin_kill_switches_screen.dart';
import 'admin_system_announcements_screen.dart';
import 'admin_ticket_list_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final PlatformAdminModel admin;

  const AdminDashboardScreen({super.key, required this.admin});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final SupportTicketService _ticketService = SupportTicketService();
  final AdminCompanyService _companyService = AdminCompanyService();
  late Stream<TicketStats> _statsStream;
  late Stream<AdminCompanyStats> _companyStatsStream;

  @override
  void initState() {
    super.initState();
    _statsStream = _ticketService.watchTicketStats();
    _companyStatsStream = _companyService.watchCompanyStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/bluejay_logo.png', height: 34),
            const SizedBox(width: 10),
            const Text('Admin Panel', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          // The data is already live via streams — nothing to
          // actively re-fetch. Kept only as a brief, expected gesture
          // for anyone used to pull-to-refresh, not because it does
          // anything the stream isn't already doing continuously.
          onRefresh: () => Future.delayed(const Duration(milliseconds: 400)),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                elevation: 0,
                color: AppTheme.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Signed in as ${widget.admin.displayName}',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(widget.admin.role, style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              if (widget.admin.canManageOtherAdmins) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPlatformAdminsScreen()));
                    },
                    icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                    label: const Text('Manage Platform Admins'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminSystemAnnouncementsScreen()));
                    },
                    icon: const Icon(Icons.campaign_outlined, size: 18),
                    label: const Text('System Announcements'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminFeatureFlagsScreen()));
                    },
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Feature Flags'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminKillSwitchesScreen()));
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.power_settings_new_outlined, size: 18),
                    label: const Text('Kill Switches'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminFoundingCommitmentsScreen()));
                    },
                    icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                    label: const Text('Founding Commitments'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminAuditLogScreen()));
                  },
                  icon: const Icon(Icons.history_outlined, size: 18),
                  label: const Text('View Audit Log'),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Companies', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
              const SizedBox(height: 10),
              StreamBuilder<AdminCompanyStats>(
                stream: _companyStatsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: Text(snapshot.error?.toString() ?? 'Unable to load company stats.',
                          style: const TextStyle(color: AppTheme.mutedText)),
                    );
                  }

                  final cStats = snapshot.data!;

                  return GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.5,
                    children: [
                      _StatTile(label: 'Total Companies', value: cStats.totalCompanies, color: AppTheme.blue),
                      _StatTile(label: 'Active Companies', value: cStats.activeCompanies, color: Colors.green),
                      _StatTile(label: 'Suspended', value: cStats.suspendedCompanies, color: Colors.red),
                      _StatTile(label: 'New This Month', value: cStats.newThisMonth, color: Colors.purple),
                      _StatTile(label: 'Trialing', value: cStats.trialingCompanies, color: Colors.orange),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              StreamBuilder<AdminCompanyStats>(
                stream: _companyStatsStream,
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  if (stats == null) return const SizedBox.shrink();

                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Founding Program', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                          const SizedBox(height: 8),
                          Text(
                            stats.foundingSlotTaken
                                ? '✓ Founding Customer (#1) slot taken'
                                : '1 Founding Customer (#1) slot open',
                            style: const TextStyle(fontSize: 13, color: AppTheme.mutedText),
                          ),
                          Text('${stats.betaSlotsRemaining} of 4 Beta Company slots remaining',
                              style: const TextStyle(fontSize: 13, color: AppTheme.mutedText)),
                          Text('${stats.earlyAdopterSlotsRemaining} of 4 Early Adopter slots remaining',
                              style: const TextStyle(fontSize: 13, color: AppTheme.mutedText)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminCompanyListScreen()));
                  },
                  icon: const Icon(Icons.business_outlined),
                  label: const Text('View All Companies'),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Support Tickets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
              const SizedBox(height: 10),
              StreamBuilder<TicketStats>(
                stream: _statsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: Text(snapshot.error?.toString() ?? 'Unable to load stats.',
                          style: const TextStyle(color: AppTheme.mutedText)),
                    );
                  }

                  final stats = snapshot.data!;

                  return GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.5,
                    children: [
                      _StatTile(label: 'Total Tickets', value: stats.total, color: AppTheme.blue),
                      _StatTile(label: 'Open Tickets', value: stats.open, color: Colors.orange),
                      _StatTile(label: 'Closed Tickets', value: stats.closed, color: Colors.green),
                      _StatTile(label: 'Critical Tickets', value: stats.critical, color: Colors.red),
                      _StatTile(label: 'New Today', value: stats.newToday, color: Colors.purple),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminTicketListScreen()));
                  },
                  icon: const Icon(Icons.confirmation_number_outlined),
                  label: const Text('View All Tickets'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$value', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.mutedText)),
          ],
        ),
      ),
    );
  }
}
