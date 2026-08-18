import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/job_model.dart';
import '../Models/membership.dart';
import '../Models/time_entry_model.dart';
import '../Services/permission_service.dart';
import '../Services/time_entry_service.dart';
import '../theme/app_theme.dart';
import 'time_entry_detail_screen.dart';

class TeamTimeHistoryScreen extends StatefulWidget {
  const TeamTimeHistoryScreen({super.key});

  @override
  State<TeamTimeHistoryScreen> createState() => _TeamTimeHistoryScreenState();
}

class _TeamTimeHistoryScreenState extends State<TeamTimeHistoryScreen> {
  final TimeEntryService _timeEntryService = TimeEntryService();
  final PermissionService _permissionService = PermissionService();

  late Future<String> _companyFuture;
  late Future<String> _roleFuture;
  late Future<_ReferenceData> _referenceDataFuture;

  String _selectedFilter = 'today';

  @override
  void initState() {
    super.initState();
    _companyFuture = _timeEntryService.getCurrentCompanyId();
    _roleFuture = _permissionService.getCurrentUserRole();
    _referenceDataFuture = _companyFuture.then(_loadReferenceData);
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
      employeesById: {for (final d in employeesSnap.docs) d.id: EmployeeModel.fromSnapshot(d)},
      membershipsById: {for (final d in membershipsSnap.docs) d.id: MembershipModel.fromSnapshot(d)},
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _entriesStream(String companyId) {
    return FirebaseFirestore.instance
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeEntries)
        .snapshots();
  }

  bool _matchesFilter(DateTime clockIn) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entryDay = DateTime(clockIn.year, clockIn.month, clockIn.day);

    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = weekStart.subtract(const Duration(days: 1));

