import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/membership.dart';
import '../Services/company_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../theme/app_theme.dart';

class EditEmployeeScreen extends StatefulWidget {
  final String companyId;
  final String employeeId;
  final Map<String, dynamic> employeeData;

  const EditEmployeeScreen({
    super.key,
    required this.companyId,
    required this.employeeId,
    required this.employeeData,
  });

  @override
  State<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  final EmployeeService _employeeService = EmployeeService();
  final CrewService _crewService = CrewService();
  final CompanyService _companyService = CompanyService();

  final _formKey = GlobalKey<FormState>();

  late final EmployeeModel _originalEmployee;

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _employeeNumberController;

  String _selectedEmploymentType = EmploymentType.fullTime;
  final Set<String> _selectedCrewIds = {};
  String _selectedRole = FSRoles.employee;

  bool _isSaving = false;

  late Future<_EditReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _originalEmployee = EmployeeModel.fromMap(widget.employeeId, widget.employeeData);

    _firstNameController = TextEditingController(text: _originalEmployee.firstName);
    _lastNameController = TextEditingController(text: _originalEmployee.lastName);
    _phoneController = TextEditingController(text: _originalEmployee.phone ?? '');
    _jobTitleController = TextEditingController(text: _originalEmployee.jobTitle ?? '');
    _employeeNumberController = TextEditingController(text: _originalEmployee.employeeNumber ?? '');
    _selectedEmploymentType = _originalEmployee.employmentType;
    _selectedCrewIds.addAll(_originalEmployee.crewIds);

    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _jobTitleController.dispose();
    _employeeNumberController.dispose();
    super.dispose();
  }

  Future<MembershipModel?> _fetchMembership(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection(FSCollections.companies)
        .doc(widget.companyId)
        .collection(FSCompanySub.memberships)
        .doc(userId)
        .get();
    if (!doc.exists) return null;
    return MembershipModel.fromSnapshot(doc);
  }

  Future<_EditReferenceData> _loadReferenceData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user is currently signed in.');

    final crews = await _crewService.getCrewsByCompany(companyId: widget.companyId);

    final actingMembership = await _fetchMembership(user.uid);
    final targetMembership = await _fetchMembership(widget.employeeId);

    _selectedRole = targetMembership?.role ?? FSRoles.employee;

    return _EditReferenceData(
      actingUserId: user.uid,
      actingRole: actingMembership?.role ?? FSRoles.employee,
      crews: crews,
    );
  }

  Future<void> _saveChanges(_EditReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;
    final actingUserId = reference.actingUserId;

    setState(() => _isSaving = true);

    try {
      await _employeeService.updateEmployeeProfile(
        companyId: widget.companyId,
        actingUserId: actingUserId,
        employeeId: widget.employeeId,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        jobTitle: _jobTitleController.text.trim(),
        employmentType: _selectedEmploymentType,
        employeeNumber: _employeeNumberController.text.trim(),
      );

      final originalCrewIds = _originalEmployee.crewIds.toSet();
      final addedCrews = _selectedCrewIds.difference(originalCrewIds);
      final removedCrews = originalCrewIds.difference(_selectedCrewIds);

      for (final crewId in addedCrews) {
        await _employeeService.addToCrew(
          companyId: widget.companyId,
          actingUserId: actingUserId,
          employeeId: widget.employeeId,
          crewId: crewId,
        );
      }
      for (final crewId in removedCrews) {
        await _employeeService.removeFromCrew(
          companyId: widget.companyId,
          actingUserId: actingUserId,
          employeeId: widget.employeeId,
          crewId: crewId,
        );
      }

      if (_selectedRole != reference.actingRole && _selectedRole.isNotEmpty) {
        // changeMemberRole itself re-validates permission and the
        // last-owner safeguard — this screen doesn't need to duplicate
        // that logic, just call it and surface any error.
        try {
          await _companyService.changeMemberRole(
            companyId: widget.companyId,
            actingUserId: actingUserId,
            targetUserId: widget.employeeId,
            newRole: _selectedRole,
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile saved, but role change failed. Check permissions.')),
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee updated successfully.')));
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
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
        title: const Text('Edit Employee', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                    snapshot.error?.toString() ?? 'Unable to load employee data.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                ),
              );
            }

            final reference = snapshot.data!;
            final canChangeRole =
                PermissionService.roleHasPermission(reference.actingRole, Permission.employeesChangeRole);

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                children: [
                  _section('Employee Information', [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _firstNameController,
                        decoration: const InputDecoration(labelText: 'First Name'),
                        validator: (v) => _requiredValidator(v, 'First name'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _lastNameController,
                        decoration: const InputDecoration(labelText: 'Last Name'),
                        validator: (v) => _requiredValidator(v, 'Last name'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone Number'),
                      ),
                    ),
                  ]),
                  _section('Work Details', [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: [
                          const DropdownMenuItem(value: FSRoles.employee, child: Text('Employee')),
                          const DropdownMenuItem(value: FSRoles.manager, child: Text('Manager')),
                          if (reference.actingRole == FSRoles.owner)
                            const DropdownMenuItem(value: FSRoles.owner, child: Text('Owner')),
                        ],
                        onChanged: canChangeRole ? (value) => setState(() => _selectedRole = value ?? _selectedRole) : null,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _jobTitleController,
                        decoration: const InputDecoration(labelText: 'Job Title (optional)'),
                      ),
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Crews', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (reference.crews.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No crews created yet.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ...reference.crews.map(
                        (c) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.crewName),
                          value: _selectedCrewIds.contains(c.crewId),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedCrewIds.add(c.crewId);
                              } else {
                                _selectedCrewIds.remove(c.crewId);
                              }
                            });
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        value: _selectedEmploymentType,
                        decoration: const InputDecoration(labelText: 'Employment Type'),
                        items: const [
                          DropdownMenuItem(value: EmploymentType.fullTime, child: Text('Full-time')),
                          DropdownMenuItem(value: EmploymentType.partTime, child: Text('Part-time')),
                          DropdownMenuItem(value: EmploymentType.seasonal, child: Text('Seasonal')),
                          DropdownMenuItem(value: EmploymentType.contractor, child: Text('Contractor')),
                        ],
                        onChanged: (value) => setState(() => _selectedEmploymentType = value ?? _selectedEmploymentType),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: _employeeNumberController,
                        decoration: const InputDecoration(labelText: 'Employee Number (optional)'),
                      ),
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
  final String actingRole;
  final List<CrewModel> crews;

  const _EditReferenceData({required this.actingUserId, required this.actingRole, required this.crews});
}
