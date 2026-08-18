import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/membership.dart';
import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../theme/app_theme.dart';
import 'edit_employee_screen.dart';

/// Preset reasons offered in the archive dialog — covers the common
/// cases (fired, quit, laid off) a manager would actually need to
/// record, plus a free-text option for anything else. The backend only
/// ever stores a single reason string, so picking one of these (with
/// optional extra detail) is just a friendlier way to build that string
/// than a bare text field.
enum _ArchiveReason { resigned, terminated, laidOff, other }

extension on _ArchiveReason {
  String get label {
    switch (this) {
      case _ArchiveReason.resigned:
        return 'Resigned / Quit';
      case _ArchiveReason.terminated:
        return 'Terminated / Fired';
      case _ArchiveReason.laidOff:
        return 'Laid Off';
      case _ArchiveReason.other:
        return 'Other';
    }
  }
}

/// Constructor kept unchanged since employees_screen.dart (already
/// shipped) calls this with employeeId + a raw employeeData map — that
/// map comes from EmployeeModel.toMap(), which conveniently still
/// includes companyId, so this screen can look up everything else
/// (role, crew name, membership status) itself without needing a third
/// constructor parameter.
class EmployeeDetailsScreen extends StatefulWidget {
  final String employeeId;
  final Map<String, dynamic> employeeData;

  const EmployeeDetailsScreen({
    super.key,
    required this.employeeId,
    required this.employeeData,
  });

  @override
  State<EmployeeDetailsScreen> createState() => _EmployeeDetailsScreenState();
}

class _EmployeeDetailsScreenState extends State<EmployeeDetailsScreen> {
  final CrewService _crewService = CrewService();
  final AuthService _authService = AuthService();
  final EmployeeService _employeeService = EmployeeService();

  late String _companyId;
  late Stream<_DetailsReferenceData> _referenceStream;
  late Future<AuthUserProfile> _actingProfileFuture;
  bool _isResendingSetupEmail = false;
  bool _isChangingArchiveStatus = false;

  @override
  void initState() {
    super.initState();
    _companyId = widget.employeeData[FSFields.companyId]?.toString() ?? '';
    _referenceStream = _watchReferenceData();
    _actingProfileFuture = _authService.getCurrentUserProfile();
  }

  Stream<_DetailsReferenceData> _watchReferenceData() async* {
    if (_companyId.isEmpty) {
      final fallback = EmployeeModel.fromMap(widget.employeeId, widget.employeeData);
      yield _DetailsReferenceData(employee: fallback, membership: null, crews: const []);
      return;
    }

    await for (final employeeDoc in FirebaseFirestore.instance
        .collection(FSCollections.companies)
        .doc(_companyId)
        .collection(FSCompanySub.employees)
        .doc(widget.employeeId)
        .snapshots()) {
      final employee = employeeDoc.exists
          ? EmployeeModel.fromSnapshot(employeeDoc)
          : EmployeeModel.fromMap(widget.employeeId, widget.employeeData);

      final membershipDoc = await FirebaseFirestore.instance
          .collection(FSCollections.companies)
          .doc(_companyId)
          .collection(FSCompanySub.memberships)
          .doc(widget.employeeId)
          .get();
      final membership = membershipDoc.data() != null ? MembershipModel.fromSnapshot(membershipDoc) : null;

      final crews = <CrewModel>[];
      for (final crewId in employee.crewIds) {
        final crew = await _crewService.getCrew(companyId: _companyId, crewId: crewId);
        if (crew != null) crews.add(crew);
      }

      yield _DetailsReferenceData(employee: employee, membership: membership, crews: crews);
    }
  }

