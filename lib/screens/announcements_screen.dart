import 'package:flutter/material.dart';

import '../Models/announcement_model.dart';
import '../Services/announcement_service.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../theme/app_theme.dart';
import 'announcement_details_screen.dart';
import 'create_announcement_screen.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final AuthService _authService = AuthService();
  final AnnouncementService _announcementService = AnnouncementService();
  final EmployeeService _employeeService = EmployeeService();

  late Future<_AnnouncementsReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
  }

  Future<_AnnouncementsReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final employee = await _employeeService.getEmployee(companyId: companyId, employeeId: profile.uid);

    return _AnnouncementsReferenceData(
      companyId: companyId,
      userId: profile.uid,
      role: profile.role,
      crewIds: employee?.crewIds ?? const [],
      canCreate: PermissionService.roleHasPermission(profile.role, Permission.announcementsCreate),
    );
  }

  String _relativeDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) return 'Posted Today';
    if (difference.inDays == 1) return 'Posted Yesterday';
    if (difference.inDays < 7) return 'Posted ${difference.inDays} Days Ago';
    if (difference.inDays < 14) return 'Posted Last Week';
    return 'Posted ${date.month}/${date.day}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Announcements', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: FutureBuilder<_AnnouncementsReferenceData>(
            future: _referenceFuture,
            builder: (context, refSnapshot) {
              if (refSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (refSnapshot.hasError || !refSnapshot.hasData) {
                return Center(
                  child: Text(
                    refSnapshot.error?.toString() ?? 'Unable to load announcements.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                );
              }

              final reference = refSnapshot.data!;

              return Column(
                children: [
                  Expanded(
                    child: StreamBuilder<List<AnnouncementModel>>(
                      stream: _announcementService.watchVisibleAnnouncements(
                    companyId: reference.companyId,
                    userId: reference.userId,
                    crewIds: reference.crewIds,
                    role: reference.role,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                    }

                    final announcements = snapshot.data ?? [];

                    if (announcements.isEmpty) {
                      return const Center(
                        child: Text('No announcements yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                      children: announcements
                          .map((a) => AnnouncementCard(
                                title: a.title,
                                date: _relativeDate(a.createdAt),
                                isPinned: a.isPinned,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AnnouncementDetailsScreen(
                                        companyId: reference.companyId,
                                        announcementId: a.announcementId,
                                      ),
                                    ),
                                  );
                                },
                              ))
                          .toList(),
                    );
                  },
                ),
              ),
              if (reference.canCreate)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateAnnouncementScreen()));
                      },
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('Create Announcement'),
                    ),
                  ),
                ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnnouncementsReferenceData {
  final String companyId;
  final String userId;
  final String role;
  final List<String> crewIds;
  final bool canCreate;

  const _AnnouncementsReferenceData({
    required this.companyId,
    required this.userId,
    required this.role,
    required this.crewIds,
    required this.canCreate,
  });
}

class AnnouncementCard extends StatelessWidget {
  final String title;
  final String date;
  final bool isPinned;
  final VoidCallback onTap;

  const AnnouncementCard({
    super.key,
    required this.title,
    required this.date,
    required this.isPinned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPinned ? AppTheme.blue.withOpacity(0.12) : null,
          child: Icon(isPinned ? Icons.push_pin : Icons.campaign_outlined, color: isPinned ? AppTheme.blue : null),
        ),
        title: Text(title),
        subtitle: Text(date),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
