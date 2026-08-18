import 'package:flutter/material.dart';
import '../Firebase/firestore_schema.dart';
import '../Models/company_settings_model.dart';
import '../Models/correction_request_model.dart';
import '../Models/crew_model.dart';
import '../Models/equipment_model.dart';
import '../Models/job_model.dart';
import '../Models/time_entry_model.dart';
import '../Models/time_off_request_model.dart';
import '../Models/vehicle_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/equipment_service.dart';
import '../Services/job_service.dart';
import '../Services/permission_service.dart';
import '../Services/time_entry_service.dart';
import '../Services/time_off_service.dart';
import '../Services/vehicle_service.dart';
import '../theme/app_theme.dart';
import 'announcements_screen.dart';
import 'app_nav_drawer.dart';
import 'system_announcement_banner.dart';
import 'crews_screen.dart';
import 'employees_screen.dart';
import 'employer_messages_screen.dart';
import 'equipment_screen.dart';
import 'jobs_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'team_time_screen.dart';
import 'time_off_requests_screen.dart';
import 'Vehicles_screen.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final AuthService _authService = AuthService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  late Future<AuthUserProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _authService.getCurrentUserProfile();
  }

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildDashboardTab(context),
      const JobsScreen(showAllJobs: true),
      const EmployerMessagesScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: FutureBuilder<AuthUserProfile>(
        future: _profileFuture,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) return const Drawer(child: SizedBox.shrink());
          // Company settings determine whether this company calls
          // crews "Crews" or "Teams" — without this, the drawer always
          // said "Crews" even when the dashboard cards next to it
          // correctly said "Teams" for a company that renamed it.
          return StreamBuilder<CompanySettingsModel>(
            stream: _settingsService.watchCompanySettings(profile.activeCompanyId),
            builder: (context, settingsSnapshot) {
              final crewLabel =
                  settingsSnapshot.data?.crewTerminology == 'team' ? 'Team' : 'Crew';
              return AppNavDrawer(
                role: profile.role,
                companyId: profile.activeCompanyId,
                crewLabel: crewLabel,
              );
            },
          );
        },
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Manager Dashboard',
          style: TextStyle(
            color: AppTheme.darkText,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SystemAnnouncementBanner(),
            Expanded(child: IndexedStack(index: _selectedIndex, children: tabs)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width >= 700;

    return Padding(
          padding: const EdgeInsets.all(18),
          child: FutureBuilder<AuthUserProfile>(
            future: _profileFuture,
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (profileSnapshot.hasError || !profileSnapshot.hasData) {
                return Center(
                  child: Text(
                    profileSnapshot.error?.toString() ?? 'Unable to load your company.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                );
              }

              final profile = profileSnapshot.data!;
              final companyId = profile.activeCompanyId;

              // Not every card a manager sees is decided by company
              // settings alone — payroll visibility specifically
              // depends on the manager's own permission grant (Section
              // 16: "Do not expose payroll unless permitted").
              final canViewPayroll = PermissionService.roleHasPermission(
                profile.role,
                Permission.timeViewPayrollTotals,
              );

              return StreamBuilder<CompanySettingsModel>(
                stream: _settingsService.watchCompanySettings(companyId),
                builder: (context, settingsSnapshot) {
                  if (settingsSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final settings = settingsSnapshot.data ??
                      CompanySettingsModel.defaults(companyId: companyId);

                  final timeOffEnabled = _settingsService.isFeatureEnabled(settings, 'timeOff');
                  final teamTimeEnabled = _settingsService.isFeatureEnabled(settings, 'teamTime');

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Manager tools',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Manage field operations, employees, crews, team time, and schedules.',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppTheme.mutedText,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: isWideScreen ? 2 : 1,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: isWideScreen ? 1.35 : 1.45,
                          children: [
                            if (_settingsService.isFeatureEnabled(settings, 'jobs'))
                              _LiveJobsCard(companyId: companyId, userId: profile.uid),
                            _LiveEmployeesCard(companyId: companyId),
                            if (_settingsService.isFeatureEnabled(settings, 'teamTime'))
                              _LiveClockedInCard(companyId: companyId),
                            if (_settingsService.isFeatureEnabled(settings, 'crews'))
                              _LiveCrewsCard(companyId: companyId, crewLabel: settings.crewTerminology == 'team' ? 'Team' : 'Crew'),
                            if (_settingsService.isFeatureEnabled(settings, 'vehicles'))
                              _LiveVehiclesCard(companyId: companyId),
                            _LiveEquipmentCard(companyId: companyId),
                            if (timeOffEnabled || teamTimeEnabled)
                              _LivePendingApprovalsCard(
                                companyId: companyId,
                                timeOffEnabled: timeOffEnabled,
                                teamTimeEnabled: teamTimeEnabled,
                              ),
                            if (_settingsService.isFeatureEnabled(settings, 'messaging'))
                              ManagerStatCard(
                                icon: Icons.message_outlined,
                                title: 'Messages',
                                mainValue: 'Open Chat',
                                details: const [
                                  'Crew messages',
                                  'Direct messages',
                                  'Company threads',
                                ],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const EmployerMessagesScreen(),
                                    ),
                                  );
                                },
                              ),
                            if (canViewPayroll &&
                                _settingsService.isFeatureEnabled(settings, 'payroll'))
                              ManagerStatCard(
                                icon: Icons.payments_outlined,
                                title: 'Payroll',
                                mainValue: 'View Totals',
                                details: const ['Tap to view team time totals'],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const TeamTimeScreen(),
                                    ),
                                  );
                                },
                              ),
                            if (_settingsService.isFeatureEnabled(settings, 'announcements'))
                              ManagerStatCard(
                                icon: Icons.campaign_outlined,
                                title: 'Announcements',
                                mainValue: 'Company Updates',
                                details: const ['View and post announcements'],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const AnnouncementsScreen(),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
  }
}

class _LiveClockedInCard extends StatelessWidget {
  final String companyId;

  const _LiveClockedInCard({required this.companyId});

  @override
  Widget build(BuildContext context) {
    final timeEntryService = TimeEntryService();

    return StreamBuilder<List<TimeEntryModel>>(
      stream: timeEntryService.watchActiveCompanyClockEntries(companyId),
      builder: (context, snapshot) {
        final activeCount = snapshot.data?.length ?? 0;

        return ManagerStatCard(
          icon: Icons.access_time_outlined,
          title: 'Team Time',
          mainValue: '$activeCount Clocked In',
          details: const [
            'Live clock status',
            'Correction requests',
          ],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TeamTimeScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

/// Live version of the Employees stat card — was a one-time Future
/// fetch, meaning a newly hired or archived employee's count only
/// updated after a full page reload.
class _LiveEmployeesCard extends StatelessWidget {
  final String companyId;

  const _LiveEmployeesCard({required this.companyId});

  @override
  Widget build(BuildContext context) {
    final employeeService = EmployeeService();

    // Archived employees are former staff (fired/quit/laid off) — they
    // shouldn't count toward the headcount shown here. Fetching with
    // includeArchived: false excludes them at the source rather than
    // computing and displaying a separate archived count on the card;
    // archived employees are still reachable via the "View Archived"
    // button on the Employees screen itself.
    return StreamBuilder<List<EmployeeWithMembership>>(
      stream: employeeService.watchEmployeesByCompany(companyId: companyId, includeArchived: false),
      builder: (context, snapshot) {
        final total = (snapshot.data ?? []).length;

        return ManagerStatCard(
          icon: Icons.groups_outlined,
          title: 'Employees',
          mainValue: '$total Total',
          details: const ['Tap to view team'],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const EmployeesScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

/// Live version of the Pending Approvals card — combines two live
/// streams (pending time-off requests, pending time-correction
/// requests) instead of the old one-time DashboardStats fetch, so a
/// newly submitted or resolved request updates the count immediately.
class _LivePendingApprovalsCard extends StatelessWidget {
  final String companyId;
  final bool timeOffEnabled;
  final bool teamTimeEnabled;

  const _LivePendingApprovalsCard({
    required this.companyId,
    required this.timeOffEnabled,
    required this.teamTimeEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final timeOffService = TimeOffService();
    final timeEntryService = TimeEntryService();

    final timeOffStream = timeOffEnabled
        ? timeOffService.watchPendingRequests(companyId: companyId)
        : Stream<List<TimeOffRequestModel>>.value(const []);
    final correctionsStream = teamTimeEnabled
        ? timeEntryService.watchPendingCorrectionRequests(companyId)
        : Stream<List<CorrectionRequestModel>>.value(const []);

    return StreamBuilder<List<TimeOffRequestModel>>(
      stream: timeOffStream,
      builder: (context, timeOffSnapshot) {
        final pendingTimeOff = timeOffSnapshot.data?.length ?? 0;

        return StreamBuilder<List<CorrectionRequestModel>>(
          stream: correctionsStream,
          builder: (context, correctionsSnapshot) {
            final pendingCorrections = correctionsSnapshot.data?.length ?? 0;

            return ManagerStatCard(
              icon: Icons.pending_actions_outlined,
              title: 'Pending Approvals',
              mainValue: '${pendingTimeOff + pendingCorrections} Pending',
              details: [
                if (timeOffEnabled) '$pendingTimeOff Time Off',
                if (teamTimeEnabled) '$pendingCorrections Time Corrections',
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TimeOffRequestsScreen(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Live version of the Jobs stat card — was a one-time Future fetch,
/// meaning a newly created job's count only updated after a full page
/// reload. Streams all company jobs and recomputes today's counts on
/// every update instead.
/// Live version of the Crews/Teams stat card — was a one-time Future
/// fetch, meaning a newly created crew's count only updated after a
/// full page reload.
class _LiveCrewsCard extends StatelessWidget {
  final String companyId;
  final String crewLabel;

  const _LiveCrewsCard({required this.companyId, required this.crewLabel});

  @override
  Widget build(BuildContext context) {
    final crewService = CrewService();

    return StreamBuilder<List<CrewModel>>(
      stream: crewService.watchCrewsByCompany(companyId: companyId),
      builder: (context, snapshot) {
        final total = snapshot.data?.length ?? 0;

        return ManagerStatCard(
          icon: Icons.group_work_outlined,
          title: '${crewLabel}s',
          mainValue: '$total Total',
          details: const ['Create crews', 'Assign employees', 'Manage field teams'],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CrewsScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

class _LiveVehiclesCard extends StatelessWidget {
  final String companyId;

  const _LiveVehiclesCard({required this.companyId});

  @override
  Widget build(BuildContext context) {
    final vehicleService = VehicleService();

    return StreamBuilder<List<VehicleModel>>(
      stream: vehicleService.watchVehiclesByCompany(companyId: companyId),
      builder: (context, snapshot) {
        final total = snapshot.data?.length ?? 0;

        return ManagerStatCard(
          icon: Icons.local_shipping_outlined,
          title: 'Vehicles',
          mainValue: '$total Total',
          details: const ['Tap to view all'],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const VehiclesScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

class _LiveEquipmentCard extends StatelessWidget {
  final String companyId;

  const _LiveEquipmentCard({required this.companyId});

  @override
  Widget build(BuildContext context) {
    final equipmentService = EquipmentService();

    return StreamBuilder<List<EquipmentModel>>(
      stream: equipmentService.watchEquipmentByCompany(companyId: companyId),
      builder: (context, snapshot) {
        final total = snapshot.data?.length ?? 0;

        return ManagerStatCard(
          icon: Icons.construction_outlined,
          title: 'Equipment',
          mainValue: '$total Total',
          details: const ['Tap to view all'],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const EquipmentScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

class _LiveJobsCard extends StatelessWidget {
  final String companyId;
  final String userId;

  const _LiveJobsCard({required this.companyId, required this.userId});

  @override
  Widget build(BuildContext context) {
    final jobService = JobService();
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);

    return StreamBuilder<List<JobModel>>(
      stream: jobService.watchVisibleJobs(companyId: companyId, requestingUserId: userId),
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? [];

        final todaysJobs = jobs.where((j) {
          final isActive = j.status == FSJobStatus.scheduled || j.status == FSJobStatus.inProgress;
          return isActive && !j.startDate.isAfter(todayEnd) && !j.endDate.isBefore(todayStart);
        }).length;
        final unassignedJobs = jobs
            .where((j) =>
                (j.status == FSJobStatus.scheduled || j.status == FSJobStatus.inProgress) &&
                j.assignedEmployeeIds.isEmpty &&
                j.assignedCrewIds.isEmpty)
            .length;
        final completedJobs = jobs.where((j) => j.status == FSJobStatus.completed).length;
        final cancelledJobs = jobs.where((j) => j.status == FSJobStatus.cancelled).length;

        return ManagerStatCard(
          icon: Icons.local_shipping_outlined,
          title: 'Jobs',
          mainValue: '$todaysJobs Today',
          details: [
            '$unassignedJobs Unassigned',
            '$completedJobs Completed',
            '$cancelledJobs Cancelled',
          ],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const JobsScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

class ManagerStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String mainValue;
  final List<String> details;
  final VoidCallback onTap;

  const ManagerStatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.mainValue,
    required this.details,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppTheme.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkText,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppTheme.mutedText,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  mainValue,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkText,
                  ),
                ),
                const SizedBox(height: 10),
                ...details.map(
                  (detail) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '• $detail',
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
