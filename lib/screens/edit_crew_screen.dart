import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../theme/app_theme.dart';

class EditCrewScreen extends StatefulWidget {
  final String crewId;
  final Map<String, dynamic> crewData;

  const EditCrewScreen({super.key, required this.crewId, required this.crewData});

  @override
  State<EditCrewScreen> createState() => _EditCrewScreenState();
}

class _EditCrewScreenState extends State<EditCrewScreen> {
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();

  final _formKey = GlobalKey<FormState>();

  late final CrewModel _originalCrew;
  late final TextEditingController _crewNameController;
  late final TextEditingController _descriptionController;

  String? _selectedLeaderId;
  bool _isSaving = false;
  late Future<_EditReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _originalCrew = CrewModel.fromMap(widget.crewId, widget.crewData);

    _crewNameController = TextEditingController(text: _originalCrew.crewName);
    _descriptionController = TextEditingController(text: _originalCrew.description ?? '');
    _selectedLeaderId = _originalCrew.leaderId;

    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _crewNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<_EditReferenceData> _loadReferenceData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user is currently signed in.');

    final employees = await _employeeService.getEmployeesByCompany(companyId: _originalCrew.companyId);

    return _EditReferenceData(
      actingUserId: user.uid,
      employees: employees.map((e) => e.employee).toList(),
    );
  }

  Future<void> _saveChanges(_EditReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await _crewService.updateCrew(
        companyId: _originalCrew.companyId,
        actingUserId: reference.actingUserId,
        crewId: widget.crewId,
        crewName: _crewNameController.text.trim(),
        description: _descriptionController.text.trim(),
        clearLeader: _selectedLeaderId == null,
        leaderId: _selectedLeaderId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crew updated successfully.')));
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleArchive(_EditReferenceData reference) async {
    try {
      if (_originalCrew.isArchived) {
        await _crewService.restoreCrew(
          companyId: _originalCrew.companyId,
          actingUserId: reference.actingUserId,
          crewId: widget.crewId,
        );
      } else {
        await _crewService.archiveCrew(
          companyId: _originalCrew.companyId,
          actingUserId: reference.actingUserId,
          crewId: widget.crewId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_originalCrew.isArchived ? 'Crew restored.' : 'Crew archived.')),
      );
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
        title: const Text('Edit Crew', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                    snapshot.error?.toString() ?? 'Unable to load crew data.',
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
                  _section('Crew Information', [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _crewNameController,
                        decoration: const InputDecoration(labelText: 'Crew Name'),
                        validator: (v) => _requiredValidator(v, 'Crew name'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String?>(
                        value: _selectedLeaderId,
                        decoration: const InputDecoration(labelText: 'Crew Leader (optional)'),
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
                  _section('Description', [
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: 'Description (optional)'),
                    ),
                  ]),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => _toggleArchive(reference),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _originalCrew.isArchived ? AppTheme.blue : Colors.red,
                      ),
                      icon: Icon(_originalCrew.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
                      label: Text(_originalCrew.isArchived ? 'Restore Crew' : 'Archive Crew'),
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
  final List<EmployeeModel> employees;

  const _EditReferenceData({required this.actingUserId, required this.employees});
}
