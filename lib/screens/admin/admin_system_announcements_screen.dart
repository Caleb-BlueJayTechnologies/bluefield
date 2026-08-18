import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../Models/system_announcement_model.dart';
import '../../Services/system_announcement_service.dart';
import '../../theme/app_theme.dart';
import 'environment_indicator.dart';

class AdminSystemAnnouncementsScreen extends StatefulWidget {
  const AdminSystemAnnouncementsScreen({super.key});

  @override
  State<AdminSystemAnnouncementsScreen> createState() => _AdminSystemAnnouncementsScreenState();
}

class _AdminSystemAnnouncementsScreenState extends State<AdminSystemAnnouncementsScreen> {
  final SystemAnnouncementService _service = SystemAnnouncementService();
  late Stream<List<SystemAnnouncementModel>> _announcementsStream;
  bool _isActing = false;

  @override
  void initState() {
    super.initState();
    _announcementsStream = _service.watchAllAnnouncements();
  }

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Color _severityColor(String severity) {
    switch (severity) {
      case SystemAnnouncementSeverity.critical:
        return Colors.red;
      case SystemAnnouncementSeverity.warning:
        return Colors.orange;
      default:
        return AppTheme.blue;
    }
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case SystemAnnouncementSeverity.critical:
        return 'Critical';
      case SystemAnnouncementSeverity.warning:
        return 'Warning';
      default:
        return 'Info';
    }
  }

  Future<void> _openCreateDialog() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    var selectedSeverity = SystemAnnouncementSeverity.info;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New System Announcement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  decoration: const InputDecoration(labelText: 'Body'),
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedSeverity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: const [
                    DropdownMenuItem(value: SystemAnnouncementSeverity.info, child: Text('Info')),
                    DropdownMenuItem(value: SystemAnnouncementSeverity.warning, child: Text('Warning')),
                    DropdownMenuItem(value: SystemAnnouncementSeverity.critical, child: Text('Critical')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selectedSeverity = value);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'This shows to every company in the app immediately.',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish')),
          ],
        ),
      ),
    );

    if (created != true) return;
    if (titleController.text.trim().isEmpty || bodyController.text.trim().isEmpty) return;

    setState(() => _isActing = true);
    try {
      await _service.createAnnouncement(
        actingAdminId: _myUid,
        title: titleController.text.trim(),
        body: bodyController.text.trim(),
        severity: selectedSeverity,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement published.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _toggleActive(SystemAnnouncementModel announcement) async {
    setState(() => _isActing = true);
    try {
      await _service.setActive(
        actingAdminId: _myUid,
        announcementId: announcement.announcementId,
        isActive: !announcement.isActive,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _confirmDelete(SystemAnnouncementModel announcement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Announcement?'),
        content: Text('This permanently removes "${announcement.title}". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isActing = true);
    try {
      await _service.deleteAnnouncement(actingAdminId: _myUid, announcementId: announcement.announcementId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
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
        title: const Text('System Announcements', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isActing ? null : _openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Announcement'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const EnvironmentIndicator(),
            Expanded(
              child: StreamBuilder<List<SystemAnnouncementModel>>(
                stream: _announcementsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final announcements = snapshot.data ?? [];
                  if (announcements.isEmpty) {
                    return const Center(
                      child: Text('No system announcements yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                    itemCount: announcements.length,
                    itemBuilder: (context, index) {
                      final a = announcements[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _severityColor(a.severity).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _severityLabel(a.severity),
                                      style: TextStyle(color: _severityColor(a.severity), fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (!a.isActive)
                                    const Text('Inactive', style: TextStyle(color: AppTheme.mutedText, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.darkText)),
                              const SizedBox(height: 4),
                              Text(a.body, style: const TextStyle(color: AppTheme.mutedText)),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: _isActing ? null : () => _toggleActive(a),
                                    child: Text(a.isActive ? 'Deactivate' : 'Reactivate'),
                                  ),
                                  TextButton(
                                    onPressed: _isActing ? null : () => _confirmDelete(a),
                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
