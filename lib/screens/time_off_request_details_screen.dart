import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/time_off_request_model.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../Services/time_off_service.dart';
import '../theme/app_theme.dart';

class TimeOffRequestDetailsScreen extends StatefulWidget {
  final String companyId;
  final String requestId;

  const TimeOffRequestDetailsScreen({super.key, required this.companyId, required this.requestId});

  @override
  State<TimeOffRequestDetailsScreen> createState() => _TimeOffRequestDetailsScreenState();
}

class _TimeOffRequestDetailsScreenState extends State<TimeOffRequestDetailsScreen> {
  final AuthService _authService = AuthService();
  final TimeOffService _timeOffService = TimeOffService();
  final EmployeeService _employeeService = EmployeeService();

  bool _isProcessing = false;
  late Future<_DetailsData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_DetailsData> _loadData() async {
    final profile = await _authService.getCurrentUserProfile();

    // TimeOffService only exposes list/watch queries, not a single-request
    // fetch — this reads the doc directly rather than adding a
    // one-off method for a single unreferenced screen.
    final doc = await FirebaseFirestore.instance
        .collection(FSCollections.companies)
        .doc(widget.companyId)
        .collection(FSCompanySub.timeOffRequests)
        .doc(widget.requestId)
        .get();

    if (!doc.exists) {
      throw Exception('This time off request was not found.');
    }

    final request = TimeOffRequestModel.fromSnapshot(doc);
    final employee = await _employeeService.getEmployee(companyId: widget.companyId, employeeId: request.employeeId);

    return _DetailsData(
      request: request,
      employeeName: employee?.fullName ?? 'Unknown',
      jobTitle: employee?.jobTitle,
      actingUserId: profile.uid,
      canApprove: PermissionService.roleHasPermission(profile.role, Permission.timeOffApprove),
    );
  }

  String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

  int _totalDays(TimeOffRequestModel request) => request.endDate.difference(request.startDate).inDays + 1;

  Future<void> _approve(_DetailsData data) async {
    setState(() => _isProcessing = true);
    try {
      await _timeOffService.approveRequest(
        companyId: widget.companyId,
        reviewerUserId: data.actingUserId,
        requestId: widget.requestId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request approved.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _reject(_DetailsData data) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Deny Request?'),
              content: TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reason', hintText: 'Optional'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deny')),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      controller.dispose();
      return;
    }

    setState(() => _isProcessing = true);
    try {
      await _timeOffService.rejectRequest(
        companyId: widget.companyId,
        reviewerUserId: data.actingUserId,
        requestId: widget.requestId,
        reviewNotes: controller.text.trim().isEmpty ? null : controller.text.trim(),
      );
      controller.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request denied.')));
      Navigator.pop(context);
    } catch (e) {
      controller.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
        title: const Text('Time Off Request', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<_DetailsData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  snapshot.error?.toString() ?? 'Unable to load this request.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final request = data.request;

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
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
                        radius: 34,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, color: AppTheme.blue, size: 38),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data.employeeName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(data.jobTitle ?? 'Employee', style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _infoCard(
                title: 'Request Information',
                children: [
                  _infoRow('Start Date', _formatDate(request.startDate)),
                  _infoRow('End Date', _formatDate(request.endDate)),
                  _infoRow('Total Days', _totalDays(request).toString()),
                  if (request.totalHours != null) _infoRow('Hours', request.totalHours.toString()),
                  _infoRow('Status', request.status[0].toUpperCase() + request.status.substring(1)),
                ],
              ),
              if (request.reason?.trim().isNotEmpty == true)
                _infoCard(title: 'Reason', children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(request.reason!, style: const TextStyle(color: AppTheme.darkText, fontSize: 15)),
                  ),
                ]),
              if (request.notes?.trim().isNotEmpty == true)
                _infoCard(title: 'Additional Notes', children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(request.notes!, style: const TextStyle(color: AppTheme.darkText, fontSize: 15)),
                  ),
                ]),
              if (data.canApprove && request.isPending) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isProcessing ? null : () => _approve(data),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve Request'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : () => _reject(data),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Deny Request'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Widget _infoCard({required String title, required List<Widget> children}) {
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.darkText)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppTheme.mutedText))),
          Text(value, style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DetailsData {
  final TimeOffRequestModel request;
  final String employeeName;
  final String? jobTitle;
  final String actingUserId;
  final bool canApprove;

  const _DetailsData({
    required this.request,
    required this.employeeName,
    required this.jobTitle,
    required this.actingUserId,
    required this.canApprove,
  });
}
