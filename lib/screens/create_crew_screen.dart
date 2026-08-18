import 'package:flutter/material.dart';

import '../Models/employee_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../theme/app_theme.dart';

class CreateCrewScreen extends StatefulWidget {
  const CreateCrewScreen({super.key});

  @override
  State<CreateCrewScreen> createState() => _CreateCrewScreenState();
}

class _CreateCrewScreenState extends State<CreateCrewScreen> {
  final AuthService _authService = AuthService();
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  final _formKey = GlobalKey<FormState>();

  final _crewNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedLeaderId;
  bool _isSaving = false;
  String _crewLabel = 'Crew';

  late Future<_FormReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _crewNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<_FormReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final settings = await _settingsService.getCompanySettings(companyId);
    _crewLabel = settings.crewTerminology == 'team' ? 'Team' : 'Crew';

    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId);

    return _FormReferenceData(
      companyId: companyId,
      actingUserId: profile.uid,
      employees: employees.map((e) => e.employee).toList(),
    );
  }

  Future<void> _createCrew(_FormReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await _crewService.createCrew(
        companyId: reference.companyId,
        actingUserId: reference.actingUserId,
        crewName: _crewNameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        leaderId: _selectedLeaderId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_crewLabel created successfully.')));
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

  Widget _section(String title, List<Widget> children) {
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
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
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
        title: Text('Create $_crewLabel', style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                  _section('$_crewLabel Information', [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _crewNameController,
                        decoration: InputDecoration(labelText: '$_crewLabel Name'),
                        validator: (v) => _requiredValidator(v, '$_crewLabel name'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String?>(
                        value: _selectedLeaderId,
                        decoration: InputDecoration(labelText: '$_crewLabel Leader (optional)'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('No leader')),
                          ...reference.employees.map(
                            (e) => DropdownMenuItem<String?>(value: e.employeeId, child: Text(e.fullName)),
                          ),
                        ],
                        onChanged: (value) => setState(() => _selectedLeaderId = value),
                      ),
                    ),
                  ]),
                  _section('Members', [
                    Text('Members are added from this ${_crewLabel.toLowerCase()}\'s details page after creation.',
                        style: const TextStyle(color: AppTheme.mutedText)),
                  ]),
                  _section('Description', [
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: 'Description (optional)'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : () => _createCrew(reference),
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.group_add_outlined),
                      label: Text(_isSaving ? 'Saving...' : 'Create $_crewLabel'),
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
  final List<EmployeeModel> employees;

  const _FormReferenceData({required this.companyId, required this.actingUserId, required this.employees});
}