  Future<void> _resendSetupEmail(EmployeeModel employee) async {
    final email = employee.loginEmail;
    if (email == null || email.trim().isEmpty) return;

    setState(() => _isResendingSetupEmail = true);
    try {
      await _authService.sendPasswordSetupEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Setup email sent to $email.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isResendingSetupEmail = false);
    }
  }

  /// Prompts for an archive reason (fired/quit/laid off/other, plus
  /// optional detail) then archives the employee — this is the action
  /// that was entirely missing from the UI even though
  /// EmployeeService.archiveEmployee already existed and fully worked.
  /// Archiving revokes access immediately; it does not touch historical
  /// time/payroll/job/message records, which all key off employeeId,
  /// not membership status.
  Future<void> _archiveEmployee(String actingUserId) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ArchiveReasonDialog(employeeName: EmployeeModel.fromMap(widget.employeeId, widget.employeeData).fullName),
    );
    if (result == null || result.trim().isEmpty) return;

    setState(() => _isChangingArchiveStatus = true);
    try {
      await _employeeService.archiveEmployee(
        companyId: _companyId,
        actingUserId: actingUserId,
        employeeId: widget.employeeId,
        reason: result.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee archived.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isChangingArchiveStatus = false);
    }
  }

  Future<void> _restoreEmployee(String actingUserId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Employee?'),
        content: const Text('This restores their access and marks them active again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isChangingArchiveStatus = true);
    try {
      await _employeeService.restoreEmployee(
        companyId: _companyId,
        actingUserId: actingUserId,
        employeeId: widget.employeeId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee restored.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isChangingArchiveStatus = false);
    }
  }

  String _roleLabel(String role) {
    if (role.isEmpty) return 'Employee';
    return role[0].toUpperCase() + role.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Employee Details', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<_DetailsReferenceData>(
        stream: _referenceStream,
        builder: (context, snapshot) {
          final reference = snapshot.data;
          if (reference == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final employee = reference.employee;
          final membership = reference.membership;
          final role = membership?.role ?? 'employee';
          final isArchived = membership?.isArchived ?? false;
          final crewName = reference.crews.isNotEmpty
              ? reference.crews.map((c) => c.crewName).join(', ')
              : 'No crew assigned';

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                elevation: 0,
                color: AppTheme.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, color: AppTheme.blue, size: 40),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              employee.fullName.trim().isEmpty ? 'Unnamed' : employee.fullName,
                              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text('${_roleLabel(role)} • $crewName', style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 10),
                            _HeaderStatusBadge(isArchived: isArchived),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _infoCard('Contact Information', Icons.phone_outlined, [
                _infoTile('Phone Number', employee.phone?.trim().isNotEmpty == true ? employee.phone! : 'Not provided',
                    Icons.phone_outlined),
                _infoTile(
                    'Login Email',
                    employee.loginEmail?.trim().isNotEmpty == true ? employee.loginEmail! : 'Not provided',
                    Icons.email_outlined),
              ]),
              _infoCard('Employment', Icons.work_outline, [
                _infoTile('Role', _roleLabel(role), Icons.badge_outlined),
                if (employee.jobTitle?.trim().isNotEmpty == true)
                  _infoTile('Job Title', employee.jobTitle!, Icons.badge_outlined),
                _infoTile('Crew', crewName, Icons.groups_outlined),
                _infoTile('Employment Type', _employmentTypeLabel(employee.employmentType), Icons.check_circle_outline),
                if (employee.employeeNumber?.trim().isNotEmpty == true)
                  _infoTile('Employee Number', employee.employeeNumber!, Icons.fingerprint_outlined),
                if (employee.hireDate != null)
                  _infoTile(
                      'Hire Date',
                      '${employee.hireDate!.month}/${employee.hireDate!.day}/${employee.hireDate!.year}',
                      Icons.event_outlined),
              ]),
              _infoCard('Account', Icons.manage_accounts_outlined, [
                _infoTile('Status', isArchived ? 'Archived' : 'Active', Icons.manage_accounts_outlined),
                _infoTile(
                  'Password Setup',
                  employee.requiresPasswordChange ? 'Not completed yet' : 'Completed',
                  employee.requiresPasswordChange ? Icons.pending_outlined : Icons.check_circle_outline,
                ),
                if (employee.requiresPasswordChange && employee.loginEmail?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _isResendingSetupEmail ? null : () => _resendSetupEmail(employee),
                      icon: _isResendingSetupEmail
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.mail_outline, size: 18),
                      label: Text(_isResendingSetupEmail ? 'Sending...' : 'Resend Setup Email'),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _companyId.isEmpty
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditEmployeeScreen(
                                companyId: _companyId,
                                employeeId: widget.employeeId,
                                employeeData: widget.employeeData,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Employee'),
                ),
              ),
              const SizedBox(height: 10),
              // Was completely missing from the UI — EmployeeService
              // already had a fully-working archive/restore lifecycle
              // (last-owner protection, audit logging, reason capture)
              // with no button anywhere that called it.
              FutureBuilder<AuthUserProfile>(
                future: _actingProfileFuture,
                builder: (context, profileSnapshot) {
                  final actingProfile = profileSnapshot.data;
                  if (actingProfile == null || _companyId.isEmpty) return const SizedBox.shrink();

                  final canArchive = PermissionService.roleHasPermission(
                    actingProfile.role,
                    Permission.employeesArchive,
                  );
                  final canRestore = PermissionService.roleHasPermission(
                    actingProfile.role,
                    Permission.employeesRestore,
                  );

                  if (isArchived && !canRestore) return const SizedBox.shrink();
                  if (!isArchived && !canArchive) return const SizedBox.shrink();

                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isArchived ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                        side: BorderSide(color: isArchived ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
                      ),
                      onPressed: _isChangingArchiveStatus
                          ? null
                          : () => isArchived
                              ? _restoreEmployee(actingProfile.uid)
                              : _archiveEmployee(actingProfile.uid),
                      icon: _isChangingArchiveStatus
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(isArchived ? Icons.person_add_alt_1_outlined : Icons.person_off_outlined, size: 18),
                      label: Text(
                        _isChangingArchiveStatus
                            ? 'Please wait...'
                            : (isArchived ? 'Restore Employee' : 'Archive Employee'),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  String _employmentTypeLabel(String type) {
    switch (type) {
      case EmploymentType.fullTime:
        return 'Full-time';
      case EmploymentType.partTime:
        return 'Part-time';
      case EmploymentType.seasonal:
        return 'Seasonal';
      case EmploymentType.contractor:
        return 'Contractor';
      default:
        return 'Other';
    }
  }

  static Widget _infoCard(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.blue),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.darkText)),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  static Widget _infoTile(String title, String subtitle, IconData icon) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.blue),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _DetailsReferenceData {
  final EmployeeModel employee;
  final MembershipModel? membership;
  final List<CrewModel> crews;

  const _DetailsReferenceData({required this.employee, required this.membership, this.crews = const []});
}

class _HeaderStatusBadge extends StatelessWidget {
  final bool isArchived;

  const _HeaderStatusBadge({required this.isArchived});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isArchived ? Icons.person_off_outlined : Icons.verified_user_outlined, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            isArchived ? 'Archived' : 'Active',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Collects an archive reason and returns it via Navigator.pop —
/// null/empty means the dialog was cancelled. A preset covers the
/// common real-world reasons (fired, quit, laid off) instead of
/// leaving the manager to type free text every time, while "Other"
/// still allows anything not covered by those.
class _ArchiveReasonDialog extends StatefulWidget {
  final String employeeName;

  const _ArchiveReasonDialog({required this.employeeName});

  @override
  State<_ArchiveReasonDialog> createState() => _ArchiveReasonDialogState();
}

class _ArchiveReasonDialogState extends State<_ArchiveReasonDialog> {
  _ArchiveReason _selected = _ArchiveReason.resigned;
  final _detailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.employeeName.trim().isEmpty ? 'this employee' : widget.employeeName;

    return AlertDialog(
      title: Text('Archive $name?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This revokes their access immediately. Historical time, payroll, jobs, and messages are kept.',
              style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
            ),
            const SizedBox(height: 14),
            ..._ArchiveReason.values.map(
              (reason) => RadioListTile<_ArchiveReason>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(reason.label),
                value: reason,
                groupValue: _selected,
                onChanged: (value) => setState(() => _selected = value ?? _selected),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsController,
              decoration: InputDecoration(
                labelText: _selected == _ArchiveReason.other ? 'Reason' : 'Additional details (optional)',
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final details = _detailsController.text.trim();
            if (_selected == _ArchiveReason.other && details.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter a reason.')),
              );
              return;
            }
            final reason = details.isEmpty ? _selected.label : '${_selected.label} - $details';
            Navigator.pop(context, reason);
          },
          child: const Text('Archive'),
        ),
      ],
    );
  }
}
