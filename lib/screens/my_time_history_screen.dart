import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/job_model.dart';
import '../Models/time_entry_model.dart';
import '../Services/company_settings_service.dart';
import '../Services/time_entry_service.dart';
import '../theme/app_theme.dart';
import 'time_entry_detail_screen.dart';

class MyTimeHistoryScreen extends StatefulWidget {
  const MyTimeHistoryScreen({super.key});

  @override
  State<MyTimeHistoryScreen> createState() => _MyTimeHistoryScreenState();
}

class _MyTimeHistoryScreenState extends State<MyTimeHistoryScreen> {
  final TimeEntryService _timeEntryService = TimeEntryService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  late Future<({String companyId, bool selfEditEnabled})> _companyFuture;

  // Ticks the UI every 30s so an active entry's running duration counts
  // up live instead of freezing at whatever value it had when this
  // screen was last rebuilt.
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _companyFuture = _loadCompanyInfo();
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<({String companyId, bool selfEditEnabled})> _loadCompanyInfo() async {
    final companyId = await _timeEntryService.getCurrentCompanyId();
    final settings = await _settingsService.getCompanySettings(companyId);
    return (companyId: companyId, selfEditEnabled: settings.employeeSelfEditEnabled);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _myEntriesStream(String companyId, String userId) {
    return FirebaseFirestore.instance
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeEntries)
        .where(FSFields.employeeId, isEqualTo: userId)
        .snapshots();
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

  int _totalMinutesThisWeek(List<TimeEntryModel> entries) {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));

    int total = 0;
    for (final entry in entries) {
      if (entry.clockInAt.isBefore(weekStart)) continue;
      total += entry.rawDuration?.inMinutes ?? 0;
    }
    return total;
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('My Time History', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<({String companyId, bool selfEditEnabled})>(
          future: _companyFuture,
          builder: (context, companySnapshot) {
            if (companySnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (user == null) {
              return const Center(child: Text('No user signed in.', style: TextStyle(color: AppTheme.mutedText)));
            }

            if (companySnapshot.hasError || companySnapshot.data == null || companySnapshot.data!.companyId.isEmpty) {
              return Center(
                child: Text(companySnapshot.error?.toString() ?? 'Company not found.',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.mutedText)),
              );
            }

            final companyId = companySnapshot.data!.companyId;
            final selfEditEnabled = companySnapshot.data!.selfEditEnabled;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _myEntriesStream(companyId, user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                // Pair each doc with its parsed model, then sort the
                // pairs together so the raw doc (needed for the detail
                // screen's still-Map<String,dynamic> constructor) stays
                // aligned with the entry it belongs to.
                final pairs = docs.map((d) => MapEntry(d, TimeEntryModel.fromSnapshot(d))).toList()
                  ..sort((a, b) => b.value.clockInAt.compareTo(a.value.clockInAt));

                final entries = pairs.map((p) => p.value).toList();
                final totalThisWeek = _totalMinutesThisWeek(entries);

                return FutureBuilder<Map<String, JobModel>>(
                  future: _resolveJobs(companyId, entries),
                  builder: (context, jobsSnapshot) {
                    final jobsById = jobsSnapshot.data ?? {};

                    return ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        _HistorySummaryCard(
                          totalEntries: entries.length,
                          weeklyTotal: _formatMinutes(totalThisWeek),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Recent Entries',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                        ),
                        const SizedBox(height: 12),
                        if (pairs.isEmpty)
                          const _EmptyHistoryCard()
                        else
                          ...pairs.map((pair) {
                            final entry = pair.value;
                            final job = entry.jobId != null ? jobsById[entry.jobId] : null;

                            return _HistoryEntryCard(
                              status: entry.isActive ? 'Clocked in' : 'Clocked out',
                              clockIn: _timeEntryService.formatTime(entry.clockInAt),
                              clockOut: _timeEntryService.formatTime(entry.clockOutAt),
                              duration: entry.isActive
                                  ? _timeEntryService.formatDuration(DateTime.now().difference(entry.clockInAt))
                                  : _timeEntryService.formatDuration(entry.rawDuration),
                              jobName: job?.title ?? 'No linked job',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TimeEntryDetailScreen(
                                      companyId: companyId,
                                      timeEntryId: entry.timeEntryId,
                                      entryData: pair.key.data(),
                                      canEdit: selfEditEnabled,
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
        ),
      ),
    );
  }
}

class _HistorySummaryCard extends StatelessWidget {
  final int totalEntries;
  final String weeklyTotal;

  const _HistorySummaryCard({required this.totalEntries, required this.weeklyTotal});

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
            const Text('This Week', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            const SizedBox(height: 12),
            Text(weeklyTotal, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            const SizedBox(height: 8),
            Text('$totalEntries total entries on file', style: const TextStyle(color: AppTheme.mutedText)),
          ],
        ),
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  final String status;
  final String clockIn;
  final String clockOut;
  final String duration;
  final String jobName;
  final VoidCallback onTap;

  const _HistoryEntryCard({
    required this.status,
    required this.clockIn,
    required this.clockOut,
    required this.duration,
    required this.jobName,
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
              Text(status, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
              const SizedBox(height: 12),
              _MiniRow(label: 'In', value: clockIn),
              _MiniRow(label: 'Out', value: clockOut),
              _MiniRow(label: 'Total', value: duration),
              _MiniRow(label: 'Job', value: jobName),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  final String label;
  final String value;

  const _MiniRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13))),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppTheme.darkText, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Text('No time entries yet.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.mutedText)),
      ),
    );
  }
}