    switch (_selectedFilter) {
      case 'today':
        return entryDay == today;
      case 'thisWeek':
        return !entryDay.isBefore(weekStart);
      case 'lastWeek':
        return !entryDay.isBefore(lastWeekStart) && !entryDay.isAfter(lastWeekEnd);
      case 'thisMonth':
        return clockIn.year == now.year && clockIn.month == now.month;
      default:
        return true;
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Team Time History', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _companyFuture,
          builder: (context, companySnapshot) {
            if (companySnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (companySnapshot.hasError || companySnapshot.data == null || companySnapshot.data!.isEmpty) {
              return Center(
                child: Text(companySnapshot.error?.toString() ?? 'Company not found.',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.mutedText)),
              );
            }

            final companyId = companySnapshot.data!;

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

                return FutureBuilder<_ReferenceData>(
                  future: _referenceDataFuture,
                  builder: (context, refSnapshot) {
                    if (refSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final reference = refSnapshot.data ?? const _ReferenceData(employeesById: {}, membershipsById: {});

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _entriesStream(companyId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final allDocs = snapshot.data?.docs ?? [];
                        final pairs = allDocs
                            .map((d) => MapEntry(d, TimeEntryModel.fromSnapshot(d)))
                            .where((p) => _matchesFilter(p.value.clockInAt))
                            .toList()
                          ..sort((a, b) => b.value.clockInAt.compareTo(a.value.clockInAt));

                        final entries = pairs.map((p) => p.value).toList();
                        final totalMinutes =
                            entries.map((e) => e.rawDuration?.inMinutes ?? 0).fold<int>(0, (s, m) => s + m);

                        return FutureBuilder<List<dynamic>>(
                          future: Future.wait([
                            _resolveJobs(companyId, entries),
                            _resolveCrews(companyId, entries),
                          ]),
                          builder: (context, resolveSnapshot) {
                            final jobsById = (resolveSnapshot.data?[0] as Map<String, JobModel>?) ?? {};
                            final crewsById = (resolveSnapshot.data?[1] as Map<String, CrewModel>?) ?? {};

                            return ListView(
                              padding: const EdgeInsets.all(18),
                              children: [
                                _HistoryHeaderCard(entryCount: entries.length, totalHours: _formatMinutes(totalMinutes)),
                                const SizedBox(height: 14),
                                _FilterBar(
                                  selectedFilter: _selectedFilter,
                                  onChanged: (value) => setState(() => _selectedFilter = value),
                                ),
                                const SizedBox(height: 18),
                                if (pairs.isEmpty)
                                  const _EmptyTeamHistoryCard()
                                else
                                  ...pairs.map((pair) {
                                    final entry = pair.value;
                                    final employee = reference.employeesById[entry.employeeId];
                                    final role = reference.membershipsById[entry.employeeId]?.role ?? 'employee';
                                    final job = entry.jobId != null ? jobsById[entry.jobId] : null;
                                    final crew = entry.crewId != null ? crewsById[entry.crewId] : null;

                                    final canEdit = _permissionService.canEditTimeEntry(
                                      viewerRole: viewerRole,
                                      viewerUserId: viewerUserId,
                                      entryUserId: entry.employeeId,
                                    );

                                    final baseStatus = entry.isActive ? 'Clocked in' : 'Clocked out';
                                    final status = entry.isEdited ? '$baseStatus • Edited' : baseStatus;

                                    return _TeamHistoryEntryCard(
                                      employeeName:
                                          employee?.fullName.trim().isNotEmpty == true ? employee!.fullName : 'Unknown Worker',
                                      role: role,
                                      status: status,
                                      clockIn: _timeEntryService.formatTime(entry.clockInAt),
                                      clockOut: _timeEntryService.formatTime(entry.clockOutAt),
                                      total: _formatMinutes(entry.rawDuration?.inMinutes ?? 0),
                                      jobName: job?.title ?? 'No linked job',
                                      crewName: crew?.crewName ?? 'No linked crew',
                                      canEdit: canEdit,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => TimeEntryDetailScreen(
                                              companyId: companyId,
                                              timeEntryId: entry.timeEntryId,
                                              entryData: pair.key.data(),
                                              canEdit: canEdit,
                                            ),
                                          ),
                                        );
                                      },
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

class _HistoryHeaderCard extends StatelessWidget {
  final int entryCount;
  final String totalHours;

  const _HistoryHeaderCard({required this.entryCount, required this.totalHours});

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
            const Text('Filtered Time Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            const SizedBox(height: 12),
            Text(totalHours, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            const SizedBox(height: 8),
            Text('$entryCount entries', style: const TextStyle(color: AppTheme.mutedText)),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String selectedFilter;
  final ValueChanged<String> onChanged;

  const _FilterBar({required this.selectedFilter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChipButton(label: 'All', value: 'all', selectedFilter: selectedFilter, onChanged: onChanged),
        _FilterChipButton(label: 'Today', value: 'today', selectedFilter: selectedFilter, onChanged: onChanged),
        _FilterChipButton(label: 'This Week', value: 'thisWeek', selectedFilter: selectedFilter, onChanged: onChanged),
        _FilterChipButton(label: 'Last Week', value: 'lastWeek', selectedFilter: selectedFilter, onChanged: onChanged),
        _FilterChipButton(label: 'This Month', value: 'thisMonth', selectedFilter: selectedFilter, onChanged: onChanged),
      ],
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final String value;
  final String selectedFilter;
  final ValueChanged<String> onChanged;

  const _FilterChipButton({
    required this.label,
    required this.value,
    required this.selectedFilter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selectedFilter;
    return ChoiceChip(label: Text(label), selected: isSelected, onSelected: (_) => onChanged(value));
  }
}

class _TeamHistoryEntryCard extends StatelessWidget {
  final String employeeName;
  final String role;
  final String status;
  final String clockIn;
  final String clockOut;
  final String total;
  final String jobName;
  final String crewName;
  final bool canEdit;
  final VoidCallback onTap;

  const _TeamHistoryEntryCard({
    required this.employeeName,
    required this.role,
    required this.status,
    required this.clockIn,
    required this.clockOut,
    required this.total,
    required this.jobName,
    required this.crewName,
    required this.canEdit,
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
                  Expanded(
                    child: Text(employeeName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                  ),
                  Text(_displayRole, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Text(status, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13)),
              const SizedBox(height: 12),
              _HistoryRow(label: 'In', value: clockIn),
              _HistoryRow(label: 'Out', value: clockOut),
              _HistoryRow(label: 'Total', value: total),
              _HistoryRow(label: 'Job', value: jobName),
              _HistoryRow(label: 'Crew', value: crewName),
              const SizedBox(height: 10),
              Text(
                canEdit ? 'Tap to view/edit.' : 'Tap to view. Editing blocked.',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String label;
  final String value;

  const _HistoryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13))),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppTheme.darkText, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _EmptyTeamHistoryCard extends StatelessWidget {
  const _EmptyTeamHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Text('No time entries match this filter.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.mutedText)),
      ),
    );
  }
}
