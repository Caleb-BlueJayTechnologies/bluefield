import 'package:flutter/material.dart';

import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../theme/app_theme.dart';
import 'create_crew_screen.dart';
import 'crew_details_screen.dart';

class CrewsScreen extends StatefulWidget {
  const CrewsScreen({super.key});

  @override
  State<CrewsScreen> createState() => _CrewsScreenState();
}

class _CrewsScreenState extends State<CrewsScreen> {
  final AuthService _authService = AuthService();
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  final TextEditingController _searchController = TextEditingController();

  String _searchText = '';
  late Future<_CrewsReferenceData> _referenceFuture;

  // Cached once per companyId — see _ensureCrewsStream below for why.
  String? _crewsStreamCompanyId;
  Stream<List<CrewModel>>? _crewsStream;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  // The search box's setState() reruns build() on every keystroke;
  // without caching, calling watchCrewsByCompany() inline in build()
  // would hand StreamBuilder a brand-new Stream each time, tearing
  // down and resubscribing the Firestore listener (and flashing the
  // list to a loading state) on every character typed.
  Stream<List<CrewModel>> _ensureCrewsStream(String companyId) {
    if (_crewsStreamCompanyId != companyId || _crewsStream == null) {
      _crewsStreamCompanyId = companyId;
      _crewsStream = _crewService.watchCrewsByCompany(companyId: companyId);
    }
    return _crewsStream!;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_CrewsReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final settings = await _settingsService.getCompanySettings(companyId);
    final crewLabel = settings.crewTerminology == 'team' ? 'Team' : 'Crew';

    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId, includeArchived: true);
    final employeesById = {for (final e in employees) e.employeeId: e.employee};

    final memberCountByCrew = <String, int>{};
    for (final e in employees) {
      if (e.isArchived) continue;
      for (final crewId in e.employee.crewIds) {
        memberCountByCrew[crewId] = (memberCountByCrew[crewId] ?? 0) + 1;
      }
    }

    return _CrewsReferenceData(
      companyId: companyId,
      crewLabel: crewLabel,
      employeesById: employeesById,
      memberCounts: memberCountByCrew,
    );
  }

  List<CrewModel> _filterCrews(List<CrewModel> crews, _CrewsReferenceData reference) {
    if (_searchText.isEmpty) return crews;

    return crews.where((crew) {
      final name = crew.crewName.toLowerCase();
      final leader = crew.leaderId != null ? (reference.employeesById[crew.leaderId]?.fullName ?? '').toLowerCase() : '';
      return name.contains(_searchText) || leader.contains(_searchText);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CrewsReferenceData>(
      future: _referenceFuture,
      builder: (context, refSnapshot) {
        // No hardcoded fallback here on purpose — showing "Crews" as a
        // guess before the real company setting loads, then flipping
        // to "Teams" once it resolves, is a visible wrong-word flash.
        // An empty title for the brief loading window is far less
        // jarring than showing the wrong word and correcting it.
        final crewLabel = refSnapshot.data?.crewLabel;

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.white,
            title: Text(crewLabel == null ? '' : '${crewLabel}s', style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search ${(crewLabel ?? 'crew').toLowerCase()}s...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Builder(
                      builder: (context) {
                        if (refSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (refSnapshot.hasError || !refSnapshot.hasData) {
                          return Center(
                            child: Text(
                              refSnapshot.error?.toString() ?? 'Unable to load crews.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.mutedText),
                            ),
                          );
                        }

                        final reference = refSnapshot.data!;

                        return StreamBuilder<List<CrewModel>>(
                          stream: _ensureCrewsStream(reference.companyId),
                          builder: (context, crewsSnapshot) {
                            if (crewsSnapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (crewsSnapshot.hasError) {
                              return Center(
                                child: Text(crewsSnapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)),
                              );
                            }

                            final crews = crewsSnapshot.data ?? [];
                            final filtered = _filterCrews(crews, reference);

                            if (crews.isEmpty) {
                              return EmptyCrewsState(crewLabel: reference.crewLabel);
                            }
                            if (filtered.isEmpty) {
                              return Center(
                                child: Text('No ${reference.crewLabel.toLowerCase()}s match your search.',
                                    style: const TextStyle(color: AppTheme.mutedText)),
                              );
                            }

                            return Column(
                              children: [
                                ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final crew = filtered[index];
                                final leaderName =
                                    crew.leaderId != null ? reference.employeesById[crew.leaderId]?.fullName : null;

                                return CrewCard(
                                  crew: crew,
                                  leaderName: leaderName,
                                  memberCount: reference.memberCounts[crew.crewId] ?? 0,
                                  onTap: () {
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
                                );
                              },
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateCrewScreen()));
                                    },
                                    icon: const Icon(Icons.group_add_outlined),
                                    label: Text('Create ${crewLabel ?? 'Crew'}'),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CrewsReferenceData {
  final String companyId;
  final String crewLabel;
  final Map<String, EmployeeModel> employeesById;
  final Map<String, int> memberCounts;

  const _CrewsReferenceData({
    required this.companyId,
    required this.crewLabel,
    required this.employeesById,
    required this.memberCounts,
  });
}

class EmptyCrewsState extends StatelessWidget {
  final String crewLabel;

  const EmptyCrewsState({super.key, required this.crewLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No ${crewLabel.toLowerCase()}s created yet.', style: const TextStyle(color: AppTheme.mutedText, fontSize: 16)),
    );
  }
}

class CrewCard extends StatelessWidget {
  final CrewModel crew;
  final String? leaderName;
  final int memberCount;
  final VoidCallback onTap;

  const CrewCard({super.key, required this.crew, required this.leaderName, required this.memberCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      '$memberCount Member${memberCount == 1 ? '' : 's'}',
      if (leaderName != null && leaderName!.trim().isNotEmpty) 'Led by $leaderName',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.groups)),
        title: Text(crew.crewName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
        subtitle: Text(subtitleParts.join(' • '), style: const TextStyle(color: AppTheme.mutedText)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
