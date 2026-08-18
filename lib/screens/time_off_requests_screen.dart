import 'package:flutter/material.dart';

import '../Models/company_settings_model.dart';
import '../Models/employee_model.dart';
import '../Models/time_off_request_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../Services/time_off_service.dart';
import '../theme/app_theme.dart';

class TimeOffRequestsScreen extends StatefulWidget {
  const TimeOffRequestsScreen({super.key});

  @override
  State<TimeOffRequestsScreen> createState() => _TimeOffRequestsScreenState();
}

class _TimeOffRequestsScreenState extends State<TimeOffRequestsScreen> {
  final AuthService _authService = AuthService();
  final TimeOffService _timeOffService = TimeOffService();
  final CompanySettingsService _settingsService = CompanySettingsService();
  final EmployeeService _employeeService = EmployeeService();

  final TextEditingController _hoursController = TextEditingController(text: '8');
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late Future<_TimeOffReferenceData> _referenceFuture;

  String _selectedFilter = 'pending';
  String _selectedLeaveType = StandardLeaveTypeIds.pto;
  bool _isFullDay = true;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isSubmitting = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<_TimeOffReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final settings = await _settingsService.getCompanySettings(companyId);
    final canViewTeam = PermissionService.roleHasPermission(profile.role, Permission.timeOffViewTeam);
    final canApprove = PermissionService.roleHasPermission(profile.role, Permission.timeOffApprove);

    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId, includeArchived: true);
    final employeesById = {for (final e in employees) e.employeeId: e.employee};

    return _TimeOffReferenceData(
      companyId: companyId,
      userId: profile.uid,
      settings: settings,
      canViewTeam: canViewTeam,
      canApprove: canApprove,
      employeesById: employeesById,
    );
  }

  List<String> _enabledLeaveTypes(CompanySettingsModel settings) {
    final timeOff = settings.timeOff;
    final enabled = <String>[];
    if (timeOff['pto'] == true) enabled.add(StandardLeaveTypeIds.pto);
    if (timeOff['sick'] == true) enabled.add(StandardLeaveTypeIds.sick);
    if (timeOff['unpaid'] == true) enabled.add(StandardLeaveTypeIds.unpaid);
    if (timeOff['bereavement'] == true) enabled.add(StandardLeaveTypeIds.bereavement);
    if (timeOff['juryDuty'] == true) enabled.add(StandardLeaveTypeIds.juryDuty);
    return enabled;
  }

  String _leaveTypeLabel(String id) {
    switch (id) {
      case StandardLeaveTypeIds.pto:
        return 'PTO';
      case StandardLeaveTypeIds.sick:
        return 'Sick Time';
      case StandardLeaveTypeIds.unpaid:
        return 'Unpaid Time Off';
      case StandardLeaveTypeIds.bereavement:
        return 'Bereavement';
      case StandardLeaveTypeIds.juryDuty:
        return 'Jury Duty';
      default:
        return id;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Choose date';
    return '${date.month}/${date.day}/${date.year}';
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate == null || _endDate!.isBefore(picked)) _endDate = picked;
    });
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  void _clearRequestForm() {
    _selectedLeaveType = StandardLeaveTypeIds.pto;
    _isFullDay = true;
    _startDate = null;
    _endDate = null;
    _hoursController.text = '8';
    _reasonController.clear();
    _notesController.clear();
  }

  Future<void> _submitRequest(_TimeOffReferenceData reference) async {
    final startDate = _startDate;
    final endDate = _endDate;
    final reason = _reasonController.text.trim();

    if (startDate == null || endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a start and end date.')));
      return;
    }
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a reason.')));
      return;
    }

    final hours = _isFullDay ? null : double.tryParse(_hoursController.text.trim());
    if (!_isFullDay && (hours == null || hours <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid partial-day hours.')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _timeOffService.submitTimeOffRequest(
        companyId: reference.companyId,
        employeeId: reference.userId,
        leaveTypeId: _selectedLeaveType,
        isFullDay: _isFullDay,
        startDate: startDate,
        endDate: endDate,
        totalHours: hours,
        reason: reason,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);
      setState(_clearRequestForm);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time off request submitted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _approveRequest(_TimeOffReferenceData reference, String requestId) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await _timeOffService.approveRequest(companyId: reference.companyId, reviewerUserId: reference.userId, requestId: requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time off request approved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectRequest(_TimeOffReferenceData reference, String requestId) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Reject Time Off?'),
              content: TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Reason', hintText: 'Optional rejection reason.'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
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
        companyId: reference.companyId,
        reviewerUserId: reference.userId,
        requestId: requestId,
        reviewNotes: controller.text.trim().isEmpty ? null : controller.text.trim(),
      );
      controller.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time off request rejected.')));
    } catch (e) {
      controller.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cancelRequest(_TimeOffReferenceData reference, String requestId) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Cancel Time Off Request?'),
              content: const Text('This will cancel the request.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Request')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Request')),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isProcessing = true);
    try {
      await _timeOffService.cancelRequest(companyId: reference.companyId, actingUserId: reference.userId, requestId: requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time off request cancelled.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openRequestSheet(_TimeOffReferenceData reference) async {
    if (!_settingsService.isTimeOffEnabled(reference.settings)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time Off has been disabled by your company.')));
      return;
    }

    final enabledTypes = _enabledLeaveTypes(reference.settings);
    if (enabledTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No time off request types are currently enabled.')));
      return;
    }
    if (!enabledTypes.contains(_selectedLeaveType)) {
      _selectedLeaveType = enabledTypes.first;
    }

    await showModalBottomSheet(
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Request Time Off', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _selectedLeaveType,
                      decoration: const InputDecoration(labelText: 'Leave Type'),
                      items: enabledTypes.map((id) => DropdownMenuItem(value: id, child: Text(_leaveTypeLabel(id)))).toList(),
                      onChanged: (value) {
                        if (value != null) setSheetState(() => _selectedLeaveType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(onPressed: _pickStartDate, child: Text('Start: ${_formatDate(_startDate)}')),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(onPressed: _pickEndDate, child: Text('End: ${_formatDate(_endDate)}')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Full Day(s)'),
                      value: _isFullDay,
                      onChanged: (v) => setSheetState(() => _isFullDay = v),
                    ),
                    if (!_isFullDay)
                      TextField(
                        controller: _hoursController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Hours Requested'),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reasonController,
                      decoration: const InputDecoration(labelText: 'Reason'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : () => _submitRequest(reference),
                        child: Text(_isSubmitting ? 'Submitting...' : 'Submit Request'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<TimeOffRequestModel> _filtered(List<TimeOffRequestModel> requests) {
    final filtered = _selectedFilter == 'all'
        ? requests
        : requests.where((r) => r.status == _selectedFilter).toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Time Off', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<_TimeOffReferenceData>(
        future: _referenceFuture,
        builder: (context, refSnapshot) {
          if (refSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (refSnapshot.hasError || !refSnapshot.hasData) {
            return Center(
              child: Text(refSnapshot.error?.toString() ?? 'Unable to load time off.', style: const TextStyle(color: AppTheme.mutedText)),
            );
          }

          final reference = refSnapshot.data!;

          return DefaultTabController(
            length: reference.canViewTeam ? 2 : 1,
            child: Column(
              children: [
                if (reference.canViewTeam)
                  const TabBar(
                    labelColor: AppTheme.blue,
                    unselectedLabelColor: AppTheme.mutedText,
                    tabs: [Tab(text: 'My Requests'), Tab(text: 'Team Requests')],
                  ),
                Expanded(
                  child: reference.canViewTeam
                      ? TabBarView(
                          children: [
                            _MyRequestsList(
                              service: _timeOffService,
                              reference: reference,
                              filter: _selectedFilter,
                              onFilterChanged: (v) => setState(() => _selectedFilter = v),
                              filterFn: _filtered,
                              onCancel: (id) => _cancelRequest(reference, id),
                              leaveTypeLabel: _leaveTypeLabel,
                            ),
                            _TeamRequestsList(
                              service: _timeOffService,
                              reference: reference,
                              onApprove: (id) => _approveRequest(reference, id),
                              onReject: (id) => _rejectRequest(reference, id),
                              leaveTypeLabel: _leaveTypeLabel,
                              isProcessing: _isProcessing,
                            ),
                          ],
                        )
                      : _MyRequestsList(
                          service: _timeOffService,
                          reference: reference,
                          filter: _selectedFilter,
                          onFilterChanged: (v) => setState(() => _selectedFilter = v),
                          filterFn: _filtered,
                          onCancel: (id) => _cancelRequest(reference, id),
                          leaveTypeLabel: _leaveTypeLabel,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => _openRequestSheet(reference),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('Request Time Off'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimeOffReferenceData {
  final String companyId;
  final String userId;
  final CompanySettingsModel settings;
  final bool canViewTeam;
  final bool canApprove;
  final Map<String, EmployeeModel> employeesById;

  const _TimeOffReferenceData({
    required this.companyId,
    required this.userId,
    required this.settings,
    required this.canViewTeam,
    required this.canApprove,
    required this.employeesById,
  });
}

class _MyRequestsList extends StatelessWidget {
  final TimeOffService service;
  final _TimeOffReferenceData reference;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final List<TimeOffRequestModel> Function(List<TimeOffRequestModel>) filterFn;
  final void Function(String requestId) onCancel;
  final String Function(String) leaveTypeLabel;

  const _MyRequestsList({
    required this.service,
    required this.reference,
    required this.filter,
    required this.onFilterChanged,
    required this.filterFn,
    required this.onCancel,
    required this.leaveTypeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TimeOffRequestModel>>(
      stream: service.watchMyRequests(companyId: reference.companyId, employeeId: reference.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = filterFn(snapshot.data ?? []);

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          children: [
            Wrap(
              spacing: 8,
              children: ['pending', 'approved', 'rejected', 'cancelled', 'all']
                  .map((f) => ChoiceChip(
                        label: Text(f[0].toUpperCase() + f.substring(1)),
                        selected: filter == f,
                        onSelected: (_) => onFilterChanged(f),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),
            if (requests.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('No requests found.', style: TextStyle(color: AppTheme.mutedText))),
              )
            else
              ...requests.map((r) => _TimeOffCard(
                    request: r,
                    leaveTypeLabel: leaveTypeLabel(r.leaveTypeId),
                    employeeName: null,
                    trailingAction: r.isCancellable
                        ? OutlinedButton(onPressed: () => onCancel(r.requestId), child: const Text('Cancel'))
                        : null,
                  )),
          ],
        );
      },
    );
  }
}

class _TeamRequestsList extends StatelessWidget {
  final TimeOffService service;
  final _TimeOffReferenceData reference;
  final void Function(String requestId) onApprove;
  final void Function(String requestId) onReject;
  final String Function(String) leaveTypeLabel;
  final bool isProcessing;

  const _TeamRequestsList({
    required this.service,
    required this.reference,
    required this.onApprove,
    required this.onReject,
    required this.leaveTypeLabel,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TimeOffRequestModel>>(
      stream: service.watchPendingRequests(companyId: reference.companyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return const Center(child: Text('No pending requests.', style: TextStyle(color: AppTheme.mutedText)));
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          children: requests
              .map((r) => _TimeOffCard(
                    request: r,
                    leaveTypeLabel: leaveTypeLabel(r.leaveTypeId),
                    employeeName: reference.employeesById[r.employeeId]?.fullName ?? 'Unknown',
                    trailingAction: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isProcessing ? null : () => onReject(r.requestId),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: isProcessing ? null : () => onApprove(r.requestId),
                            child: const Text('Approve'),
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _TimeOffCard extends StatelessWidget {
  final TimeOffRequestModel request;
  final String leaveTypeLabel;
  final String? employeeName;
  final Widget? trailingAction;

  const _TimeOffCard({
    required this.request,
    required this.leaveTypeLabel,
    required this.employeeName,
    required this.trailingAction,
  });

  Color get _statusColor {
    switch (request.status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return AppTheme.mutedText;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = request.startDate;
    final end = request.endDate;
    final dateText = start == end
        ? '${start.month}/${start.day}/${start.year}'
        : '${start.month}/${start.day} - ${end.month}/${end.day}/${end.year}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    employeeName != null ? '$employeeName • $leaveTypeLabel' : leaveTypeLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.darkText),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: _statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    request.status[0].toUpperCase() + request.status.substring(1),
                    style: TextStyle(color: _statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(dateText, style: const TextStyle(color: AppTheme.mutedText)),
            if (request.totalHours != null) ...[
              const SizedBox(height: 4),
              Text('${request.totalHours} hours', style: const TextStyle(color: AppTheme.mutedText)),
            ],
            if (request.reason?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(request.reason!, style: const TextStyle(color: AppTheme.darkText)),
            ],
            if (trailingAction != null) ...[
              const SizedBox(height: 12),
              trailingAction!,
            ],
          ],
        ),
      ),
    );
  }
}
