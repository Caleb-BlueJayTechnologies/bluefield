import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/correction_request_model.dart';
import '../Models/employee_model.dart';
import '../Models/membership.dart';
import '../Services/permission_service.dart';
import '../Services/time_entry_service.dart';
import '../theme/app_theme.dart';
import 'time_entry_detail_screen.dart';

class CorrectionRequestsScreen extends StatefulWidget {
  const CorrectionRequestsScreen({super.key});

  @override
  State<CorrectionRequestsScreen> createState() => _CorrectionRequestsScreenState();
}

class _CorrectionRequestsScreenState extends State<CorrectionRequestsScreen> {
  final TimeEntryService _timeEntryService = TimeEntryService();
  final PermissionService _permissionService = PermissionService();

  late Future<String> _companyFuture;
  late Future<String> _roleFuture;
  late Future<_ReferenceData> _referenceDataFuture;

  bool _isProcessing = false;

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

  String _formatTime(DateTime? value) {
    if (value == null) return 'Not requested';
    final hour = value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatSubmittedAt(DateTime value) {
    return '${value.month}/${value.day}/${value.year} • ${_formatTime(value)}';
  }

  Future<void> _openTimeEntryDetails({
    required String companyId,
    required CorrectionRequestModel request,
    required String viewerRole,
    required String viewerUserId,
  }) async {
    if (request.timeEntryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This request is not linked to an existing time entry yet.')),
      );
      return;
    }

    try {
      final entryDoc = await FirebaseFirestore.instance
          .collection(FSCollections.companies)
          .doc(companyId)
          .collection(FSCompanySub.timeEntries)
          .doc(request.timeEntryId)
          .get();

      final entryData = entryDoc.data();
      if (entryData == null) {
        throw Exception('Original time entry was not found.');
      }

      final canEdit = _permissionService.canEditTimeEntry(
        viewerRole: viewerRole,
        viewerUserId: viewerUserId,
        entryUserId: entryData[FSFields.employeeId]?.toString() ?? '',
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TimeEntryDetailScreen(
            companyId: companyId,
            timeEntryId: request.timeEntryId!,
            entryData: entryData,
            canEdit: canEdit,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _approveRequest({required String companyId, required CorrectionRequestModel request}) async {
    if (_isProcessing) return;
    final reviewerId = FirebaseAuth.instance.currentUser?.uid;
    if (reviewerId == null) return;

    setState(() => _isProcessing = true);

    try {
      await _timeEntryService.reviewCorrectionRequest(
        companyId: companyId,
        requestId: request.requestId,
        reviewerUserId: reviewerId,
        approve: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Correction approved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectRequest({required String companyId, required CorrectionRequestModel request}) async {
    if (_isProcessing) return;
    final reviewerId = FirebaseAuth.instance.currentUser?.uid;
    if (reviewerId == null) return;

    final reasonController = TextEditingController();

    final shouldReject = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject Correction?'),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Optional reason for rejecting this request.',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
          ],
        );
      },
    );

    if (shouldReject != true) {
      reasonController.dispose();
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await _timeEntryService.reviewCorrectionRequest(
        companyId: companyId,
        requestId: request.requestId,
        reviewerUserId: reviewerId,
        approve: false,
        reviewNotes: reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
      );

      reasonController.dispose();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Correction rejected.')));
    } catch (e) {
      reasonController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  _CorrectionDisplayData _displayDataFor(CorrectionRequestModel request, _ReferenceData reference) {
    final employee = reference.employeesById[request.employeeId];
    final role = reference.membershipsById[request.employeeId]?.role ?? 'employee';

    return _CorrectionDisplayData(
      employeeName: employee?.fullName.trim().isNotEmpty == true ? employee!.fullName : 'Unknown Worker',
      role: role,
      currentClockIn: _formatTime(request.originalClockInAt),
      currentClockOut: _formatTime(request.originalClockOutAt),
      requestedClockIn: _formatTime(request.requestedClockInAt),
      requestedClockOut: _formatTime(request.requestedClockOutAt),
      reason: request.reason.trim().isEmpty ? 'No reason provided.' : request.reason,
      submittedAt: _formatSubmittedAt(request.createdAt),
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
        title: const Text('Correction Requests', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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

                final viewerRole = roleSnapshot.data ?? '';
                final viewerUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

                if (roleSnapshot.hasError ||
                    viewerRole.isEmpty ||
                    !_permissionService.canApproveCorrection(viewerRole)) {
                  return const Center(
                    child: Text('You do not have permission to approve corrections.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppTheme.mutedText)),
                  );
                }

                return FutureBuilder<_ReferenceData>(
                  future: _referenceDataFuture,
                  builder: (context, refSnapshot) {
                    if (refSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final reference = refSnapshot.data ?? const _ReferenceData(employeesById: {}, membershipsById: {});

                    return StreamBuilder<List<CorrectionRequestModel>>(
                      stream: _timeEntryService.watchPendingCorrectionRequests(companyId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final requests = snapshot.data ?? [];

                        return ListView(
                          padding: const EdgeInsets.all(18),
                          children: [
                            _CorrectionSummaryCard(pendingCount: requests.length),
                            const SizedBox(height: 18),
                            if (requests.isEmpty)
                              const _EmptyCorrectionCard()
                            else
                              ...requests.map((request) {
                                final displayData = _displayDataFor(request, reference);

                                return _CorrectionRequestCard(
                                  data: displayData,
                                  isProcessing: _isProcessing,
                                  onApprove: () => _approveRequest(companyId: companyId, request: request),
                                  onReject: () => _rejectRequest(companyId: companyId, request: request),
                                  onViewEntry: () => _openTimeEntryDetails(
                                    companyId: companyId,
                                    request: request,
                                    viewerRole: viewerRole,
                                    viewerUserId: viewerUserId,
                                  ),
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

class _CorrectionDisplayData {
  final String employeeName;
  final String role;
  final String currentClockIn;
  final String currentClockOut;
  final String requestedClockIn;
  final String requestedClockOut;
  final String reason;
  final String submittedAt;

  const _CorrectionDisplayData({
    required this.employeeName,
    required this.role,
    required this.currentClockIn,
    required this.currentClockOut,
    required this.requestedClockIn,
    required this.requestedClockOut,
    required this.reason,
    required this.submittedAt,
  });
}

class _CorrectionSummaryCard extends StatelessWidget {
  final int pendingCount;

  const _CorrectionSummaryCard({required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.edit_note_outlined, color: AppTheme.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$pendingCount Pending Correction${pendingCount == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CorrectionRequestCard extends StatelessWidget {
  final _CorrectionDisplayData data;
  final bool isProcessing;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onViewEntry;

  const _CorrectionRequestCard({
    required this.data,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
    required this.onViewEntry,
  });

  String get _displayRole {
    if (data.role.isEmpty) return 'Employee';
    return data.role[0].toUpperCase() + data.role.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
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
                  child: Text(data.employeeName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                ),
                const _StatusBadge(status: 'pending'),
              ],
            ),
            const SizedBox(height: 6),
            Text(_displayRole, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13)),
            const SizedBox(height: 16),
            _TimeChangeBlock(title: 'Clock In', currentValue: data.currentClockIn, requestedValue: data.requestedClockIn),
            const SizedBox(height: 12),
            _TimeChangeBlock(title: 'Clock Out', currentValue: data.currentClockOut, requestedValue: data.requestedClockOut),
            const SizedBox(height: 14),
            _CorrectionInfoRow(label: 'Reason', value: data.reason),
            const SizedBox(height: 7),
            _CorrectionInfoRow(label: 'Submitted', value: data.submittedAt),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: isProcessing ? null : onViewEntry,
                icon: const Icon(Icons.open_in_new_outlined),
                label: const Text('View Time Entry'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isProcessing ? null : onReject,
                    icon: const Icon(Icons.close_outlined),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isProcessing ? null : onApprove,
                    icon: const Icon(Icons.check_outlined),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeChangeBlock extends StatelessWidget {
  final String title;
  final String currentValue;
  final String requestedValue;

  const _TimeChangeBlock({required this.title, required this.currentValue, required this.requestedValue});

  bool get _hasChange => requestedValue != 'Not requested' && requestedValue != currentValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hasChange ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _hasChange ? Colors.blue.shade100 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          _MiniTimeRow(label: 'Current', value: currentValue),
          const SizedBox(height: 6),
          const Icon(Icons.arrow_downward, size: 18, color: AppTheme.mutedText),
          const SizedBox(height: 6),
          _MiniTimeRow(label: 'Requested', value: requestedValue, highlight: _hasChange),
        ],
      ),
    );
  }
}

class _MiniTimeRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _MiniTimeRow({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 82, child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 12))),
        Expanded(
          child: Text(value,
              style: TextStyle(color: highlight ? AppTheme.blue : AppTheme.darkText, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _CorrectionInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _CorrectionInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13))),
        Expanded(
          child: Text(value, style: const TextStyle(color: AppTheme.darkText, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  Color get _color {
    final normalized = status.toLowerCase().trim();
    if (normalized == 'approved') return Colors.green;
    if (normalized == 'rejected') return Colors.red;
    return Colors.orange;
  }

  String get _label {
    if (status.trim().isEmpty) return 'Pending';
    return status[0].toUpperCase() + status.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color.withOpacity(0.35)),
      ),
      child: Text(_label, style: TextStyle(color: _color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class _EmptyCorrectionCard extends StatelessWidget {
  const _EmptyCorrectionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Text('No pending correction requests.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.mutedText)),
      ),
    );
  }
}
