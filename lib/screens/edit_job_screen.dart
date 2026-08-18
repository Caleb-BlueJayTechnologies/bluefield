import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/equipment_model.dart';
import '../Models/job_model.dart';
import '../Models/vehicle_model.dart';
import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/equipment_service.dart';
import '../Services/job_service.dart';
import '../Services/vehicle_service.dart';
import '../theme/app_theme.dart';

class EditJobScreen extends StatefulWidget {
  final Map<String, dynamic> jobData;

  const EditJobScreen({super.key, required this.jobData});

  @override
  State<EditJobScreen> createState() => _EditJobScreenState();
}

class _EditJobScreenState extends State<EditJobScreen> {
  final AuthService _authService = AuthService();
  final JobService _jobService = JobService();
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();
  final VehicleService _vehicleService = VehicleService();
  final EquipmentService _equipmentService = EquipmentService();

  final _formKey = GlobalKey<FormState>();

  late final JobModel _originalJob;

  late final TextEditingController _titleController;
  late final TextEditingController _customerNameController;
  late final TextEditingController _customerPhoneController;
  late final TextEditingController _customerEmailController;
  late final TextEditingController _jobLocationController;
  final List<TextEditingController> _additionalLocationControllers = [];
  late final TextEditingController _notesController;

  late DateTime _startDate;
  late DateTime _endDate;
  late bool _isAllDay;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  late Set<String> _selectedCrewIds;
  late Set<String> _selectedVehicleIds;
  late Set<String> _selectedEquipmentIds;
  late Set<String> _selectedEmployeeIds;

  bool _isSaving = false;
  bool _isChangingStatus = false;

  late Future<_EditReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    final jobId = widget.jobData[FSFields.jobId]?.toString() ?? '';
    _originalJob = JobModel.fromMap(jobId, widget.jobData);

    _titleController = TextEditingController(text: _originalJob.title);
    _customerNameController = TextEditingController(text: _originalJob.customerName ?? '');
    _customerPhoneController = TextEditingController(text: _originalJob.customerPhone ?? '');
    _customerEmailController = TextEditingController(text: _originalJob.customerEmail ?? '');
    _jobLocationController = TextEditingController(text: _originalJob.jobLocation ?? '');
    for (final loc in _originalJob.additionalJobLocations) {
      _additionalLocationControllers.add(TextEditingController(text: loc));
    }
    _jobLocationController.addListener(() => setState(() {}));
    _notesController = TextEditingController(text: _originalJob.notes ?? '');

    _startDate = _originalJob.startDate;
    _endDate = _originalJob.endDate;
    _isAllDay = _originalJob.isAllDay;
    _startTime = _originalJob.startTime != null ? TimeOfDay.fromDateTime(_originalJob.startTime!) : null;
    _endTime = _originalJob.endTime != null ? TimeOfDay.fromDateTime(_originalJob.endTime!) : null;

    _selectedCrewIds = _originalJob.assignedCrewIds.toSet();
    _selectedEmployeeIds = _originalJob.assignedEmployeeIds.toSet();
    _selectedVehicleIds = _originalJob.assignedVehicleIds.toSet();
    _selectedEquipmentIds = _originalJob.assignedEquipmentIds.toSet();

    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _jobLocationController.dispose();
    for (final c in _additionalLocationControllers) {
      c.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }

