import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/app_user.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/membership.dart';
import '../Services/crew_service.dart';
import '../theme/app_theme.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key});

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final CrewService _crewService = CrewService();
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _employeeNumberController = TextEditingController();

  bool _isSaving = false;
  String _selectedRole = FSRoles.employee;
  String _selectedEmploymentType = EmploymentType.fullTime;
  final Set<String> _selectedCrewIds = {};

  late Future<_FormReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _jobTitleController.dispose();
    _employeeNumberController.dispose();
    super.dispose();
  }

  Future<_FormReferenceData> _loadReferenceData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user is currently signed in.');

    final userDoc = await FirebaseFirestore.instance.collection(FSCollections.users).doc(user.uid).get();
    final companyId = userDoc.data()?['activeCompanyId']?.toString() ?? '';
    if (companyId.isEmpty) throw Exception('User is not linked to a company.');

    final membershipDoc = await FirebaseFirestore.instance
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships)
        .doc(user.uid)
        .get();
    final isOwner = membershipDoc.data()?[FSFields.role] == FSRoles.owner;

    final crews = await _crewService.getCrewsByCompany(companyId: companyId);

    return _FormReferenceData(companyId: companyId, actingUserId: user.uid, isOwner: isOwner, crews: crews);
  }

  String _generateTemporaryPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Creates the Auth account via a secondary, throwaway Firebase App
  /// instance so the admin performing this action stays signed in —
  /// createUserWithEmailAndPassword on the default app would otherwise
  /// sign the admin OUT and into the new employee's account.
  Future<UserCredential> _createEmployeeAuthAccount({
    required String email,
    required String temporaryPassword,
    required String displayName,
  }) async {
    final primaryApp = Firebase.app();
    final secondaryAppName = 'employee_creation_${DateTime.now().microsecondsSinceEpoch}';
    final secondaryApp = await Firebase.initializeApp(name: secondaryAppName, options: primaryApp.options);

    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: temporaryPassword,
      );

      final createdUser = credential.user;
      if (createdUser == null) {
        throw Exception('Employee login account was not created.');
      }

      await createdUser.updateDisplayName(displayName);
      await secondaryAuth.signOut();

      return credential;
    } finally {
      await secondaryApp.delete();
    }
  }

  Future<void> _saveEmployee(_FormReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    String? temporaryPassword;
    String email = _emailController.text.trim().toLowerCase();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final fullName = '$firstName $lastName'.trim();

    try {
      temporaryPassword = _generateTemporaryPassword();

      final credential = await _createEmployeeAuthAccount(
        email: email,
        temporaryPassword: temporaryPassword,
        displayName: fullName,
      );

      final newUserId = credential.user?.uid;
      if (newUserId == null) {
        throw Exception('Employee login account was not created.');
      }

      // employeeId MUST equal the Auth UID under our design — the
      // employee doc, membership doc, and user doc all share this same
      // ID rather than each generating their own random one.
      final batch = FirebaseFirestore.instance.batch();

      final userRef = FirebaseFirestore.instance.collection(FSCollections.users).doc(newUserId);
      final membershipRef = FirebaseFirestore.instance
          .collection(FSCollections.companies)
          .doc(reference.companyId)
          .collection(FSCompanySub.memberships)
          .doc(newUserId);
      final employeeRef = FirebaseFirestore.instance
          .collection(FSCollections.companies)
          .doc(reference.companyId)
          .collection(FSCompanySub.employees)
          .doc(newUserId);

      batch.set(
          userRef,
          AppUser.toMapForCreate(
            email: email,
            firstName: firstName,
            lastName: lastName,
            activeCompanyId: reference.companyId,
            requiresPasswordChange: true,
          ));

      batch.set(
          membershipRef,
          MembershipModel.toMapForCreate(
            userId: newUserId,
            companyId: reference.companyId,
            role: _selectedRole,
            invitedBy: reference.actingUserId,
          ));

      batch.set(
          employeeRef,
          EmployeeModel.toMapForCreate(
            companyId: reference.companyId,
            firstName: firstName,
            lastName: lastName,
            jobTitle: _jobTitleController.text.trim().isEmpty ? null : _jobTitleController.text.trim(),
            crewIds: _selectedCrewIds.toList(),
            phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
            loginEmail: email,
            employmentType: _selectedEmploymentType,
            employeeNumber:
                _employeeNumberController.text.trim().isEmpty ? null : _employeeNumberController.text.trim(),
          ));

      await batch.commit();

      if (!mounted) return;

      await _showTemporaryPasswordDialog(email: email, temporaryPassword: temporaryPassword);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showTemporaryPasswordDialog({required String email, required String temporaryPassword}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(_selectedRole == FSRoles.manager ? 'Manager Login Created' : 'Employee Login Created'),
          content: SelectableText(
            'Give this temporary login to the ${_selectedRole == FSRoles.manager ? 'manager' : 'employee'}:\n\n'
            'Email: $email\n'
            'Temporary Password: $temporaryPassword\n\n'
            'They will be required to change their password the first time they sign in.',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        );
      },
    );
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('email-already-in-use')) return 'An account already exists with that email.';
    if (message.contains('invalid-email')) return 'Enter a valid email address.';
    if (message.contains('weak-password')) return 'The temporary password was rejected. Try again.';
    if (message.contains('operation-not-allowed')) {
      return 'Email/password accounts are not enabled in Firebase Authentication.';
    }
    if (message.contains('permission-denied')) {
      return 'Firebase blocked the database write. Firestore rules need to allow employee creation.';
    }
    if (message.contains('No Firebase App')) return 'Firebase app setup failed while creating the login account.';
    return message.replaceFirst('Exception: ', '');
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  String? _emailValidator(String? value) {
    // Login email is always required — every employee record is
    // created together with a Firebase Auth account under this app's
    // design, so there's no "record only, no login" path (Section 2's
    // open question about this is resolved here: yes, always required).
    if (value == null || value.trim().isEmpty) return 'Login email is required';
    if (!value.contains('@') || !value.contains('.')) return 'Enter a valid email';
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
        title: const Text('Add Employee', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(labelText: 'First Name'),
                          validator: (v) => _requiredValidator(v, 'First name'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(labelText: 'Last Name'),
                          validator: (v) => _requiredValidator(v, 'Last name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Login Email'),
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      const DropdownMenuItem(value: FSRoles.employee, child: Text('Employee')),
                      const DropdownMenuItem(value: FSRoles.manager, child: Text('Manager')),
                      if (reference.isOwner) const DropdownMenuItem(value: FSRoles.owner, child: Text('Owner')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedRole = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _jobTitleController,
                    decoration: const InputDecoration(labelText: 'Job Title (optional)', hintText: 'e.g. Crew Lead'),
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _selectedEmploymentType,
                    decoration: const InputDecoration(labelText: 'Employment Type'),
                    items: const [
                      DropdownMenuItem(value: EmploymentType.fullTime, child: Text('Full-time')),
                      DropdownMenuItem(value: EmploymentType.partTime, child: Text('Part-time')),
                      DropdownMenuItem(value: EmploymentType.seasonal, child: Text('Seasonal')),
                      DropdownMenuItem(value: EmploymentType.contractor, child: Text('Contractor')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedEmploymentType = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _employeeNumberController,
                    decoration: const InputDecoration(labelText: 'Employee Number (optional)'),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : () => _saveEmployee(reference),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(_isSaving ? 'Creating...' : 'Create Employee'),
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
  final bool isOwner;
  final List<CrewModel> crews;

  const _FormReferenceData({
    required this.companyId,
    required this.actingUserId,
    required this.isOwner,
    required this.crews,
  });
}
