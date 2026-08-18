import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/company_settings_model.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/job_model.dart';
import '../Models/membership.dart';
import '../Models/time_entry_model.dart';
import '../Services/company_settings_service.dart';
import '../Services/permission_service.dart';
import '../Services/time_entry_service.dart';
import '../theme/app_theme.dart';
import 'clock_in_screen.dart';
import 'correction_requests_screen.dart';
import 'my_time_history_screen.dart';
import 'pay_periods_screen.dart';
import 'time_entry_detail_screen.dart';
import 'team_time_history_screen.dart';

class TeamTimeScreen extends StatefulWidget {
  const TeamTimeScreen({super.key});

  @override
  State<TeamTimeScreen> createState() => _TeamTimeScreenState();
}

class _TeamTimeScreenState extends State<TeamTimeScreen> {
  final TimeEntryService _timeEntryService = TimeEntryService();
  final PermissionService _permissionService = PermissionService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  late Future<String> _companyFuture;
  late Future<String> _roleFuture;

  // Employees/memberships change rarely relative to time entries, so
  // these are loaded once per company rather than re-fetched on every
  // clock-in/out event.
  late Future<_ReferenceData> _referenceDataFuture;

  // Ticks the UI every 30s so each clocked-in employee's running time
  // counts up live instead of freezing at whatever value it had when
  // this screen was last rebuilt.
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _companyFuture = _timeEntryService.getCurrentCompanyId();
    _roleFuture = _permissionService.getCurrentUserRole();
    _referenceDataFuture = _companyFuture.then(_loadReferenceData);
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<_ReferenceData> _loadReferenceData(String companyId) async {
    final firestore = FirebaseFirestore.instance;

    final employeesSnap = await firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.employees)
        .get();
    final membershipsSnap = await firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships)
        .get();

    return _ReferenceData(
      employeesById: {
        for (final d in employeesSnap.docs) d.id: EmployeeModel.fromSnapshot(d),
      },
      membershipsById: {
        for (final d in membershipsSnap.docs) d.id: MembershipModel.fromSnapshot(d),
      },
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _todayEntriesStream(String companyId) {
    return FirebaseFirestore.instance
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeEntries)
        .snapshots();
  }

  bool _isToday(DateTime clockIn) {
    final now = DateTime.now();
    return clockIn.year == now.year && clockIn.month == now.month && clockIn.day == now.day;
  }

  Future<Map<String, JobModel>> _resolveJobs(String companyId, List<TimeEntryModel> entries) async {
    final jobIds = entries.map((e) => e.jobId).whereType<String>().toSet().toList();
    final jobsById = <String, JobModel>{};
    for (var i = 0; i < jobIds.length; i += 30) {
      final chunk = jobIds.sublist(i, i + 30 > jobIds.length ? jobIds.length : i + 30);
      if (chunk.isEmpty) continue;
      final snap = await FirebaseFirestore.instance
          .collection(FSCollections.companies)
          .doc(companyId)
          .collection(FSCompanySub.jobs)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        jobsById[d.id] = JobModel.fromSnapshot(d);
      }
    }
    return jobsById;
  }

  Future<Map<String, CrewModel>> _resolveCrews(String companyId, List<TimeEntryModel> entries) async {
    final crewIds = entries.map((e) => e.crewId).whereType<String>().toSet().toList();
    final crewsById = <String, CrewModel>{};
    for (var i = 0; i < crewIds.length; i += 30) {
      final chunk = crewIds.sublist(i, i + 30 > crewIds.length ? crewIds.length : i + 30);
      if (chunk.isEmpty) continue;
      final snap = await FirebaseFirestore.instance
          .collection(FSCollections.companies)
          .doc(companyId)
          .collection(FSCompanySub.crews)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        crewsById[d.id] = CrewModel.fromSnapshot(d);
      }
    }
    return crewsById;
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }

  void _openEntryDetails({
    required String companyId,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required bool canEdit,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TimeEntryDetailScreen(
          companyId: companyId,
          timeEntryId: doc.id,
          entryData: doc.data(),
          canEdit: canEdit,
        ),
      ),
    );
  }

  bool _isOwner(String role) => role.toLowerCase().trim() == 'owner';
  bool _canManagePayPeriods(String role) => _isOwner(role);

  Widget _buildDisabledState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 44, color: AppTheme.blue),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.darkText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Team Time', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _companyFuture,
          builder: (context, companySnapshot) {
            if (companySnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (companySnapshot.hasError) {
              return Center(
                child: Text(companySnapshot.error.toString(),
                    textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.mutedText)),
              );
            }

            final companyId = companySnapshot.data;
            if (companyId == null || companyId.isEmpty) {
              return const Center(child: Text('No company found.', style: TextStyle(color: AppTheme.mutedText)));
            }

            return StreamBuilder<CompanySettingsModel>(
              stream: _settingsService.watchCompanySettings(companyId),
              builder: (context, settingsSnapshot) {
                if (settingsSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (settingsSnapshot.hasError || settingsSnapshot.data == null) {
                  return Center(
                    child: Text(
                      settingsSnapshot.error?.toString() ?? 'Unable to load company settings.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  );
                }

                final settings = settingsSnapshot.data!;
                if (!_settingsService.isTeamTimeEnabled(settings)) {
                  return _buildDisabledState(_settingsService.disabledMessageForFeature('teamTime'));
                }

                final clockInOutEnabled = _settingsService.isClockInOutEnabled(settings);
                final correctionRequestsEnabled = _settingsService.areCorrectionRequestsEnabled(settings);
                final managerEditsEnabled = _settingsService.areManagerTimeEditsEnabled(settings);
                final payPeriodsEnabled = _settingsService.arePayPeriodsEnabled(settings);

                return FutureBuilder<String>(
                  future: _roleFuture,
                  builder: (context, roleSnapshot) {
                    if (roleSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (roleSnapshot.hasError || roleSnapshot.data == null || roleSnapshot.data!.isEmpty) {
                      return Center(
                        child: Text(
                          roleSnapshot.error?.toString() ?? 'Unable to determine permissions.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      );
                    }

                    final viewerRole = roleSnapshot.data!;
                    final viewerUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
                    final isOwner = _isOwner(viewerRole);
                    final canManagePayPeriods = _canManagePayPeriods(viewerRole) && payPeriodsEnabled;

                    return FutureBuilder<_ReferenceData>(
                      future: _referenceDataFuture,
                      builder: (context, refSnapshot) {
                        if (refSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final reference = refSnapshot.data ?? const _ReferenceData(employeesById: {}, membershipsById: {});

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _todayEntriesStream(companyId),
                          builder: (context, allEntriesSnapshot) {
                            if (allEntriesSnapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (allEntriesSnapshot.hasError) {
                              return Center(
                                child: Text(allEntriesSnapshot.error.toString(),
                                    textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.mutedText)),
                              );
                            }

                            final allDocs = allEntriesSnapshot.data?.docs ?? [];
                            final allEntries = allDocs.map((d) => TimeEntryModel.fromSnapshot(d)).toList();

                            final todayEntries = <MapEntry<QueryDocumentSnapshot<Map<String, dynamic>>, TimeEntryModel>>[];
                            for (var i = 0; i < allDocs.length; i++) {
                              if (_isToday(allEntries[i].clockInAt)) {
                                todayEntries.add(MapEntry(allDocs[i], allEntries[i]));
                              }
                            }
                            todayEntries.sort((a, b) => b.value.clockInAt.compareTo(a.value.clockInAt));

                            final activeEntries = todayEntries.where((e) => e.value.isActive).toList();

                            // Breaks no longer clock anyone out (see
                            // TimeEntryService.startBreak/endBreak) — "on
                            // break" is just the subset of today's active
                            // entries with an unended BreakEntry, not a
                            // separate "most recent entry ended with
                            // isBreak true" heuristic over past entries.
                            final onBreakEntries = activeEntries.where((e) => e.value.isOnBreak).map((e) => e.value).toList();

                            int employeesClockedIn = 0;
                            int managersClockedIn = 0;
                            for (final e in activeEntries) {
                              final role = reference.membershipsById[e.value.employeeId]?.role ?? 'employee';
                              if (role == 'manager') {
                                managersClockedIn++;
                              } else {
                                employeesClockedIn++;
                              }
                            }

                            final todayTotalMinutes = todayEntries
                                .map((e) => e.value.rawDuration?.inMinutes ?? 0)
                                .fold<int>(0, (sum, m) => sum + m);

                            return FutureBuilder<List<Map<String, dynamic>>>(
                              future: Future.wait([
                                _resolveJobs(companyId, todayEntries.map((e) => e.value).toList()),
                                _resolveCrews(companyId, todayEntries.map((e) => e.value).toList()),
                              ]).then((results) => [
                                    {'jobs': results[0]},
                                    {'crews': results[1]},
                                  ]),
                              builder: (context, resolveSnapshot) {
                                final jobsById = (resolveSnapshot.data?[0]['jobs'] as Map<String, JobModel>?) ?? {};
                                final crewsById = (resolveSnapshot.data?[1]['crews'] as Map<String, CrewModel>?) ?? {};

                                bool canEditEntry(TimeEntryModel entry) {
                                  final permissionAllowsEdit = _permissionService.canEditTimeEntry(
                                    viewerRole: viewerRole,
                                    viewerUserId: viewerUserId,
                                    entryUserId: entry.employeeId,
                                  );
                                  return permissionAllowsEdit && (isOwner || managerEditsEnabled);
                                }

                                String nameFor(String employeeId) {
                                  final employee = reference.employeesById[employeeId];
                                  return employee?.fullName.trim().isNotEmpty == true
                                      ? employee!.fullName
                                      : 'Unknown Worker';
                                }

                                String roleFor(String employeeId) {
                                  return reference.membershipsById[employeeId]?.role ?? 'employee';
                                }

                                return ListView(
                                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                                  children: [
                                    _TeamTimeSummaryCard(
                                      totalClockedIn: activeEntries.length,
                                      employeesClockedIn: employeesClockedIn,
                                      managersClockedIn: managersClockedIn,
                                      onBreakCount: onBreakEntries.length,
                                      onBreakNames: onBreakEntries.map((e) => nameFor(e.employeeId)).toList(),
                                      todayEntries: todayEntries.length,
                                      todayTotalHours: _formatMinutes(todayTotalMinutes),
                                    ),
                                    const SizedBox(height: 18),
                                    _ShortcutGrid(
                                      showMyClock: clockInOutEnabled,
                                      showCorrections: correctionRequestsEnabled,
                                      canManagePayPeriods: canManagePayPeriods,
                                      onOpenMyClock: () {
                                        if (!clockInOutEnabled) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(_settingsService.disabledMessageForFeature('clockInOut'))),
                                          );
                                          return;
                                        }
                                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ClockInScreen()));
                                      },
                                      onOpenMyHistory: () {
                                        Navigator.push(
                                            context, MaterialPageRoute(builder: (context) => const MyTimeHistoryScreen()));
                                      },
                                      onOpenTeamHistory: () {
                                        Navigator.push(context,
                                            MaterialPageRoute(builder: (context) => const TeamTimeHistoryScreen()));
                                      },
                                      onOpenCorrections: () {
                                        if (!correctionRequestsEnabled) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    _settingsService.disabledMessageForFeature('correctionRequests'))),
                                          );
                                          return;
                                        }
                                        Navigator.push(context,
                                            MaterialPageRoute(builder: (context) => const CorrectionRequestsScreen()));
                                      },
                                      onOpenPayPeriods: () {
                                        if (!canManagePayPeriods) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(_settingsService.disabledMessageForFeature('payPeriods'))),
                                          );
                                          return;
                                        }
                                        Navigator.push(
                                            context, MaterialPageRoute(builder: (context) => const PayPeriodsScreen()));
                                      },
                                    ),
                                    const SizedBox(height: 22),
                                    const Text('Active Right Now',
                                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                                    const SizedBox(height: 12),
                                    if (activeEntries.isEmpty)
                                      const _EmptyTeamTimeCard()
                                    else
                                      ...activeEntries.map((e) {
                                        final entry = e.value;
                                        final canEdit = canEditEntry(entry);
                                        final job = entry.jobId != null ? jobsById[entry.jobId] : null;
                                        final crew = entry.crewId != null ? crewsById[entry.crewId] : null;

                                        return _ActiveTimeEntryCard(
                                          employeeName: nameFor(entry.employeeId),
                                          role: roleFor(entry.employeeId),
                                          clockInTime: _timeEntryService.formatTime(entry.clockInAt),
                                          runningTime: _timeEntryService
                                              .formatDuration(DateTime.now().difference(entry.clockInAt)),
                                          jobName: job?.title ?? 'No job selected',
                                          crewName: crew?.crewName ?? 'No crew selected',
                                          canEdit: canEdit,
                                          onBreak: entry.isOnBreak,
                                          onBreakIsPaid: entry.activeBreak?.isPaid,
                                          onTap: () => _openEntryDetails(companyId: companyId, doc: e.key, canEdit: canEdit),
                                        );
                                      }),
                                    const SizedBox(height: 22),
                                    const Text("Today's Entries",
                                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                                    const SizedBox(height: 12),
                                    if (todayEntries.isEmpty)
                                      const _EmptyTodayEntriesCard()
                                    else
                                      ...todayEntries.map((e) {
                                        final entry = e.value;
                                        final canEdit = canEditEntry(entry);

                                        return _TodayEntryCard(
                                          employeeName: nameFor(entry.employeeId),
                                          status: entry.isActive ? 'Clocked in' : 'Clocked out',
                                          clockIn: _timeEntryService.formatTime(entry.clockInAt),
                                          clockOut: _timeEntryService.formatTime(entry.clockOutAt),
                                          total: _formatMinutes(entry.rawDuration?.inMinutes ?? 0),
                                          canEdit: canEdit,
                                          onTap: () => _openEntryDetails(companyId: companyId, doc: e.key, canEdit: canEdit),
                                        );
                                      }),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReferenceData {
  final Map<String, EmployeeModel> employeesById;
  final Map<String, MembershipModel> membershipsById;

  const _ReferenceData({required this.employeesById, required this.membershipsById});
}

class _TeamTimeSummaryCard extends StatelessWidget {
  final int totalClockedIn;
  final int employeesClockedIn;
  final int managersClockedIn;
  final int onBreakCount;
  final List<String> onBreakNames;
  final int todayEntries;
  final String todayTotalHours;

  const _TeamTimeSummaryCard({
    required this.totalClockedIn,
    required this.employeesClockedIn,
    required this.managersClockedIn,
    this.onBreakCount = 0,
    this.onBreakNames = const [],
    required this.todayEntries,
    required this.todayTotalHours,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.access_time_outlined, color: AppTheme.blue),
                SizedBox(width: 8),
                Text('Currently Active',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
              ],
            ),
            const SizedBox(height: 16),
            Text('$totalClockedIn Total Clocked In',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            const SizedBox(height: 10),
            Text('$employeesClockedIn Employees', style: const TextStyle(fontSize: 14, color: AppTheme.mutedText)),
            const SizedBox(height: 4),
            Text('$managersClockedIn Managers', style: const TextStyle(fontSize: 14, color: AppTheme.mutedText)),
            if (onBreakCount > 0) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.free_breakfast_outlined, size: 18, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text('$onBreakCount On Break',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
              const SizedBox(height: 4),
              Text(onBreakNames.join(', '), style: const TextStyle(fontSize: 13, color: AppTheme.mutedText)),
            ],
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            Text("$todayEntries Today's Entries", style: const TextStyle(fontSize: 14, color: AppTheme.mutedText)),
            const SizedBox(height: 4),
            Text('$todayTotalHours Total Completed Time Today',
                style: const TextStyle(fontSize: 14, color: AppTheme.mutedText)),
          ],
        ),
      ),
    );
  }
}

class _ShortcutGrid extends StatelessWidget {
  final bool showMyClock;
  final bool showCorrections;
  final bool canManagePayPeriods;
  final VoidCallback onOpenMyClock;
  final VoidCallback onOpenMyHistory;
  final VoidCallback onOpenTeamHistory;
  final VoidCallback onOpenCorrections;
  final VoidCallback onOpenPayPeriods;

  const _ShortcutGrid({
    required this.showMyClock,
    required this.showCorrections,
    required this.canManagePayPeriods,
    required this.onOpenMyClock,
    required this.onOpenMyHistory,
    required this.onOpenTeamHistory,
    required this.onOpenCorrections,
    required this.onOpenPayPeriods,
  });

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width >= 700;

    return GridView.count(
      crossAxisCount: isWideScreen ? 2 : 1,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: isWideScreen ? 2.0 : 2.3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (showMyClock)
          _ShortcutCard(icon: Icons.access_time, title: 'My Clock', subtitle: 'Clock yourself in or out.', onTap: onOpenMyClock),
        _ShortcutCard(
            icon: Icons.history_outlined,
            title: 'My Time History',
            subtitle: 'View your entries and request corrections.',
            onTap: onOpenMyHistory),
        _ShortcutCard(
            icon: Icons.groups_outlined,
            title: 'Team Time History',
            subtitle: 'Review company time entries.',
            onTap: onOpenTeamHistory),
        if (showCorrections)
          _ShortcutCard(
              icon: Icons.rule_folder_outlined,
              title: 'Corrections',
              subtitle: 'Approve or reject time correction requests.',
              onTap: onOpenCorrections),
        if (canManagePayPeriods)
          _ShortcutCard(
              icon: Icons.lock_clock_outlined,
              title: 'Pay Periods',
              subtitle: 'Create, lock, unlock, and prepare payroll periods.',
              onTap: onOpenPayPeriods),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ShortcutCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.mutedText)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.mutedText),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveTimeEntryCard extends StatelessWidget {
  final String employeeName;
  final String role;
  final String clockInTime;
  final String runningTime;
  final String jobName;
  final String crewName;
  final bool canEdit;
  final bool onBreak;
  final bool? onBreakIsPaid;
  final VoidCallback onTap;

  const _ActiveTimeEntryCard({
    required this.employeeName,
    required this.role,
    required this.clockInTime,
    required this.runningTime,
    required this.jobName,
    required this.crewName,
    required this.canEdit,
    this.onBreak = false,
    this.onBreakIsPaid,
    required this.onTap,
  });

  String get _displayRole {
    if (role.isEmpty) return 'Employee';
    return role[0].toUpperCase() + role.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(employeeName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                  ),
                  Text(_displayRole, style: const TextStyle(fontSize: 13, color: AppTheme.mutedText)),
                  if (onBreak) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        onBreakIsPaid == true ? 'Paid Break' : 'Unpaid Break',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _TeamTimeRow(label: 'Clocked In', value: clockInTime),
              const SizedBox(height: 8),
              _TeamTimeRow(label: 'Running', value: runningTime),
              const SizedBox(height: 8),
              _TeamTimeRow(label: 'Job', value: jobName),
              const SizedBox(height: 8),
              _TeamTimeRow(label: 'Crew', value: crewName),
              const SizedBox(height: 12),
              Text(
                canEdit ? 'Tap to view details or edit later.' : 'Tap to view details. You cannot edit your own time.',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayEntryCard extends StatelessWidget {
  final String employeeName;
  final String status;
  final String clockIn;
  final String clockOut;
  final String total;
  final bool canEdit;
  final VoidCallback onTap;

  const _TodayEntryCard({
    required this.employeeName,
    required this.status,
    required this.clockIn,
    required this.clockOut,
    required this.total,
    required this.canEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(employeeName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
              const SizedBox(height: 8),
              Text(status, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13)),
              const SizedBox(height: 12),
              _TeamTimeRow(label: 'In', value: clockIn),
              const SizedBox(height: 6),
              _TeamTimeRow(label: 'Out', value: clockOut),
              const SizedBox(height: 6),
              _TeamTimeRow(label: 'Total', value: total),
              const SizedBox(height: 10),
              Text(
                canEdit ? 'Tap to view details or edit later.' : 'Tap to view details. You cannot edit your own time.',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamTimeRow extends StatelessWidget {
  final String label;
  final String value;

  const _TeamTimeRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.mutedText))),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.darkText)),
        ),
      ],
    );
  }
}

class _EmptyTeamTimeCard extends StatelessWidget {
  const _EmptyTeamTimeCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 42, color: AppTheme.blue),
            SizedBox(height: 12),
            Text('Nobody is currently clocked in.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            SizedBox(height: 6),
            Text('Active employees and managers will appear here.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppTheme.mutedText)),
          ],
        ),
      ),
    );
  }
}

class _EmptyTodayEntriesCard extends StatelessWidget {
  const _EmptyTodayEntriesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Text('No time entries today.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.mutedText)),
      ),
    );
  }
}
