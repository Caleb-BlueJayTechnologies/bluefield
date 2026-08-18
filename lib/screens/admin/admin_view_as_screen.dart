import 'package:flutter/material.dart';

import '../../Services/employee_service.dart';
import '../../theme/app_theme.dart';
import 'environment_indicator.dart';
import 'admin_view_as_summary_screen.dart';

class AdminViewAsScreen extends StatefulWidget {
  final String companyId;
  final String companyName;

  const AdminViewAsScreen({super.key, required this.companyId, required this.companyName});

  @override
  State<AdminViewAsScreen> createState() => _AdminViewAsScreenState();
}

class _AdminViewAsScreenState extends State<AdminViewAsScreen> {
  final EmployeeService _employeeService = EmployeeService();
  late Future<List<EmployeeWithMembership>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = _employeeService.getEmployeesByCompany(companyId: widget.companyId, includeArchived: false);
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'manager':
        return 'Manager';
      default:
        return 'Employee';
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
        title: Text('View As — ${widget.companyName}', style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const EnvironmentIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pick someone to see a read-only view of what they see. Nothing you do here can change real data — '
                  'you\'re still signed in as yourself.',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<EmployeeWithMembership>>(
                future: _membersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                  }

                  final members = snapshot.data ?? [];
                  if (members.isEmpty) {
                    return const Center(
                      child: Text('No active members in this company.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final m = members[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(m.employee.fullName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                          subtitle: Text(_roleLabel(m.role)),
                          trailing: const Icon(Icons.chevron_right, color: AppTheme.mutedText),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminViewAsSummaryScreen(
                                  companyId: widget.companyId,
                                  companyName: widget.companyName,
                                  targetUserId: m.employeeId,
                                  targetName: m.employee.fullName,
                                  targetRole: m.role,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
