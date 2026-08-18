import 'package:flutter/material.dart';
import '../Models/company_model.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../theme/app_theme.dart';
import 'crew_details_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<_ProfileData> _loadProfile() async {
    final authService = AuthService();
    final employeeService = EmployeeService();
    final companyService = CompanyService();
    final crewService = CrewService();
    final settingsService = CompanySettingsService();

    final profile = await authService.getCurrentUserProfile();

    final employee = await employeeService.getEmployee(
      companyId: profile.activeCompanyId,
      employeeId: profile.uid,
    );

    final company = await companyService.getCompany(profile.activeCompanyId);
    final settings = await settingsService.getCompanySettings(profile.activeCompanyId);

    final crews = <CrewModel>[];
    for (final crewId in employee?.crewIds ?? const []) {
      final crew = await crewService.getCrew(companyId: profile.activeCompanyId, crewId: crewId);
      if (crew != null) crews.add(crew);
    }

    return _ProfileData(
      profile: profile,
      employee: employee,
      company: company,
      crews: crews,
      crewLabel: settings.crewTerminology == 'team' ? 'Team' : 'Crew',
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'manager':
        return 'Manager';
      case 'employee':
        return 'Employee';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: FutureBuilder<_ProfileData>(
          future: _loadProfile(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                ),
              );
            }

            final data = snapshot.data;

            if (data == null) {
              return const Center(
                child: Text(
                  'Profile not found.',
                  style: TextStyle(color: AppTheme.mutedText),
                ),
              );
            }

            final profile = data.profile;
            final employee = data.employee;

            final fullName = employee?.fullName.trim().isNotEmpty == true
                ? employee!.fullName
                : '${profile.firstName} ${profile.lastName}'.trim();

            final subtitleParts = <String>[
              _roleLabel(profile.role),
              if (employee?.jobTitle?.trim().isNotEmpty == true) employee!.jobTitle!.trim(),
            ];

            final crewSubtitle = data.crews.isNotEmpty
                ? data.crews.map((c) => c.crewName).join(', ')
                : 'No ${data.crewLabel.toLowerCase()}';

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Center(
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: AppTheme.blue,
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    fullName.isEmpty ? 'Unnamed' : fullName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkText,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    subtitleParts.join(' • '),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.mutedText,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    crewSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.mutedText,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                for (final crew in data.crews) ...[
                  ProfileCard(
                    title: data.crews.length > 1 ? crew.crewName : 'My ${data.crewLabel}',
                    children: [
                      ProfileRow(
                        icon: Icons.groups_outlined,
                        title: data.crewLabel,
                        value: crew.crewName,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CrewDetailsScreen(
                                  crewId: crew.crewId,
                                  crewData: crew.toMap(),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.people_outline, size: 18),
                          label: Text('View ${data.crewLabel} Members'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
                ProfileCard(
                  title: 'Contact Information',
                  children: [
                    ProfileRow(
                      icon: Icons.phone_outlined,
                      title: 'Phone',
                      value: employee?.phone?.trim().isNotEmpty == true
                          ? employee!.phone!
                          : 'Not provided',
                    ),
                    ProfileRow(
                      icon: Icons.email_outlined,
                      title: 'Email',
                      value: profile.email.isEmpty ? 'Not provided' : profile.email,
                    ),
                  ],
                ),
                ProfileCard(
                  title: 'Account',
                  children: [
                    ProfileRow(
                      icon: Icons.business_outlined,
                      title: 'Company',
                      value: data.company?.companyName ?? 'Not provided',
                    ),
                    ProfileRow(
                      icon: Icons.badge_outlined,
                      title: 'Account Role',
                      value: _roleLabel(profile.role),
                    ),
                    if (employee?.employeeNumber?.trim().isNotEmpty == true)
                      ProfileRow(
                        icon: Icons.fingerprint_outlined,
                        title: 'Employee Number',
                        value: employee!.employeeNumber!,
                      ),
                    if (employee?.hireDate != null)
                      ProfileRow(
                        icon: Icons.event_outlined,
                        title: 'Hire Date',
                        value:
                            '${employee!.hireDate!.month}/${employee.hireDate!.day}/${employee.hireDate!.year}',
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Settings'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileData {
  final AuthUserProfile profile;
  final EmployeeModel? employee;
  final CompanyModel? company;
  final List<CrewModel> crews;
  final String crewLabel;

  const _ProfileData({
    required this.profile,
    required this.employee,
    required this.company,
    this.crews = const [],
    required this.crewLabel,
  });
}

class ProfileCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const ProfileCard({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkText,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class ProfileRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const ProfileRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppTheme.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppTheme.darkText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.mutedText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
