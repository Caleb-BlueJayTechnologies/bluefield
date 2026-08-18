import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/employee_model.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/time_entry_service.dart';
import '../theme/app_theme.dart';
import 'demo_constants.dart';
import 'demo_data_seeder.dart';
import 'view_as_session.dart';

/// Lets the GenericMoversDemo@gmail.com Owner pick one of the seeded
/// employees (demo_data_seeder.dart minted a real Firebase Auth account
/// for each one) and sign the app into it, so they can show a prospect
/// exactly what an employee or manager sees — every real screen,
/// permission, and interaction, not a read-only mockup.
///
/// Only ever reachable when signed in as the demo account (see
/// employer_dashboard_screen.dart) — re-checked here too, same
/// belt-and-suspenders pattern as demo_data_seed_screen.dart.
class ViewAsScreen extends StatefulWidget {
  const ViewAsScreen({super.key});

  @override
  State<ViewAsScreen> createState() => _ViewAsScreenState();
}

class _ViewAsScreenState extends State<ViewAsScreen> {
  final EmployeeService _employeeService = EmployeeService();
  final TimeEntryService _timeEntryService = TimeEntryService();

  bool _loading = true;
  bool _switching = false;
  String? _error;
  List<EmployeeWithMembership> _people = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
      if (email != DemoDataSeeder.allowedEmail) {
        throw Exception('View As is only available for the demo account.');
      }
      final companyId = await _timeEntryService.getCurrentCompanyId();
      final people = await _employeeService.getEmployeesByCompany(companyId: companyId);
      people.sort((a, b) {
        final roleCompare = a.role == b.role ? 0 : (a.role == FSRoles.manager ? -1 : 1);
        if (roleCompare != 0) return roleCompare;
        return a.employee.firstName.compareTo(b.employee.firstName);
      });
      if (!mounted) return;
      setState(() {
        // Owner's own record has no demo login — only seeded employees
        // and managers ever get a "View as" entry.
        _people = people.where((p) => p.role != FSRoles.owner).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _viewAs(EmployeeWithMembership person) async {
    final owner = FirebaseAuth.instance.currentUser;
    if (owner == null || owner.email == null) return;

    final password = await _promptForOwnerPassword(person);
    if (password == null || password.isEmpty) return;

    setState(() => _switching = true);
    try {
      ViewAsSession.begin(
        ownerEmail: owner.email!,
        ownerPassword: password,
        employeeLabel: '${person.employee.firstName} ${person.employee.lastName}',
      );

      final email = demoEmployeeEmail(person.employee.firstName, person.employee.lastName);
      await AuthService().logout();
      await AuthService().login(email: email, password: kDemoEmployeePassword);

      if (!mounted) return;
      // Pop back to the root route — the root itself will already be
      // showing the employee's dashboard by the time this resolves,
      // since AuthGate reacts to the sign-in above on its own.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      ViewAsSession.clear();
      if (!mounted) return;
      setState(() => _switching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not switch accounts: $e')),
      );
    }
  }

  Future<String?> _promptForOwnerPassword(EmployeeWithMembership person) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        var obscure = true;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('View as ${person.employee.firstName} ${person.employee.lastName}?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "You'll be signed out of your Owner account and signed into "
                    "this employee's real account — everything they can see and "
                    'do, exactly as they see it.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confirm your Owner password so you can switch back afterward. '
                    "This is only kept in memory for this session — it's never "
                    'saved anywhere. If you mistype it, you can always sign back '
                    'in manually from the welcome screen.',
                    style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Your password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('Switch'),
                ),
              ],
            );
          },
        );
      },
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
        title: const Text(
          'View As Employee',
          style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      const Text(
                        'Pick an employee to see the app exactly as they would — '
                        'a real sign-in as their seeded account, not a preview.',
                        style: TextStyle(color: AppTheme.mutedText),
                      ),
                      const SizedBox(height: 16),
                      for (final person in _people)
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.blue.withOpacity(0.12),
                              child: Text(
                                person.employee.firstName.isNotEmpty ? person.employee.firstName[0] : '?',
                                style: const TextStyle(color: AppTheme.blue, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                              '${person.employee.firstName} ${person.employee.lastName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText),
                            ),
                            subtitle: Text(
                              [
                                if (person.employee.jobTitle != null) person.employee.jobTitle!,
                                person.role == FSRoles.manager ? 'Manager' : 'Employee',
                              ].join(' · '),
                            ),
                            trailing: FilledButton(
                              onPressed: _switching ? null : () => _viewAs(person),
                              child: const Text('View as'),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
