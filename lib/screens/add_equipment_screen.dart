import 'package:flutter/material.dart';

import '../Models/employee_model.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/equipment_service.dart';
import '../theme/app_theme.dart';

class AddEquipmentScreen extends StatefulWidget {
  const AddEquipmentScreen({super.key});

  @override
  State<AddEquipmentScreen> createState() => _AddEquipmentScreenState();
}

class _AddEquipmentScreenState extends State<AddEquipmentScreen> {
  final AuthService _authService = AuthService();
  final EquipmentService _equipmentService = EquipmentService();
  final EmployeeService _employeeService = EmployeeService();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _serialController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedEmployeeId;
  bool _isSaving = false;

  late Future<_FormReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _serialController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<_FormReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;
    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId);

    return _FormReferenceData(
      companyId: companyId,
      actingUserId: profile.uid,
      employees: employees.map((e) => e.employee).toList(),
    );
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  Future<void> _save(_FormReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await _equipmentService.createEquipment(
        companyId: reference.companyId,
        actingUserId: reference.actingUserId,
        name: _nameController.text.trim(),
        category: _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
        serialNumber: _serialController.text.trim().isEmpty ? null : _serialController.text.trim(),
        assignedEmployeeId: _selectedEmployeeId,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Equipment added.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
        title: const Text('Add Equipment', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                child: Text(snapshot.error?.toString() ?? 'Unable to load company data.', style: const TextStyle(color: AppTheme.mutedText)),
              );
            }

            final reference = snapshot.data!;

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Equipment Name', hintText: 'e.g. Pressure Washer 1'),
                    validator: (v) => _requiredValidator(v, 'Equipment name'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _categoryController,
                    decoration: const InputDecoration(labelText: 'Category (optional)', hintText: 'e.g. Power Tools'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(controller: _serialController, decoration: const InputDecoration(labelText: 'Serial Number (optional)')),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    value: _selectedEmployeeId,
                    decoration: const InputDecoration(labelText: 'Assigned To (optional)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                      ...reference.employees.map((e) => DropdownMenuItem<String?>(value: e.employeeId, child: Text(e.fullName))),
                    ],
                    onChanged: (value) => setState(() => _selectedEmployeeId = value),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : () => _save(reference),
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add),
                      label: Text(_isSaving ? 'Saving...' : 'Add Equipment'),
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
