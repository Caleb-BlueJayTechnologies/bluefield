import 'package:flutter/material.dart';

import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/time_off_service.dart';
import '../Models/time_off_request_model.dart';
import '../theme/app_theme.dart';

class EmployeeTimeOffRequestScreen extends StatefulWidget {
  const EmployeeTimeOffRequestScreen({super.key});

  @override
  State<EmployeeTimeOffRequestScreen> createState() => _EmployeeTimeOffRequestScreenState();
}

class _EmployeeTimeOffRequestScreenState extends State<EmployeeTimeOffRequestScreen> {
  final AuthService _authService = AuthService();
  final TimeOffService _timeOffService = TimeOffService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  final TextEditingController _hoursController = TextEditingController(text: '8');
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String _selectedLeaveType = StandardLeaveTypeIds.pto;
  bool _isFullDay = true;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isSubmitting = false;
  late Future<_FormReferenceData> _referenceFuture;

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

  Future<_FormReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;
    final settings = await _settingsService.getCompanySettings(companyId);

    final timeOff = settings.timeOff;
    final enabledTypes = <String>[];
    if (timeOff['pto'] == true) enabledTypes.add(StandardLeaveTypeIds.pto);
    if (timeOff['sick'] == true) enabledTypes.add(StandardLeaveTypeIds.sick);
    if (timeOff['unpaid'] == true) enabledTypes.add(StandardLeaveTypeIds.unpaid);
    if (timeOff['bereavement'] == true) enabledTypes.add(StandardLeaveTypeIds.bereavement);
    if (timeOff['juryDuty'] == true) enabledTypes.add(StandardLeaveTypeIds.juryDuty);

    if (enabledTypes.isNotEmpty) _selectedLeaveType = enabledTypes.first;

    return _FormReferenceData(
      companyId: companyId,
      employeeId: profile.uid,
      isTimeOffEnabled: _settingsService.isTimeOffEnabled(settings),
      enabledTypes: enabledTypes,
    );
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

  Future<void> _submitRequest(_FormReferenceData reference) async {
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
        employeeId: reference.employeeId,
        leaveTypeId: _selectedLeaveType,
        isFullDay: _isFullDay,
        startDate: startDate,
        endDate: endDate,
        totalHours: hours,
        reason: reason,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time off request submitted.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _dateButton({required String label, required DateTime? date, required VoidCallback onTap}) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text('$label: ${_formatDate(date)}', style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
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
        title: const Text('Request Time Off', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<_FormReferenceData>(
          future: _referenceFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    snapshot.error?.toString() ?? 'Unable to load time off settings.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                ),
              );
            }

            final reference = snapshot.data!;

            if (!reference.isTimeOffEnabled) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Time Off requests have been disabled by your company.', style: TextStyle(color: AppTheme.mutedText)),
                ),
              );
            }
            if (reference.enabledTypes.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No time off request types are currently enabled.', style: TextStyle(color: AppTheme.mutedText)),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Time Off Details', style: TextStyle(color: AppTheme.darkText, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                          'Submit PTO, sick time, unpaid time off, bereavement, or jury duty.',
                          style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedLeaveType,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: reference.enabledTypes
                              .map((type) => DropdownMenuItem<String>(value: type, child: Text(_leaveTypeLabel(type))))
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedLeaveType = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        _dateButton(label: 'Start Date', date: _startDate, onTap: _pickStartDate),
                        const SizedBox(height: 10),
                        _dateButton(label: 'End Date', date: _endDate, onTap: _pickEndDate),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Full Day(s)'),
                          value: _isFullDay,
                          onChanged: (v) => setState(() => _isFullDay = v),
                        ),
                        if (!_isFullDay)
                          TextField(
                            controller: _hoursController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Hours Requested', hintText: 'Example: 4'),
                          ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _reasonController,
                          decoration: const InputDecoration(labelText: 'Reason', hintText: 'Example: Appointment, sick, vacation'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesController,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Additional Notes', hintText: 'Optional'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : () => _submitRequest(reference),
                    icon: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined),
                    label: Text(_isSubmitting ? 'Submitting...' : 'Submit Request'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FormReferenceData {
  final String companyId;
  final String employeeId;
  final bool isTimeOffEnabled;
  final List<String> enabledTypes;

  const _FormReferenceData({
    required this.companyId,
    required this.employeeId,
    required this.isTimeOffEnabled,
    required this.enabledTypes,
  });
}
