import 'package:flutter/material.dart';

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

class CreateJobScreen extends StatefulWidget {
  const CreateJobScreen({super.key});

  @override
  State<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends State<CreateJobScreen> {
  final AuthService _authService = AuthService();
  final JobService _jobService = JobService();
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();
  final VehicleService _vehicleService = VehicleService();
  final EquipmentService _equipmentService = EquipmentService();

  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _jobLocationController = TextEditingController();
  final List<TextEditingController> _additionalLocationControllers = [];
  final _notesController = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _isAllDay = true;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  final Set<String> _selectedCrewIds = {};
  final Set<String> _selectedEmployeeIds = {};
  final Set<String> _selectedVehicleIds = {};
  final Set<String> _selectedEquipmentIds = {};

  bool _isSaving = false;
  bool _createAnywayArmed = false;
  List<String> _pendingWarnings = [];

  late Future<_FormReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
    // Triggers a rebuild so the second-address field can appear/
    // disappear as the first one is filled in or cleared, rather than
    // always showing (clutter for single-address jobs) or requiring a
    // separate explicit toggle.
    _jobLocationController.addListener(() => setState(() {}));
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

  Future<_FormReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final crews = await _crewService.getCrewsByCompany(companyId: companyId);
    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId);
    final vehicles = await _vehicleService.getVehiclesByCompany(companyId: companyId);
    final equipment = await _equipmentService.getEquipmentByCompany(companyId: companyId);

