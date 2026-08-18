import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/correction_request_model.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/job_model.dart';
import '../Models/membership.dart';
import '../Models/time_entry_model.dart';
import '../Services/time_entry_service.dart';
import '../theme/app_theme.dart';

/// Constructor kept unchanged (companyId/timeEntryId/entryData/canEdit)
/// since every caller (team_time_screen, my_time_history_screen,
/// team_time_history_screen, correction_requests_screen) still passes a
/// raw Map from a Firestore doc snapshot. That map now contains our
/// real field names (clockInAt, employeeId, jobId, isEdited, etc.)
/// since it comes from docs written by the rebuilt TimeEntryModel —
/// this screen just needed to stop reading the old field names out of it.
class TimeEntryDetailScreen extends StatefulWidget {
  final String companyId;
  final String timeEntryId;
  final Map<String, dynamic> entryData;
  final bool canEdit;

  const TimeEntryDetailScreen({
    super.key,
    required this.companyId,
    required this.timeEntryId,
    required this.entryData,
    required this.canEdit,
  });

  @override
  State<TimeEntryDetailScreen> createState() => _TimeEntryDetailScreenState();
}

class _TimeEntryDetailScreenState extends State<TimeEntryDetailScreen> {
  final TimeEntryService _timeEntryService = TimeEntryService();

  final TextEditingController _correctionReasonController = TextEditingController();
  final TextEditingController _editReasonController = TextEditingController();

  late TimeEntryModel _entry;

  DateTime? _requestedClockIn;
  DateTime? _requestedClockOut;
  DateTime? _editClockIn;
  DateTime? _editClockOut;

  bool _isSubmitting = false;
  bool _isSavingEdit = false;

