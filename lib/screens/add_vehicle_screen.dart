import 'package:flutter/material.dart';

import '../Models/employee_model.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/vehicle_service.dart';
import '../theme/app_theme.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final AuthService _authService = AuthService();
  final VehicleService _vehicleService = VehicleService();
  final EmployeeService _employeeService = EmployeeService();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _plateController = TextEditingController();
  final _vinController = TextEditingController();
  final _mileageController = TextEditingController();
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
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _plateController.dispose();
    _vinController.dispose();
    _mileageController.dispose();
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
      await _vehicleService.createVehicle(
        companyId: reference.companyId,
        actingUserId: reference.actingUserId,
        name: _nameController.text.trim(),
        make: _makeController.text.trim().isEmpty ? null : _makeController.text.trim(),
        model: _modelController.text.trim().isEmpty ? null : _modelController.text.trim(),
        year: _yearController.text.trim().isEmpty ? null : _yearController.text.trim(),
        licensePlate: _plateController.text.trim().isEmpty ? null : _plateController.text.trim(),
        vin: _vinController.text.trim().isEmpty ? null : _vinController.text.trim(),
        assignedEmployeeId: _selectedEmployeeId,
        mileage: int.tryParse(_mileageController.text.trim()),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle added.')));
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
        title: const Text('Add Vehicle', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Vehicle Name', hintText: 'e.g. Truck 1'),
                    validator: (v) => _requiredValidator(v, 'Vehicle name'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: _yearController, decoration: const InputDecoration(labelText: 'Year'))),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(controller: _makeController, decoration: const InputDecoration(labelText: 'Make'))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(controller: _modelController, decoration: const InputDecoration(labelText: 'Model')),
                  const SizedBox(height: 14),
                  TextFormField(controller: _plateController, decoration: const InputDecoration(labelText: 'License Plate')),
                  const SizedBox(height: 14),
                  TextFormField(controller: _vinController, decoration: const InputDecoration(labelText: 'VIN (optional)')),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _mileageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Mileage (optional)'),
                  ),
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
                      label: Text(_isSaving ? 'Saving...' : 'Add Vehicle'),
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
