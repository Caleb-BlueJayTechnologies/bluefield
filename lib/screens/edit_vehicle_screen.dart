import 'package:flutter/material.dart';

import '../Models/vehicle_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/employee_service.dart';
import '../Services/vehicle_service.dart';
import '../theme/app_theme.dart';

class EditVehicleScreen extends StatefulWidget {
  final String companyId;
  final String vehicleId;

  const EditVehicleScreen({super.key, required this.companyId, required this.vehicleId});

  @override
  State<EditVehicleScreen> createState() => _EditVehicleScreenState();
}

class _EditVehicleScreenState extends State<EditVehicleScreen> {
  final AuthService _authService = AuthService();
  final VehicleService _vehicleService = VehicleService();
  final CompanySettingsService _settingsService = CompanySettingsService();
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

  String _status = VehicleStatus.active;
  String? _selectedEmployeeId;
  bool _isSaving = false;

  late Future<_EditReferenceData> _referenceFuture;

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

  Future<_EditReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();

    final vehicle = await _vehicleService.getVehicle(companyId: widget.companyId, vehicleId: widget.vehicleId);
    if (vehicle == null) {
      throw Exception('This vehicle was not found.');
    }

    _nameController.text = vehicle.name;
    _makeController.text = vehicle.make ?? '';
    _modelController.text = vehicle.model ?? '';
    _yearController.text = vehicle.year ?? '';
    _plateController.text = vehicle.licensePlate ?? '';
    _vinController.text = vehicle.vin ?? '';
    _mileageController.text = vehicle.mileage?.toString() ?? '';
    _notesController.text = vehicle.notes ?? '';
    _status = vehicle.status;
    _selectedEmployeeId = vehicle.assignedEmployeeId;

    // includeArchived: true — otherwise editing a vehicle currently
    // assigned to an employee who's since been archived sets the
    // dropdown's value to an ID missing from its own items list, which
    // trips Flutter's DropdownButton assertion and crashes this screen.
    // The list screen already fetches this way for the same reason;
    // this form just hadn't matched it.
    final employees = await _employeeService.getEmployeesByCompany(
      companyId: widget.companyId,
      includeArchived: true,
    );
    final settings = await _settingsService.getCompanySettings(widget.companyId);

    return _EditReferenceData(
      actingUserId: profile.uid,
      employees: employees,
      requireConfirmationForDeletes: settings.requireConfirmationForDeletes,
    );
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  Future<void> _saveChanges(_EditReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await _vehicleService.updateVehicle(
        companyId: widget.companyId,
        actingUserId: reference.actingUserId,
        vehicleId: widget.vehicleId,
        name: _nameController.text.trim(),
        make: _makeController.text.trim(),
        model: _modelController.text.trim(),
        year: _yearController.text.trim(),
        licensePlate: _plateController.text.trim(),
        vin: _vinController.text.trim(),
        status: _status,
        mileage: int.tryParse(_mileageController.text.trim()),
        notes: _notesController.text.trim(),
      );

      await _vehicleService.assignVehicle(
        companyId: widget.companyId,
        actingUserId: reference.actingUserId,
        vehicleId: widget.vehicleId,
        employeeId: _selectedEmployeeId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle updated.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete(_EditReferenceData reference) async {
    final vehicleName = _nameController.text.trim();
    bool confirmed;

    if (reference.requireConfirmationForDeletes) {
      final typedController = TextEditingController();
      confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: const Text('Delete Vehicle?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This permanently deletes "$vehicleName". This cannot be undone. '
                      'Any job currently showing this vehicle will just show it as no longer available.',
                    ),
                    const SizedBox(height: 14),
                    Text('Type "$vehicleName" to confirm.', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: typedController,
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(
                    onPressed: typedController.text.trim() == vehicleName ? () => Navigator.pop(context, true) : null,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    } else {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Vehicle?'),
              content: Text(
                'This permanently deletes "$vehicleName". This cannot be undone. '
                'Any job currently showing this vehicle will just show it as no longer available.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (!confirmed) return;
    if (!mounted) return;

    try {
      await _vehicleService.deleteVehicle(companyId: widget.companyId, actingUserId: reference.actingUserId, vehicleId: widget.vehicleId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle deleted.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
        title: const Text('Edit Vehicle', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                child: Text(snapshot.error?.toString() ?? 'Unable to load this vehicle.', style: const TextStyle(color: AppTheme.mutedText)),
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
                    decoration: const InputDecoration(labelText: 'Vehicle Name'),
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
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: VehicleStatus.active, child: Text('Active')),
                      DropdownMenuItem(value: VehicleStatus.maintenance, child: Text('Maintenance')),
                      DropdownMenuItem(value: VehicleStatus.inactive, child: Text('Inactive')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _status = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    value: _selectedEmployeeId,
                    decoration: const InputDecoration(labelText: 'Assigned To'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                      ...reference.employees.map((e) => DropdownMenuItem<String?>(
                            value: e.employee.employeeId,
                            child: Text(e.employee.fullName + (e.membership.isArchived ? ' (Archived)' : '')),
                          )),
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
                      onPressed: () => _confirmDelete(reference),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Vehicle'),
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
  final List<EmployeeWithMembership> employees;
  final bool requireConfirmationForDeletes;

  const _EditReferenceData({
    required this.actingUserId,
    required this.employees,
    this.requireConfirmationForDeletes = true,
  });
}