    return _FormReferenceData(
      companyId: companyId,
      actingUserId: profile.uid,
      crews: crews,
      employees: employees.map((e) => e.employee).toList(),
      vehicles: vehicles,
      equipment: equipment,
    );
  }

  void _resetWarning() {
    if (_createAnywayArmed) {
      setState(() {
        _createAnywayArmed = false;
        _pendingWarnings = [];
      });
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
    _resetWarning();
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
    _resetWarning();
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime ?? TimeOfDay.now());
    if (picked == null) return;
    setState(() => _startTime = picked);
    _resetWarning();
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime ?? TimeOfDay.now());
    if (picked == null) return;
    setState(() => _endTime = picked);
    _resetWarning();
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';
  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  /// Same-day-or-overlapping-range conflict check against other active
  /// jobs sharing a selected crew or employee — day-level, since jobs
  /// (unlike schedule entries) don't always carry precise times.
  Future<List<String>> _checkConflicts(_FormReferenceData reference) async {
    if (_selectedCrewIds.isEmpty && _selectedEmployeeIds.isEmpty) return [];

    final activeJobs = await _jobService.queryJobs(
      companyId: reference.companyId,
      statuses: const ['scheduled', 'inProgress'],
    );

    final warnings = <String>[];
    for (final job in activeJobs) {
      final overlapsDate = !_endDate.isBefore(job.startDate) && !job.endDate.isBefore(_startDate);
      if (!overlapsDate) continue;

      final sharedCrews = job.assignedCrewIds.toSet().intersection(_selectedCrewIds);
      final sharedEmployees = job.assignedEmployeeIds.toSet().intersection(_selectedEmployeeIds);

      if (sharedCrews.isNotEmpty) {
        final names = sharedCrews.map((id) => reference.crews.firstWhere((c) => c.crewId == id).crewName).join(', ');
        warnings.add('$names already scheduled for "${job.title}" during this date range.');
      }
      if (sharedEmployees.isNotEmpty) {
        final names = sharedEmployees
            .map((id) => reference.employees.firstWhere((e) => e.employeeId == id).fullName)
            .join(', ');
        warnings.add('$names already scheduled for "${job.title}" during this date range.');
      }
    }
    return warnings;
  }

  Future<void> _createJob(_FormReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    if (!_createAnywayArmed) {
      final warnings = await _checkConflicts(reference);
      if (warnings.isNotEmpty) {
        setState(() {
          _pendingWarnings = warnings;
          _createAnywayArmed = true;
        });
        return;
      }
    }

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

      await _jobService.createJob(
        companyId: reference.companyId,
        actingUserId: reference.actingUserId,
        title: _titleController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        customerName: _customerNameController.text.trim().isEmpty ? null : _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim().isEmpty ? null : _customerPhoneController.text.trim(),
        customerEmail: _customerEmailController.text.trim().isEmpty ? null : _customerEmailController.text.trim(),
        jobLocation: _jobLocationController.text.trim().isEmpty ? null : _jobLocationController.text.trim(),
        additionalJobLocations: _additionalLocationControllers
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
        startDate: _startDate,
        endDate: _endDate,
        startTime: startTime,
        endTime: endTime,
        assignedCrewIds: _selectedCrewIds.toList(),
        directEmployeeIds: _selectedEmployeeIds.toList(),
        assignedVehicleIds: _selectedVehicleIds.toList(),
        assignedEquipmentIds: _selectedEquipmentIds.toList(),
        status: 'scheduled',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job created successfully.')));
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
        title: const Text('Create Job', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                  _section('Job Information', [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(labelText: 'Job Title'),
                        validator: (v) => _requiredValidator(v, 'Job title'),
                        onChanged: (_) => _resetWarning(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _jobLocationController,
                        decoration: const InputDecoration(labelText: 'Job Location (optional)'),
                      ),
                    ),
                    if (_jobLocationController.text.trim().isNotEmpty) ...[
                      for (var i = 0; i < _additionalLocationControllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _additionalLocationControllers[i],
                                  decoration: InputDecoration(
                                    labelText: i == 0 ? 'Additional Location (optional)' : 'Location ${i + 2} (optional)',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove this location',
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    _additionalLocationControllers[i].dispose();
                                    _additionalLocationControllers.removeAt(i);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      if (_additionalLocationControllers.length < JobModel.maxAdditionalLocations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
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
                        decoration: const InputDecoration(labelText: 'Customer Name'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _customerPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Customer Phone'),
                      ),
                    ),
                    TextFormField(
                      controller: _customerEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Customer Email'),
                    ),
                  ]),
                  _section('Schedule', [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('All Day'),
                      value: _isAllDay,
                      onChanged: (v) {
                        setState(() => _isAllDay = v);
                        _resetWarning();
                      },
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _pickStartDate,
                            child: Text('Start: ${_formatDate(_startDate)}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _pickEndDate,
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
                              onPressed: _pickStartTime,
                              child: Text(_startTime == null ? 'Start Time' : _formatTime(_startTime!)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickEndTime,
                              child: Text(_endTime == null ? 'End Time' : _formatTime(_endTime!)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_endDate.isAfter(_startDate)) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'This is a multi-day job — it will be stored as one job record spanning the full date range.',
                        style: TextStyle(color: AppTheme.mutedText, fontSize: 12),
                      ),
                    ],
                  ]),
                  _section(
                    'Assign Crews',
                    reference.crews.isEmpty
                        ? [const Text('No crews yet.', style: TextStyle(color: AppTheme.mutedText))]
                        : reference.crews
                            .map((crew) => CheckboxListTile(
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
                                    _resetWarning();
                                  },
                                ))
                            .toList(),
                  ),
                  _section(
                    'Assign Individual Employees',
                    [
                      const Text(
                        'Employees already covered by a selected crew are handled automatically — no need to also check them here.',
                        style: TextStyle(color: AppTheme.mutedText, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
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
                              _resetWarning();
                            },
                          )),
                    ],
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
                            onChanged: (checked) {
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
                            onChanged: (checked) {
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
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    ),
                  ]),
                  if (_createAnywayArmed && _pendingWarnings.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Scheduling Conflicts', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          ...(_pendingWarnings.map((w) => Text('• $w', style: const TextStyle(color: Colors.orange)))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : () => _createJob(reference),
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_createAnywayArmed ? Icons.warning_amber_outlined : Icons.add_location_alt_outlined),
                      label: Text(_isSaving ? 'Saving...' : (_createAnywayArmed ? 'Create Anyway' : 'Create Job')),
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
  final List<VehicleModel> vehicles;
  final List<EquipmentModel> equipment;

  const _FormReferenceData({
    required this.companyId,
    required this.actingUserId,
    required this.crews,
    required this.employees,
    this.vehicles = const [],
    this.equipment = const [],
  });
}