  Future<_EditReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final crews = await _crewService.getCrewsByCompany(companyId: companyId, includeArchived: true);
    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId);
    final vehicles = await _vehicleService.getVehiclesByCompany(companyId: companyId, includeArchived: true);
    final equipment = await _equipmentService.getEquipmentByCompany(companyId: companyId, includeArchived: true);

    return _EditReferenceData(
      companyId: companyId,
      actingUserId: profile.uid,
      crews: crews,
      employees: employees.map((e) => e.employee).toList(),
      vehicles: vehicles,
      equipment: equipment,
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime ?? TimeOfDay.now());
    if (picked == null) return;
    setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime ?? TimeOfDay.now());
    if (picked == null) return;
    setState(() => _endTime = picked);
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';
  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  Future<void> _saveChanges(_EditReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      DateTime? startTime;
      DateTime? endTime;
      if (!_isAllDay) {
        if (_startTime != null) {
          startTime = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime!.hour, _startTime!.minute);
        }
        if (_endTime != null) {
          endTime = DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime!.hour, _endTime!.minute);
        }
      }

      await _jobService.updateJobDetails(
        companyId: reference.companyId,
        actingUserId: reference.actingUserId,
        jobId: _originalJob.jobId,
        title: _titleController.text.trim(),
        notes: _notesController.text.trim(),
        customerName: _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim(),
        customerEmail: _customerEmailController.text.trim(),
        jobLocation: _jobLocationController.text.trim(),
        additionalJobLocations: _additionalLocationControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList(),
        startDate: _startDate,
        endDate: _endDate,
        clearTimes: _isAllDay,
        startTime: startTime,
        endTime: endTime,
      );

      if (_selectedCrewIds.difference(_originalJob.assignedCrewIds.toSet()).isNotEmpty ||
          _originalJob.assignedCrewIds.toSet().difference(_selectedCrewIds).isNotEmpty ||
          _selectedEmployeeIds.difference(_originalJob.assignedEmployeeIds.toSet()).isNotEmpty ||
          _originalJob.assignedEmployeeIds.toSet().difference(_selectedEmployeeIds).isNotEmpty) {
        await _jobService.updateAssignments(
          companyId: reference.companyId,
          actingUserId: reference.actingUserId,
          jobId: _originalJob.jobId,
          assignedCrewIds: _selectedCrewIds.toList(),
          directEmployeeIds: _selectedEmployeeIds.toList(),
        );
      }

      if (_selectedVehicleIds.difference(_originalJob.assignedVehicleIds.toSet()).isNotEmpty ||
          _originalJob.assignedVehicleIds.toSet().difference(_selectedVehicleIds).isNotEmpty) {
        await _jobService.assignVehicles(
          companyId: reference.companyId,
          actingUserId: reference.actingUserId,
          jobId: _originalJob.jobId,
          vehicleIds: _selectedVehicleIds.toList(),
        );
      }

      if (_selectedEquipmentIds.difference(_originalJob.assignedEquipmentIds.toSet()).isNotEmpty ||
          _originalJob.assignedEquipmentIds.toSet().difference(_selectedEquipmentIds).isNotEmpty) {
        await _jobService.assignEquipment(
          companyId: reference.companyId,
          actingUserId: reference.actingUserId,
          jobId: _originalJob.jobId,
          equipmentIds: _selectedEquipmentIds.toList(),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job updated successfully.')));
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancelJob(_EditReferenceData reference) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel Job?'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(labelText: 'Cancellation reason', hintText: 'Required'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel Job'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || reasonController.text.trim().isEmpty) return;

    setState(() => _isChangingStatus = true);
    try {
      await _jobService.cancelJob(
        companyId: reference.companyId,
        actingUserId: reference.actingUserId,
        jobId: _originalJob.jobId,
        reason: reasonController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job cancelled.')));
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isChangingStatus = false);
    }
  }

  Future<void> _completeJob(_EditReferenceData reference) async {
    if (_jobService.requiresMultiDayCompletionWarning(_originalJob)) {
      final end = _originalJob.endDate;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Complete Multi-Day Job?'),
            content: Text(
              'This job is scheduled through ${end.month}/${end.day}/${end.year}. '
              'Completing it now will close the job and remove it from all remaining scheduled days.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Complete Job')),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }

    setState(() => _isChangingStatus = true);
    try {
      await _jobService.completeJob(companyId: reference.companyId, actingUserId: reference.actingUserId, jobId: _originalJob.jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job marked complete.')));
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isChangingStatus = false);
    }
  }

  Future<void> _reopenJob(_EditReferenceData reference) async {
    setState(() => _isChangingStatus = true);
    try {
      await _jobService.reopenJob(companyId: reference.companyId, actingUserId: reference.actingUserId, jobId: _originalJob.jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job reopened.')));
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isChangingStatus = false);
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
        title: const Text('Edit Job', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                    snapshot.error?.toString() ?? 'Unable to load company data.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                ),
              );
            }

            final reference = snapshot.data!;
            final isTerminal = _originalJob.isTerminal;

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                children: [
                  if (isTerminal)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                      child: Text(
                        'This job is ${_originalJob.status}. Reopen it to make further changes.',
                        style: const TextStyle(color: AppTheme.mutedText),
                      ),
                    ),
                  _section('Job Information', [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _titleController,
                        enabled: !isTerminal,
                        decoration: const InputDecoration(labelText: 'Job Title'),
                        validator: (v) => _requiredValidator(v, 'Job title'),
                      ),
                    ),
                    TextFormField(
                      controller: _jobLocationController,
                      enabled: !isTerminal,
                      decoration: const InputDecoration(labelText: 'Job Location (optional)'),
                    ),
                    if (_jobLocationController.text.trim().isNotEmpty) ...[
                      for (var i = 0; i < _additionalLocationControllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _additionalLocationControllers[i],
                                  enabled: !isTerminal,
                                  decoration: InputDecoration(
                                    labelText: i == 0 ? 'Additional Location (optional)' : 'Location ${i + 2} (optional)',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove this location',
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: isTerminal
                                    ? null
                                    : () {
                                        setState(() {
                                          _additionalLocationControllers[i].dispose();
                                          _additionalLocationControllers.removeAt(i);
                                        });
                                      },
                              ),
                            ],
                          ),
                        ),
                      if (!isTerminal && _additionalLocationControllers.length < JobModel.maxAdditionalLocations)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _additionalLocationControllers.add(TextEditingController()));
                            },
                            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                            label: Text(_additionalLocationControllers.isEmpty ? 'Add Another Location' : 'Add One More Location'),
                          ),
                        ),
                    ],
                  ]),
                  _section('Customer (optional)', [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _customerNameController,
                        enabled: !isTerminal,
                        decoration: const InputDecoration(labelText: 'Customer Name'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _customerPhoneController,
                        enabled: !isTerminal,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Customer Phone'),
                      ),
                    ),
                    TextFormField(
                      controller: _customerEmailController,
                      enabled: !isTerminal,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Customer Email'),
                    ),
                  ]),
                  _section('Schedule', [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('All Day'),
                      value: _isAllDay,
                      onChanged: isTerminal ? null : (v) => setState(() => _isAllDay = v),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isTerminal ? null : _pickStartDate,
                            child: Text('Start: ${_formatDate(_startDate)}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isTerminal ? null : _pickEndDate,
                            child: Text('End: ${_formatDate(_endDate)}'),
                          ),
                        ),
                      ],
                    ),
                    if (!_isAllDay) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isTerminal ? null : _pickStartTime,
                              child: Text(_startTime == null ? 'Start Time' : _formatTime(_startTime!)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isTerminal ? null : _pickEndTime,
                              child: Text(_endTime == null ? 'End Time' : _formatTime(_endTime!)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ]),
                  _section(
                    'Assign Crews',
                    reference.crews
                        .map((crew) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(crew.crewName),
                              value: _selectedCrewIds.contains(crew.crewId),
                              onChanged: isTerminal
                                  ? null
                                  : (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _selectedCrewIds.add(crew.crewId);
                                        } else {
                                          _selectedCrewIds.remove(crew.crewId);
                                        }
                                      });
                                    },
                            ))
                        .toList(),
                  ),
                  _section(
                    'Assign Individual Employees',
                    reference.employees
                        .map((employee) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(employee.fullName),
                              value: _selectedEmployeeIds.contains(employee.employeeId),
                              onChanged: isTerminal
                                  ? null
                                  : (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _selectedEmployeeIds.add(employee.employeeId);
                                        } else {
                                          _selectedEmployeeIds.remove(employee.employeeId);
                                        }
                                      });
                                    },
                            ))
                        .toList(),
                  ),
                  _section('Vehicle & Equipment', [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Vehicles', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (reference.vehicles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No vehicles added yet.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ...reference.vehicles.map((v) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(v.name),
                            subtitle: v.displaySpec.isNotEmpty ? Text(v.displaySpec) : null,
                            value: _selectedVehicleIds.contains(v.vehicleId),
                            onChanged: isTerminal
                                ? null
                                : (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedVehicleIds.add(v.vehicleId);
                                      } else {
                                        _selectedVehicleIds.remove(v.vehicleId);
                                      }
                                    });
                                  },
                          )),
                    if (reference.equipment.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Equipment', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      ...reference.equipment.map((item) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.name),
                            subtitle: item.category != null ? Text(item.category!) : null,
                            value: _selectedEquipmentIds.contains(item.equipmentId),
                            onChanged: isTerminal
                                ? null
                                : (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedEquipmentIds.add(item.equipmentId);
                                      } else {
                                        _selectedEquipmentIds.remove(item.equipmentId);
                                      }
                                    });
                                  },
                          )),
                    ],
                  ]),
                  _section('Notes', [
                    TextFormField(
                      controller: _notesController,
                      enabled: !isTerminal,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    ),
                  ]),
                  if (!isTerminal) ...[
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
                        onPressed: _isChangingStatus ? null : () => _completeJob(reference),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark Complete'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _isChangingStatus ? null : () => _cancelJob(reference),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel Job'),
                      ),
                    ),
                  ] else
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _isChangingStatus ? null : () => _reopenJob(reference),
                        icon: const Icon(Icons.replay_outlined),
                        label: const Text('Reopen Job'),
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
  final String companyId;
  final String actingUserId;
  final List<CrewModel> crews;
  final List<EmployeeModel> employees;
  final List<VehicleModel> vehicles;
  final List<EquipmentModel> equipment;

  const _EditReferenceData({
    required this.companyId,
    required this.actingUserId,
    required this.crews,
    required this.employees,
    this.vehicles = const [],
    this.equipment = const [],
  });
}
