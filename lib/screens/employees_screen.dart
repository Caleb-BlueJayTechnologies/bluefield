import 'package:flutter/material.dart';

import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../theme/app_theme.dart';
import 'add_employee_screen.dart';
import 'employee_details_screen.dart';

class EmployeesScreen extends StatefulWidget {
  /// When true, shows only archived employees (reached via the "View
  /// Archived" button on the default screen) instead of the normal
  /// active-only roster.
  final bool archivedOnly;

  const EmployeesScreen({super.key, this.archivedOnly = false});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final AuthService _authService = AuthService();
  final EmployeeService _employeeService = EmployeeService();
  final CrewService _crewService = CrewService();

  final TextEditingController _searchController = TextEditingController();

  String _searchText = '';
  late Future<AuthUserProfile> _profileFuture;

  // Cached once per companyId so the search box's setState() (which
  // reruns build() on every keystroke) doesn't tear down and
  // resubscribe these Firestore listeners each time — see the audit
  // note on why creating a fresh stream inline in build() causes the
  // list to flash to a loading state on every character typed.
  String? _streamsCompanyId;
  Stream<Map<String, String>>? _crewNamesStream;
  Stream<List<EmployeeWithMembership>>? _employeesStream;

  @override
  void initState() {
    super.initState();
    _profileFuture = _authService.getCurrentUserProfile();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  void _ensureStreams(String companyId) {
    if (_streamsCompanyId == companyId) return;
    _streamsCompanyId = companyId;
    _crewNamesStream = _watchCrewNames(companyId);
    _employeesStream = _employeeService.watchEmployeesByCompany(
      companyId: companyId,
      includeArchived: true,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<Map<String, String>> _watchCrewNames(String companyId) {
    return _crewService
        .watchCrewsByCompany(companyId: companyId, includeArchived: true)
        .map((crews) => {for (final c in crews) c.crewId: c.crewName});
  }

  // Default view is active-only (archived employees no longer count
  // toward headcount anywhere in the app); the archived view is the
  // mirror image, showing only archived ones. Kept separate from
  // search filtering below so the two can report distinct empty
  // states — "no archived employees" vs. "no search matches".
  List<EmployeeWithMembership> _scopeToView(List<EmployeeWithMembership> employees) {
    return employees.where((e) => e.isArchived == widget.archivedOnly).toList();
  }

  List<EmployeeWithMembership> _filterEmployees(
    List<EmployeeWithMembership> employees,
    Map<String, String> crewNames,
  ) {
    if (_searchText.isEmpty) return employees;

    return employees.where((e) {
      final name = e.employee.fullName.toLowerCase();
      final role = e.role.toLowerCase();
      final crew = e.employee.crewIds.map((id) => crewNames[id] ?? '').join(' ').toLowerCase();
      final title = (e.employee.jobTitle ?? '').toLowerCase();

      return name.contains(_searchText) ||
          role.contains(_searchText) ||
          crew.contains(_searchText) ||
          title.contains(_searchText);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: Text(
          widget.archivedOnly ? 'Archived Employees' : 'Employees',
          style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!widget.archivedOnly)
            IconButton(
              tooltip: 'View Archived',
              icon: const Icon(Icons.person_off_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EmployeesScreen(archivedOnly: true)),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.archivedOnly ? 'Search archived employees...' : 'Search employees...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FutureBuilder<AuthUserProfile>(
                  future: _profileFuture,
                  builder: (context, profileSnapshot) {
                    if (profileSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (profileSnapshot.hasError || !profileSnapshot.hasData) {
                      return Center(
                        child: Text(
                          profileSnapshot.error?.toString() ?? 'Unable to load your company.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      );
                    }

                    final profile = profileSnapshot.data!;
                    final companyId = profile.activeCompanyId;
                    final canCreate = PermissionService.roleHasPermission(profile.role, Permission.employeesCreate);
                    _ensureStreams(companyId);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: StreamBuilder<Map<String, String>>(
                            stream: _crewNamesStream,
                            builder: (context, crewSnapshot) {
                              final crewNames = crewSnapshot.data ?? {};

                              return StreamBuilder<List<EmployeeWithMembership>>(
                                stream: _employeesStream,
                                builder: (context, employeeSnapshot) {
                                  if (employeeSnapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  if (employeeSnapshot.hasError) {
                                    return Center(
                                      child: Text(
                                        employeeSnapshot.error.toString(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppTheme.mutedText),
                                      ),
                                    );
                                  }

                                  final employees = _scopeToView(employeeSnapshot.data ?? []);
                                  final filtered = _filterEmployees(employees, crewNames);

                                  if (employees.isEmpty) {
                                    return EmptyEmployeesState(archivedOnly: widget.archivedOnly);
                                  }
                                  if (filtered.isEmpty) {
                                    return const Center(
                                      child: Text('No employees match your search.',
                                          style: TextStyle(color: AppTheme.mutedText)),
                                    );
                                  }

                                  return ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final entry = filtered[index];
                                      final crewName = entry.employee.crewIds.isEmpty
                                          ? null
                                          : entry.employee.crewIds.map((id) => crewNames[id]).whereType<String>().join(', ');

                                      return EmployeeCard(
                                        entry: entry,
                                        crewName: crewName,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => EmployeeDetailsScreen(
                                                employeeId: entry.employeeId,
                                                employeeData: entry.employee.toMap(),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (canCreate && !widget.archivedOnly)
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const AddEmployeeScreen()),
                                );
                              },
                              icon: const Icon(Icons.person_add_alt_1),
                              label: const Text('Add Employee'),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyEmployeesState extends StatelessWidget {
  final bool archivedOnly;

  const EmptyEmployeesState({super.key, this.archivedOnly = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        archivedOnly ? 'No archived employees.' : 'No employees added yet.',
        style: const TextStyle(color: AppTheme.mutedText, fontSize: 16),
      ),
    );
  }
}

class EmployeeCard extends StatelessWidget {
  final EmployeeWithMembership entry;
  final String? crewName;
  final VoidCallback onTap;

  const EmployeeCard({super.key, required this.entry, required this.crewName, required this.onTap});

  String get _displayRole {
    final role = entry.role;
    if (role.isEmpty) return 'Employee';
    return role[0].toUpperCase() + role.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      _displayRole,
      if (entry.employee.jobTitle?.trim().isNotEmpty == true) entry.employee.jobTitle!.trim(),
      if (crewName != null && crewName!.trim().isNotEmpty) crewName!.trim(),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(entry.isArchived ? Icons.person_off_outlined : Icons.person_outline),
        ),
        title: Text(
          entry.employee.fullName.trim().isEmpty ? 'Unnamed' : entry.employee.fullName,
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(subtitleParts.join(' • '), style: const TextStyle(color: AppTheme.mutedText)),
              _StatusBadge(isArchived: entry.isArchived),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isArchived;

  const _StatusBadge({required this.isArchived});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isArchived ? Colors.grey.withOpacity(0.16) : AppTheme.blue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isArchived ? 'Archived' : 'Active',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isArchived ? AppTheme.mutedText : AppTheme.blue,
        ),
      ),
    );
  }
}
