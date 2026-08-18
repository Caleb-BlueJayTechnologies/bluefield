import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/job_model.dart';
import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/job_service.dart';
import '../theme/app_theme.dart';
import 'employer_job_details_screen.dart';

class JobHistoryScreen extends StatefulWidget {
  const JobHistoryScreen({super.key});

  @override
  State<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

enum _HistoryFilter { all, completed, cancelled }

class _JobHistoryScreenState extends State<JobHistoryScreen> {
  final AuthService _authService = AuthService();
  final JobService _jobService = JobService();
  final CrewService _crewService = CrewService();

  final _searchController = TextEditingController();
  String _searchText = '';
  _HistoryFilter _filter = _HistoryFilter.all;

  late Future<_HistoryPageData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _historyDate(JobModel job) =>
      job.completedAt ?? job.cancelledAt ?? job.updatedAt;

  Future<_HistoryPageData> _loadData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    // Same visibility rule as jobs_screen.dart: owners/managers with
    // jobs.viewAll see every terminal job, everyone else only sees
    // ones they were actually assigned to. Was hardcoded to
    // ['completed'] only, so a cancelled job had nowhere to live —
    // excluded from the active Jobs list (only active statuses show
    // there) AND excluded from history, making it effectively
    // invisible in the app even though it still existed in Firestore.
    final jobs = await _jobService.getVisibleJobs(
      companyId: companyId,
      requestingUserId: profile.uid,
      statuses: const [FSJobStatus.completed, FSJobStatus.cancelled, FSJobStatus.archived],
    );
    jobs.sort((a, b) => _historyDate(b).compareTo(_historyDate(a)));

    final allCrews = await _crewService.getCrewsByCompany(companyId: companyId, includeArchived: true);
    final crewsById = {for (final c in allCrews) c.crewId: c};

    return _HistoryPageData(historyJobs: jobs, crewsById: crewsById);
  }

  bool _matchesFilter(JobModel job) {
    switch (_filter) {
      case _HistoryFilter.all:
        return true;
      case _HistoryFilter.completed:
        return job.status == FSJobStatus.completed;
      case _HistoryFilter.cancelled:
        return job.status == FSJobStatus.cancelled;
    }
  }

  bool _matchesSearch(JobModel job, Map<String, CrewModel> crewsById) {
    if (_searchText.isEmpty) return true;

    final crewNames = job.assignedCrewIds.map((id) => crewsById[id]?.crewName ?? '').join(' ').toLowerCase();

    return job.title.toLowerCase().contains(_searchText) ||
        (job.customerName ?? '').toLowerCase().contains(_searchText) ||
        (job.jobLocation ?? '').toLowerCase().contains(_searchText) ||
        (job.customerAddress ?? '').toLowerCase().contains(_searchText) ||
        crewNames.contains(_searchText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Job History', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Was hardcoded to completed jobs only, with no way to
              // pull up cancelled ones — this lets someone actually
              // list jobs by status instead of only ever seeing
              // completed work.
              SegmentedButton<_HistoryFilter>(
                segments: const [
                  ButtonSegment(value: _HistoryFilter.all, label: Text('All')),
                  ButtonSegment(value: _HistoryFilter.completed, label: Text('Completed')),
                  ButtonSegment(value: _HistoryFilter.cancelled, label: Text('Cancelled')),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) => setState(() => _filter = selection.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search job history...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FutureBuilder<_HistoryPageData>(
                  future: _dataFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return Center(
                        child: Text(
                          snapshot.error?.toString() ?? 'Unable to load job history.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      );
                    }

                    final data = snapshot.data!;
                    final filtered = data.historyJobs
                        .where(_matchesFilter)
                        .where((j) => _matchesSearch(j, data.crewsById))
                        .toList();

                    if (data.historyJobs.isEmpty) {
                      return const Center(
                        child: Text('No job history yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                      );
                    }
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text('No jobs match your filters.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                      );
                    }

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final job = filtered[index];
                        final crewNames = job.assignedCrewIds
                            .map((id) => data.crewsById[id]?.crewName)
                            .whereType<String>()
                            .toList();

                        return HistoryJobCard(
                          job: job,
                          crewLabel: crewNames.isEmpty ? 'Unassigned' : crewNames.join(', '),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EmployerJobDetailsScreen(
                                  jobData: {...job.toMap(), FSFields.jobId: job.jobId},
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryPageData {
  final List<JobModel> historyJobs;
  final Map<String, CrewModel> crewsById;

  const _HistoryPageData({required this.historyJobs, required this.crewsById});
}

/// Status-aware history card — was hardcoded to always show a green
/// checkmark and a "Completed" badge no matter what, which was
/// misleading back when cancelled jobs weren't visible here at all,
/// and would be actively wrong now that they are.
class HistoryJobCard extends StatelessWidget {
  final JobModel job;
  final String crewLabel;
  final VoidCallback onTap;

  const HistoryJobCard({super.key, required this.job, required this.crewLabel, required this.onTap});

  bool get _isCancelled => job.status == FSJobStatus.cancelled;

  Color get _badgeColor => _isCancelled ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);
  Color get _iconColor => _isCancelled ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
  IconData get _icon => _isCancelled ? Icons.cancel_outlined : Icons.check_circle_outline;
  String get _badgeLabel {
    switch (job.status) {
      case FSJobStatus.cancelled:
        return 'Cancelled';
      case FSJobStatus.archived:
        return 'Archived';
      default:
        return 'Completed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = job.completedAt ?? job.cancelledAt ?? job.updatedAt;
    final dateText = '${date.month}/${date.day}/${date.year}';
    final address = job.jobLocation ?? job.customerAddress ?? 'No address';
    final customer = job.customerName ?? 'No customer';
    final statusLine = _isCancelled
        ? 'Cancelled $dateText${job.cancellationReason?.trim().isNotEmpty == true ? ' • ${job.cancellationReason}' : ''}'
        : '$_badgeLabel $dateText';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: _badgeColor,
                child: Icon(_icon, color: _iconColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                    const SizedBox(height: 5),
                    Text(statusLine, style: const TextStyle(color: AppTheme.mutedText)),
                    const SizedBox(height: 4),
                    Text('$customer • $address • $crewLabel', style: const TextStyle(color: AppTheme.mutedText)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _badgeColor, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  _badgeLabel,
                  style: TextStyle(color: _iconColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
