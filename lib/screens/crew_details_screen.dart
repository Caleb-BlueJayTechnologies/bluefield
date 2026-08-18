import 'package:flutter/material.dart';

import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/messaging_service.dart';
import '../Services/permission_service.dart';
import '../theme/app_theme.dart';
import 'conversation_screen.dart';
import 'edit_crew_screen.dart';

class CrewDetailsScreen extends StatefulWidget {
  final String crewId;
  final Map<String, dynamic> crewData;

  const CrewDetailsScreen({super.key, required this.crewId, required this.crewData});

  @override
  State<CrewDetailsScreen> createState() => _CrewDetailsScreenState();
}

class _CrewDetailsScreenState extends State<CrewDetailsScreen> {
  final AuthService _authService = AuthService();
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();
  final MessagingService _messagingService = MessagingService();

  late CrewModel _crew;
  late Future<_CrewDetailsData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _crew = CrewModel.fromMap(widget.crewId, widget.crewData);
    _dataFuture = _loadData();
  }

  Future<_CrewDetailsData> _loadData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final members = await _crewService.getActiveMembers(companyId: companyId, crewId: widget.crewId);
    final allEmployees = await _employeeService.getEmployeesByCompany(companyId: companyId);

    EmployeeModel? leader;
    if (_crew.leaderId != null) {
      for (final e in allEmployees) {
        if (e.employeeId == _crew.leaderId) {
          leader = e.employee;
          break;
        }
      }
    }

    final availableToAdd = allEmployees
        .where((e) => !e.employee.crewIds.contains(widget.crewId))
        .map((e) => e.employee)
        .toList();

    return _CrewDetailsData(
      companyId: companyId,
      actingUserId: profile.uid,
      canManageMembers: PermissionService.roleHasPermission(profile.role, Permission.crewsAssignMembers),
      members: members,
      leader: leader,
      availableToAdd: availableToAdd,
    );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<void> _removeMember(_CrewDetailsData data, EmployeeModel member) async {
    try {
      await _crewService.removeMemberFromCrew(
        companyId: data.companyId,
        actingUserId: data.actingUserId,
        crewId: widget.crewId,
        employeeId: member.employeeId,
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _showAddMemberSheet(_CrewDetailsData data) async {
    final selected = await showModalBottomSheet<EmployeeModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add Member', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                const SizedBox(height: 12),
                if (data.availableToAdd.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No other employees available to add.', style: TextStyle(color: AppTheme.mutedText)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: data.availableToAdd.length,
                      itemBuilder: (context, index) {
                        final employee = data.availableToAdd[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(employee.fullName),
                          subtitle: employee.hasCrew ? const Text('Currently on another crew') : null,
                          onTap: () => Navigator.pop(context, employee),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    try {
      await _crewService.addMemberToCrew(
        companyId: data.companyId,
        actingUserId: data.actingUserId,
        crewId: widget.crewId,
        employeeId: selected.employeeId,
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openCrewChat(_CrewDetailsData data) async {
    try {
      final threadId = await _messagingService.getOrCreateCrewThread(
        companyId: data.companyId,
        actingUserId: data.actingUserId,
        crewId: widget.crewId,
        crewName: _crew.crewName,
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConversationScreen(companyId: data.companyId, threadId: threadId),
        ),
      );
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
        title: Text(_crew.crewName, style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<_CrewDetailsData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  snapshot.error?.toString() ?? 'Unable to load crew.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ),
            );
          }

          final data = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              CrewHeaderCard(
                name: _crew.crewName,
                subtitle:
                    '${data.members.length} Member${data.members.length == 1 ? '' : 's'} • ${_crew.isArchived ? 'Archived' : 'Active'}',
              ),
              const SizedBox(height: 14),
              CrewInfoCard(
                title: 'Leader',
                icon: Icons.badge_outlined,
                children: [
                  CrewDetailRow(
                    title: data.leader?.fullName ?? 'No leader assigned',
                    subtitle: 'Crew leader',
                    icon: Icons.person,
                  ),
                ],
              ),
              CrewInfoCard(
                title: 'Members',
                icon: Icons.groups_outlined,
                children: [
                  if (data.members.isEmpty)
                    const CrewDetailRow(title: 'No members yet', subtitle: 'Add employees below', icon: Icons.person_outline)
                  else
                    ...data.members.map(
                      (member) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person, color: AppTheme.blue),
                        title: Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: member.jobTitle != null ? Text(member.jobTitle!) : null,
                        trailing: data.canManageMembers
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () => _removeMember(data, member),
                              )
                            : null,
                      ),
                    ),
                  if (data.canManageMembers) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () => _showAddMemberSheet(data),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Add Member'),
                      ),
                    ),
                  ],
                ],
              ),
              if (_crew.description?.trim().isNotEmpty == true)
                CrewInfoCard(
                  title: 'Description',
                  icon: Icons.notes_outlined,
                  children: [
                    CrewDetailRow(title: _crew.description!, subtitle: 'Crew description', icon: Icons.notes_outlined),
                  ],
                ),
              CrewInfoCard(
                title: 'Crew Chat',
                icon: Icons.chat_bubble_outline,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: () => _openCrewChat(data),
                      icon: const Icon(Icons.message_outlined),
                      label: const Text('Open Crew Chat'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditCrewScreen(crewId: widget.crewId, crewData: widget.crewData),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Crew'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CrewDetailsData {
  final String companyId;
  final String actingUserId;
  final bool canManageMembers;
  final List<EmployeeModel> members;
  final EmployeeModel? leader;
  final List<EmployeeModel> availableToAdd;

  const _CrewDetailsData({
    required this.companyId,
    required this.actingUserId,
    required this.canManageMembers,
    required this.members,
    required this.leader,
    required this.availableToAdd,
  });
}

class CrewHeaderCard extends StatelessWidget {
  final String name;
  final String subtitle;

  const CrewHeaderCard({super.key, required this.name, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppTheme.blue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 34,
              backgroundColor: Colors.white,
              child: Icon(Icons.groups, color: AppTheme.blue, size: 42),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CrewInfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const CrewInfoCard({super.key, required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                Icon(icon, color: AppTheme.blue),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class CrewDetailRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const CrewDetailRow({super.key, required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.blue),
      title: Text(title, style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.mutedText)),
    );
  }
}
