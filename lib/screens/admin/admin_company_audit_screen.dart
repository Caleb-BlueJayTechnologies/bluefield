import 'package:flutter/material.dart';

import '../../Models/company_audit_log_model.dart';
import '../../Services/company_audit_log_service.dart';
import '../../theme/app_theme.dart';
import 'environment_indicator.dart';

class AdminCompanyAuditScreen extends StatefulWidget {
  final String companyId;
  final String companyName;

  const AdminCompanyAuditScreen({super.key, required this.companyId, required this.companyName});

  @override
  State<AdminCompanyAuditScreen> createState() => _AdminCompanyAuditScreenState();
}

class _AdminCompanyAuditScreenState extends State<AdminCompanyAuditScreen> {
  final CompanyAuditLogService _auditService = CompanyAuditLogService();
  late Stream<List<CompanyAuditEntry>> _logStream;

  @override
  void initState() {
    super.initState();
    _logStream = _auditService.watchLog(widget.companyId);
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'roleChanged':
        return 'Role changed';
      case 'employeeArchived':
        return 'Employee archived';
      case 'employeeRestored':
        return 'Employee restored';
      case 'jobStatusChanged':
        return 'Job status changed';
      default:
        return action;
    }
  }

  IconData _actionIcon(String targetType) {
    switch (targetType) {
      case CompanyAuditTargetType.membership:
        return Icons.badge_outlined;
      case CompanyAuditTargetType.employee:
        return Icons.person_outline;
      case CompanyAuditTargetType.job:
        return Icons.work_outline;
      default:
        return Icons.history_outlined;
    }
  }

  String _formatDate(DateTime value) {
    return '${value.month}/${value.day}/${value.year} • ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: Text('Audit Log — ${widget.companyName}', style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const EnvironmentIndicator(),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Role changes, employee archive/restore, and job status changes for this company. '
                  'This is not a complete record of every action — see the roadmap notes for scope.',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<CompanyAuditEntry>>(
                stream: _logStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('No audit entries yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: Icon(_actionIcon(entry.targetType), color: AppTheme.blue),
                          title: Text('${_actionLabel(entry.action)} — ${entry.targetName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              if (entry.oldValue != null || entry.newValue != null)
                                Text(
                                  '${entry.oldValue ?? '—'} → ${entry.newValue ?? '—'}',
                                  style: const TextStyle(color: AppTheme.mutedText),
                                ),
                              Text('by ${entry.actorName} • ${_formatDate(entry.createdAt)}',
                                  style: const TextStyle(color: AppTheme.mutedText, fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