  late Future<_DetailReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _entry = TimeEntryModel.fromMap(widget.timeEntryId, widget.entryData);
    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _correctionReasonController.dispose();
    _editReasonController.dispose();
    super.dispose();
  }

  Future<_DetailReferenceData> _loadReferenceData() async {
    final firestore = FirebaseFirestore.instance;
    final companyRef = firestore.collection(FSCollections.companies).doc(widget.companyId);

    final employeeDoc = await companyRef.collection(FSCompanySub.employees).doc(_entry.employeeId).get();
    final membershipDoc = await companyRef.collection(FSCompanySub.memberships).doc(_entry.employeeId).get();
    final jobDoc = _entry.jobId != null
        ? await companyRef.collection(FSCompanySub.jobs).doc(_entry.jobId).get()
        : null;
    final crewDoc = _entry.crewId != null
        ? await companyRef.collection(FSCompanySub.crews).doc(_entry.crewId).get()
        : null;

    return _DetailReferenceData(
      employee: employeeDoc.data() != null ? EmployeeModel.fromSnapshot(employeeDoc) : null,
      membership: membershipDoc.data() != null ? MembershipModel.fromSnapshot(membershipDoc) : null,
      job: jobDoc?.data() != null ? JobModel.fromSnapshot(jobDoc!) : null,
      crew: crewDoc?.data() != null ? CrewModel.fromSnapshot(crewDoc!) : null,
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) return 'Not set';
    final hour = value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Not set';
    return '${value.month}/${value.day}/${value.year} • ${_formatTime(value)}';
  }

  String _formatDuration(Duration? duration) => _timeEntryService.formatDuration(duration);

  bool get _canDirectEdit => widget.canEdit && !_entry.isLocked;

  Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 2),
    );
    if (date == null || !context.mounted) return null;

    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _submitCorrectionRequest() async {
    final reason = _correctionReasonController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a reason for the correction.')));
      return;
    }
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      final requestType = _requestedClockOut == null && _entry.clockOutAt == null
          ? CorrectionRequestType.missingClockOut
          : CorrectionRequestType.bothTimes;

      await _timeEntryService.submitCorrectionRequest(
        companyId: widget.companyId,
        employeeId: _entry.employeeId,
        timeEntryId: _entry.timeEntryId,
        requestType: requestType,
        requestedClockInAt: _requestedClockIn,
        requestedClockOutAt: _requestedClockOut,
        reason: reason,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Correction request submitted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _saveDirectEdit() async {
    final reason = _editReasonController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (!_canDirectEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_entry.isLocked
              ? 'This time entry is locked and cannot be edited.'
              : 'You do not have permission to edit this.'),
        ),
      );
      return;
    }
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a reason for this edit.')));
      return;
    }
    if (user == null) return;

    final newClockIn = _editClockIn ?? _entry.clockInAt;
    final newClockOut = _editClockOut;

    if (newClockOut != null && newClockOut.isBefore(newClockIn)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clock-out cannot be before clock-in.')));
      return;
    }

    setState(() => _isSavingEdit = true);

    try {
      await _timeEntryService.editTimeEntry(
        companyId: widget.companyId,
        timeEntryId: _entry.timeEntryId,
        editedByUserId: user.uid,
        editReason: reason,
        newClockInAt: newClockIn,
        newClockOutAt: newClockOut,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time entry updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSavingEdit = false);
    }
  }

  void _openCorrectionSheet() {
    _requestedClockIn = _entry.clockInAt;
    _requestedClockOut = _entry.clockOutAt;
    _correctionReasonController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Request Time Correction',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                  if (_entry.isLocked) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'This entry is locked. Your request can still be submitted for review.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppTheme.mutedText),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _PickerField(
                    label: 'Requested clock-in',
                    value: _formatDateTime(_requestedClockIn),
                    onTap: () async {
                      final picked = await _pickDateTime(sheetContext, _requestedClockIn ?? DateTime.now());
                      if (picked != null) setSheetState(() => _requestedClockIn = picked);
                    },
                  ),
                  const SizedBox(height: 10),
                  _PickerField(
                    label: 'Requested clock-out',
                    value: _formatDateTime(_requestedClockOut),
                    onTap: () async {
                      final picked = await _pickDateTime(sheetContext, _requestedClockOut ?? DateTime.now());
                      if (picked != null) setSheetState(() => _requestedClockOut = picked);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _correctionReasonController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Reason', hintText: 'Explain what needs to be fixed.'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submitCorrectionRequest,
                      child: Text(_isSubmitting ? 'Submitting...' : 'Submit'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openEditSheet() {
    if (_entry.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This time entry is locked and cannot be edited.')),
      );
      return;
    }

    _editClockIn = _entry.clockInAt;
    _editClockOut = _entry.clockOutAt;
    _editReasonController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Edit Time Entry',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                  const SizedBox(height: 14),
                  _PickerField(
                    label: 'Clock-in',
                    value: _formatDateTime(_editClockIn),
                    onTap: () async {
                      final picked = await _pickDateTime(sheetContext, _editClockIn ?? DateTime.now());
                      if (picked != null) setSheetState(() => _editClockIn = picked);
                    },
                  ),
                  const SizedBox(height: 10),
                  _PickerField(
                    label: 'Clock-out',
                    value: _formatDateTime(_editClockOut),
                    onTap: () async {
                      final picked = await _pickDateTime(sheetContext, _editClockOut ?? DateTime.now());
                      if (picked != null) setSheetState(() => _editClockOut = picked);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _editReasonController,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Reason', hintText: 'Required. Explain why this was changed.'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isSavingEdit ? null : _saveDirectEdit,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_isSavingEdit ? 'Saving...' : 'Save Edit'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = _entry.isLocked;
    final canDirectEdit = _canDirectEdit;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Time Entry Details', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<_DetailReferenceData>(
        future: _referenceFuture,
        builder: (context, refSnapshot) {
          final reference = refSnapshot.data;
          final employeeName =
              reference?.employee?.fullName.trim().isNotEmpty == true ? reference!.employee!.fullName : 'Unknown Worker';
          final role = reference?.membership?.role ?? 'employee';

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
            children: [
              _SectionCard(
                title: employeeName,
                trailing: isLocked ? const _LockedBadge() : null,
                children: [
                  _DetailRow(label: 'Role', value: role.isEmpty ? 'Employee' : role[0].toUpperCase() + role.substring(1)),
                  _DetailRow(label: 'Status', value: _entry.isActive ? 'Clocked in' : 'Clocked out'),
                  _DetailRow(label: 'Clock In', value: _formatTime(_entry.clockInAt)),
                  _DetailRow(label: 'Clock Out', value: _formatTime(_entry.clockOutAt)),
                  _DetailRow(label: 'Total', value: _formatDuration(_entry.rawDuration)),
                  if (_entry.isOnBreak)
                    _DetailRow(
                      label: 'On Break',
                      value: '${_entry.activeBreak!.isPaid ? 'Paid' : 'Unpaid'} — ${_formatDuration(_entry.activeBreak!.duration)} so far',
                    ),
                ],
              ),
              if (_entry.breaks.isNotEmpty) ...[
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Breaks',
                  children: [
                    _DetailRow(label: 'Paid break time', value: _formatDuration(_entry.totalPaidBreakDuration)),
                    _DetailRow(label: 'Unpaid break time', value: _formatDuration(_entry.totalUnpaidBreakDuration)),
                    for (var i = 0; i < _entry.breaks.length; i++)
                      _DetailRow(
                        label: '${_entry.breaks[i].isPaid ? 'Paid' : 'Unpaid'} break ${i + 1}',
                        value: '${_formatTime(_entry.breaks[i].startedAt)} - ${_entry.breaks[i].endedAt != null ? _formatTime(_entry.breaks[i].endedAt) : 'ongoing'}',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Work Assignment',
                children: [
                  _DetailRow(label: 'Job', value: reference?.job?.title ?? 'No linked job'),
                  _DetailRow(label: 'Crew', value: reference?.crew?.crewName ?? 'No linked crew'),
                ],
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Permissions',
                children: [
                  _DetailRow(label: 'Can Edit', value: canDirectEdit ? 'Yes' : 'No'),
                  _DetailRow(label: 'Locked', value: isLocked ? 'Yes' : 'No'),
                  _DetailRow(label: 'Pay Period', value: _entry.payPeriodId ?? 'Not assigned'),
                  _DetailRow(label: 'Pending Correction', value: _entry.hasPendingCorrectionRequest ? 'Yes' : 'No'),
                ],
              ),
              const SizedBox(height: 14),
              // Reflects the model's actual capacity: TimeEntryModel keeps
              // only the most recent edit's before/after values, not a
              // full multi-edit history. A true audit trail across every
              // edit ever made would need its own append-only collection
              // (Section 23), which isn't built yet — this section is
              // honest about showing "last edit" rather than faking a
              // history list.
              if (_entry.isEdited)
                _SectionCard(
                  title: 'Last Edit',
                  children: [
                    _DetailRow(label: 'Edited By', value: _entry.editedBy ?? 'Unknown'),
                    _DetailRow(label: 'Edited At', value: _formatDateTime(_entry.editedAt)),
                    _DetailRow(label: 'Reason', value: _entry.editReason ?? 'No reason provided.'),
                    _DetailRow(label: 'Original Clock In', value: _formatDateTime(_entry.originalClockInAt)),
                    _DetailRow(label: 'Original Clock Out', value: _formatDateTime(_entry.originalClockOutAt)),
                  ],
                ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _openCorrectionSheet,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: Text(isLocked ? 'Request Locked Entry Correction' : 'Request Correction'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: canDirectEdit ? _openEditSheet : null,
                  icon: Icon(isLocked ? Icons.lock_outline : Icons.edit_outlined),
                  label: Text(
                    isLocked
                        ? 'Locked Time Entry'
                        : widget.canEdit
                            ? 'Edit Time Entry'
                            : 'Cannot Edit This Time Entry',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailReferenceData {
  final EmployeeModel? employee;
  final MembershipModel? membership;
  final JobModel? job;
  final CrewModel? crew;

  const _DetailReferenceData({this.employee, this.membership, this.job, this.crew});
}

class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickerField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.children, this.trailing});

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
            Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LockedBadge extends StatelessWidget {
  const _LockedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 14, color: Colors.orange),
          SizedBox(width: 4),
          Text('Locked', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13))),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppTheme.darkText, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
