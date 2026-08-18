import 'package:flutter/material.dart';

import '../Models/announcement_model.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Services/announcement_service.dart';
import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../theme/app_theme.dart';

class EditAnnouncementScreen extends StatefulWidget {
  final String companyId;
  final String announcementId;

  const EditAnnouncementScreen({super.key, required this.companyId, required this.announcementId});

  @override
  State<EditAnnouncementScreen> createState() => _EditAnnouncementScreenState();
}

class _EditAnnouncementScreenState extends State<EditAnnouncementScreen> {
  final AuthService _authService = AuthService();
  final AnnouncementService _announcementService = AnnouncementService();
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _targetType = AnnouncementTargetType.companyWide;
  Set<String> _selectedCrewIds = {};
  Set<String> _selectedEmployeeIds = {};
  bool _isPinned = false;
  DateTime? _expiresAt;
  bool _isSaving = false;

  late Future<_EditReferenceData> _referenceFuture;

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

  Future<_EditReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();

    final announcement = await _announcementService.getAnnouncement(
      companyId: widget.companyId,
      announcementId: widget.announcementId,
    );
    if (announcement == null) {
      throw Exception('This announcement was not found.');
    }

    _titleController.text = announcement.title;
    _bodyController.text = announcement.body;
    _targetType = announcement.targetType;
    _selectedCrewIds = announcement.targetCrewIds.toSet();
    _selectedEmployeeIds = announcement.targetUserIds.toSet();
    _isPinned = announcement.isPinned;
    _expiresAt = announcement.expiresAt;

    final crews = await _crewService.getCrewsByCompany(companyId: widget.companyId);
    final employees = await _employeeService.getEmployeesByCompany(companyId: widget.companyId);

    return _EditReferenceData(
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

  Future<void> _saveChanges(_EditReferenceData reference) async {
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
      await _announcementService.updateAnnouncement(
        companyId: widget.companyId,
        actingUserId: reference.actingUserId,
        announcementId: widget.announcementId,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        targetType: _targetType,
        targetCrewIds: _selectedCrewIds.toList(),
        targetUserIds: _selectedEmployeeIds.toList(),
        isPinned: _isPinned,
        expiresAt: _expiresAt,
        clearExpiresAt: _expiresAt == null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement updated.')));
      Navigator.pop(context);
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
        title: const Text('Edit Announcement', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<_EditReferenceData>(
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
                    snapshot.error?.toString() ?? 'Unable to load this announcement.',
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
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
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
                            decoration: const InputDecoration(labelText: 'Title'),
                            validator: (v) => _requiredValidator(v, 'Title'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _bodyController,
                            maxLines: 8,
                            decoration: const InputDecoration(labelText: 'Announcement'),
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
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : () => _saveChanges(reference),
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
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

class _EditReferenceData {
  final String actingUserId;
  final List<CrewModel> crews;
  final List<EmployeeModel> employees;

  const _EditReferenceData({required this.actingUserId, required this.crews, required this.employees});
}
