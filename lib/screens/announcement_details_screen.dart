import 'package:flutter/material.dart';

import '../Models/announcement_model.dart';
import '../Services/announcement_service.dart';
import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../theme/app_theme.dart';
import 'edit_announcement_screen.dart';

class AnnouncementDetailsScreen extends StatefulWidget {
  final String companyId;
  final String announcementId;

  const AnnouncementDetailsScreen({super.key, required this.companyId, required this.announcementId});

  @override
  State<AnnouncementDetailsScreen> createState() => _AnnouncementDetailsScreenState();
}

class _AnnouncementDetailsScreenState extends State<AnnouncementDetailsScreen> {
  final AuthService _authService = AuthService();
  final AnnouncementService _announcementService = AnnouncementService();
  final CrewService _crewService = CrewService();
  final EmployeeService _employeeService = EmployeeService();

  late Future<_DetailsData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_DetailsData> _loadData() async {
    final profile = await _authService.getCurrentUserProfile();

    final announcement = await _announcementService.getAnnouncement(
      companyId: widget.companyId,
      announcementId: widget.announcementId,
    );

    if (announcement == null) {
      throw Exception('This announcement was not found.');
    }

    final recipients = await _resolveRecipients(announcement);

    return _DetailsData(
      announcement: announcement,
      recipientLines: recipients,
      canEdit: PermissionService.roleHasPermission(profile.role, Permission.announcementsEdit),
      canArchive: PermissionService.roleHasPermission(profile.role, Permission.announcementsArchive),
      canPin: PermissionService.roleHasPermission(profile.role, Permission.announcementsPin),
      actingUserId: profile.uid,
    );
  }

  Future<List<String>> _resolveRecipients(AnnouncementModel announcement) async {
    switch (announcement.targetType) {
      case AnnouncementTargetType.companyWide:
        return const ['All Employees'];
      case AnnouncementTargetType.managersOnly:
        return const ['Managers Only'];
      case AnnouncementTargetType.crew:
        if (announcement.targetCrewIds.isEmpty) return const ['No crews selected'];
        final crews = await _crewService.getCrewsByCompany(companyId: widget.companyId, includeArchived: true);
        final names = crews.where((c) => announcement.targetCrewIds.contains(c.crewId)).map((c) => c.crewName).toList();
        return names.isEmpty ? const ['No crews selected'] : names;
      case AnnouncementTargetType.employees:
        if (announcement.targetUserIds.isEmpty) return const ['No employees selected'];
        final employees = await _employeeService.getEmployeesByCompany(companyId: widget.companyId, includeArchived: true);
        final names = employees
            .where((e) => announcement.targetUserIds.contains(e.employeeId))
            .map((e) => e.employee.fullName)
            .toList();
        return names.isEmpty ? const ['No employees selected'] : names;
      default:
        return const ['Unknown audience'];
    }
  }

  Future<void> _archive(_DetailsData data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Archive Announcement?'),
          content: const Text('This will remove it from everyone\'s announcement list.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await _announcementService.archiveAnnouncement(
        companyId: widget.companyId,
        actingUserId: data.actingUserId,
        announcementId: widget.announcementId,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _togglePin(_DetailsData data) async {
    try {
      await _announcementService.updateAnnouncement(
        companyId: widget.companyId,
        actingUserId: data.actingUserId,
        announcementId: widget.announcementId,
        isPinned: !data.announcement.isPinned,
      );
      if (!mounted) return;
      setState(() {
        _dataFuture = _loadData();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String _relativeDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) return 'Posted Today';
    if (difference.inDays == 1) return 'Posted Yesterday';
    if (difference.inDays < 7) return 'Posted ${difference.inDays} Days Ago';
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
        title: const Text('Announcement Details', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<_DetailsData>(
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
                  snapshot.error?.toString() ?? 'Unable to load this announcement.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final announcement = data.announcement;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                elevation: 0,
                color: AppTheme.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              announcement.title,
                              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (announcement.isPinned) const Icon(Icons.push_pin, color: Colors.white),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_relativeDate(announcement.createdAt), style: const TextStyle(color: Colors.white70)),
                      if (announcement.isEdited) ...[
                        const SizedBox(height: 4),
                        const Text('Edited', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    announcement.body,
                    style: const TextStyle(fontSize: 16, color: AppTheme.darkText, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Recipients', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...data.recipientLines.map((line) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(line),
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (data.canPin)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => _togglePin(data),
                      icon: Icon(announcement.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
                      label: Text(announcement.isPinned ? 'Unpin' : 'Pin to Top'),
                    ),
                  ),
                ),
              if (data.canEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditAnnouncementScreen(
                              companyId: widget.companyId,
                              announcementId: widget.announcementId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Announcement'),
                    ),
                  ),
                ),
              if (data.canArchive)
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _archive(data),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive Announcement'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailsData {
  final AnnouncementModel announcement;
  final List<String> recipientLines;
  final bool canEdit;
  final bool canArchive;
  final bool canPin;
  final String actingUserId;

  const _DetailsData({
    required this.announcement,
    required this.recipientLines,
    required this.canEdit,
    required this.canArchive,
    required this.canPin,
    required this.actingUserId,
  });
}
