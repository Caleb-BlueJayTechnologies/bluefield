import 'package:flutter/material.dart';

import '../Models/equipment_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/employee_service.dart';
import '../Services/equipment_service.dart';
import '../theme/app_theme.dart';

class EditEquipmentScreen extends StatefulWidget {
  final String companyId;
  final String equipmentId;

  const EditEquipmentScreen({super.key, required this.companyId, required this.equipmentId});

  @override
  State<EditEquipmentScreen> createState() => _EditEquipmentScreenState();
}

class _EditEquipmentScreenState extends State<EditEquipmentScreen> {
  final AuthService _authService = AuthService();
  final EquipmentService _equipmentService = EquipmentService();
  final CompanySettingsService _settingsService = CompanySettingsService();
  final EmployeeService _employeeService = EmployeeService();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _serialController = TextEditingController();
  final _notesController = TextEditingController();

  String _status = EquipmentStatus.active;
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
    _categoryController.dispose();
    _serialController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<_EditReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();

    final equipment = await _equipmentService.getEquipment(companyId: widget.companyId, equipmentId: widget.equipmentId);
    if (equipment == null) {
      throw Exception('This equipment was not found.');
    }

    _nameController.text = equipment.name;
    _categoryController.text = equipment.category ?? '';
    _serialController.text = equipment.serialNumber ?? '';
    _notesController.text = equipment.notes ?? '';
    _status = equipment.status;
    _selectedEmployeeId = equipment.assignedEmployeeId;

    // includeArchived: true — otherwise editing a piece of equipment
    // currently assigned to an employee who's since been archived sets
    // the dropdown's value to an ID missing from its own items list,
    // which trips Flutter's DropdownButton assertion and crashes this
    // screen. The list screen already fetches this way for the same
    // reason; this form just hadn't matched it.
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
      await _equipmentService.updateEquipment(
        companyId: widget.companyId,
        actingUserId: reference.actingUserId,
        equipmentId: widget.equipmentId,
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        serialNumber: _serialController.text.trim(),
        status: _status,
        notes: _notesController.text.trim(),
      );

      await _equipmentService.assignEquipment(
        companyId: widget.companyId,
        actingUserId: reference.actingUserId,
        equipmentId: widget.equipmentId,
        employeeId: _selectedEmployeeId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Equipment updated.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete(_EditReferenceData reference) async {
    final equipmentName = _nameController.text.trim();
    bool confirmed;

    if (reference.requireConfirmationForDeletes) {
      final typedController = TextEditingController();
      confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: const Text('Delete Equipment?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This permanently deletes "$equipmentName". This cannot be undone. '
                      'Any job currently showing this item will just show it as no longer available.',
                    ),
                    const SizedBox(height: 14),
                    Text('Type "$equipmentName" to confirm.', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    onPressed: typedController.text.trim() == equipmentName ? () => Navigator.pop(context, true) : null,
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
              title: const Text('Delete Equipment?'),
              content: Text(
                'This permanently deletes "$equipmentName". This cannot be undone. '
                'Any job currently showing this item will just show it as no longer available.',
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
      await _equipmentService.deleteEquipment(companyId: widget.companyId, actingUserId: reference.actingUserId, equipmentId: widget.equipmentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Equipment deleted.')));
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
        title: const Text('Edit Equipment', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                child: Text(snapshot.error?.toString() ?? 'Unable to load this equipment.', style: const TextStyle(color: AppTheme.mutedText)),
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
                    decoration: const InputDecoration(labelText: 'Equipment Name'),
                    validator: (v) => _requiredValidator(v, 'Equipment name'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(controller: _categoryController, decoration: const InputDecoration(labelText: 'Category (optional)')),
                  const SizedBox(height: 14),
                  TextFormField(controller: _serialController, decoration: const InputDecoration(labelText: 'Serial Number (optional)')),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: EquipmentStatus.active, child: Text('Active')),
                      DropdownMenuItem(value: EquipmentStatus.maintenance, child: Text('Maintenance')),
                      DropdownMenuItem(value: EquipmentStatus.inactive, child: Text('Inactive')),
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
                      label: const Text('Delete Equipment'),
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
