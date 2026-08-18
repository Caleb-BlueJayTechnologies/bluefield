import 'package:flutter/material.dart';

import '../Models/announcement_model.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Services/announcement_service.dart';
import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../theme/app_theme.dart';

class CreateAnnouncementScreen extends StatefulWidget {
  const CreateAnnouncementScreen({super.key});

  @override
  State<CreateAnnouncementScreen> createState() => _CreateAnnouncementScreenState();
}

class _CreateAnnouncementScreenState extends State<CreateAnnouncementScreen> {
  final AuthService _authService = AuthService();
  final AnnouncementService _announcementService = AnnouncementService();
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _targetType = AnnouncementTargetType.companyWide;
  final Set<String> _selectedCrewIds = {};
  final Set<String> _selectedEmployeeIds = {};
  bool _isPinned = false;
  DateTime? _expiresAt;
  bool _isSaving = false;

  late Future<_FormReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<_FormReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final crews = await _crewService.getCrewsByCompany(companyId: companyId);
    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId);

    return _FormReferenceData(
      companyId: companyId,
      actingUserId: profile.uid,
      crews: crews,
      employees: employees.map((e) => e.employee).toList(),
    );
  }

  Future<void> _pickExpiration() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _expiresAt = picked);
  }

  Future<void> _publish(_FormReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    if (_targetType == AnnouncementTargetType.crew && _selectedCrewIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one crew.')));
      return;
    }
    if (_targetType == AnnouncementTargetType.employees && _selectedEmployeeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one employee.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _announcementService.createAnnouncement(
        companyId: reference.companyId,
        actingUserId: reference.actingUserId,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        targetType: _targetType,
        targetCrewIds: _selectedCrewIds.toList(),
        targetUserIds: _selectedEmployeeIds.toList(),
        isPinned: _isPinned,
        expiresAt: _expiresAt,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement published.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Create Announcement', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                    snapshot.error?.toString() ?? 'Unable to load company data.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                ),
              );
            }

            final reference = snapshot.data!;

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _titleController,
                            decoration: const InputDecoration(labelText: 'Announcement Title'),
                            validator: (v) => _requiredValidator(v, 'Title'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _bodyController,
                            maxLines: 8,
                            decoration: const InputDecoration(labelText: 'Announcement Message'),
                            validator: (v) => _requiredValidator(v, 'Message'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Audience', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: _targetType,
                            decoration: const InputDecoration(labelText: 'Send To'),
                            items: const [
                              DropdownMenuItem(value: AnnouncementTargetType.companyWide, child: Text('All Employees')),
                              DropdownMenuItem(value: AnnouncementTargetType.crew, child: Text('Specific Crews')),
                              DropdownMenuItem(value: AnnouncementTargetType.employees, child: Text('Specific Employees')),
                              DropdownMenuItem(value: AnnouncementTargetType.managersOnly, child: Text('Managers Only')),
                            ],
                            onChanged: (value) {
                              if (value != null) setState(() => _targetType = value);
                            },
                          ),
                          if (_targetType == AnnouncementTargetType.crew) ...[
                            const SizedBox(height: 12),
                            ...reference.crews.map((crew) => CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(crew.crewName),
                                  value: _selectedCrewIds.contains(crew.crewId),
                                  onChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedCrewIds.add(crew.crewId);
                                      } else {
                                        _selectedCrewIds.remove(crew.crewId);
                                      }
                                    });
                                  },
                                )),
                          ],
                          if (_targetType == AnnouncementTargetType.employees) ...[
                            const SizedBox(height: 12),
                            ...reference.employees.map((employee) => CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(employee.fullName),
                                  value: _selectedEmployeeIds.contains(employee.employeeId),
                                  onChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedEmployeeIds.add(employee.employeeId);
                                      } else {
                                        _selectedEmployeeIds.remove(employee.employeeId);
                                      }
                                    });
                                  },
                                )),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Pin to Top'),
                            value: _isPinned,
                            onChanged: (v) => setState(() => _isPinned = v),
                          ),
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: _pickExpiration,
                            icon: const Icon(Icons.event_outlined),
                            label: Text(
                              _expiresAt == null
                                  ? 'Set Expiration (optional)'
                                  : 'Expires ${_expiresAt!.month}/${_expiresAt!.day}/${_expiresAt!.year}',
                            ),
                          ),
                          if (_expiresAt != null)
                            TextButton(
                              onPressed: () => setState(() => _expiresAt = null),
                              child: const Text('Clear expiration'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : () => _publish(reference),
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.campaign_outlined),
                      label: Text(_isSaving ? 'Publishing...' : 'Publish Announcement'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FormReferenceData {
  final String companyId;
  final String actingUserId;
  final List<CrewModel> crews;
  final List<EmployeeModel> employees;

  const _FormReferenceData({
    required this.companyId,
    required this.actingUserId,
    required this.crews,
    required this.employees,
  });
}
