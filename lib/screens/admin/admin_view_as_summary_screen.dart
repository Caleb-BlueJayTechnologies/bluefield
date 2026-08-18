import 'package:flutter/material.dart';

import '../../Firebase/firestore_schema.dart';
import '../../Models/job_model.dart';
import '../../Services/job_service.dart';
import '../../theme/app_theme.dart';
import 'environment_indicator.dart';

/// A read-only summary of what a specific company member sees —
/// built by calling the exact same visibility-aware service methods
/// the real app uses (JobService.watchVisibleJobs with their own
/// user ID), so this reflects genuinely computed results rather than
/// a simulation. There are deliberately no write actions anywhere on
/// this screen: the platform admin viewing this is still signed in
/// as themselves, and every mutation in the app is gated by the real
/// authenticated user's own permissions regardless of what's shown
/// here.
class AdminViewAsSummaryScreen extends StatefulWidget {
  final String companyId;
  final String companyName;
  final String targetUserId;
  final String targetName;
  final String targetRole;

  const AdminViewAsSummaryScreen({
    super.key,
    required this.companyId,
    required this.companyName,
    required this.targetUserId,
    required this.targetName,
    required this.targetRole,
  });

  @override
  State<AdminViewAsSummaryScreen> createState() => _AdminViewAsSummaryScreenState();
}

class _AdminViewAsSummaryScreenState extends State<AdminViewAsSummaryScreen> {
  final JobService _jobService = JobService();
  late Stream<List<JobModel>> _jobsStream;

  @override
  void initState() {
    super.initState();
    _jobsStream = _jobService.watchVisibleJobs(
      companyId: widget.companyId,
      requestingUserId: widget.targetUserId,
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'manager':
        return 'Manager';
      default:
        return 'Employee';
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case FSJobStatus.draft:
        return 'Draft';
      case FSJobStatus.scheduled:
        return 'Scheduled';
      case FSJobStatus.inProgress:
        return 'In Progress';
      case FSJobStatus.completed:
        return 'Completed';
      case FSJobStatus.cancelled:
        return 'Cancelled';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Viewing As', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const EnvironmentIndicator(),
            Container(
              width: double.infinity,
              color: Colors.purple.shade600,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Viewing as ${widget.targetName} (${_roleLabel(widget.targetRole)}) — ${widget.companyName}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.purple.shade50,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: const Text(
                'Read-only. Nothing here can change real data — you\'re still signed in as yourself.',
                style: TextStyle(color: AppTheme.mutedText, fontSize: 11),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text('Visible Jobs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.darkText)),
                  const SizedBox(height: 4),
                  const Text(
                    'Computed using the same visibility rules the app itself uses for this person\'s role and crew.',
                    style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<JobModel>>(
                    stream: _jobsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)),
                        );
                      }

                      final jobs = (snapshot.data ?? []).where((j) => j.isActive).toList()
                        ..sort((a, b) => (a.startTime ?? a.startDate).compareTo(b.startTime ?? b.startDate));

                      if (jobs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('No active jobs visible to this person.', style: TextStyle(color: AppTheme.mutedText)),
                        );
                      }

                      return Column(
                        children: jobs.map((job) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              leading: const Icon(Icons.work_outline, color: AppTheme.blue),
                              title: Text(job.title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                              subtitle: Text('${_statusLabel(job.status)} • ${job.startDate.month}/${job.startDate.day}/${job.startDate.year}'),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
