import 'package:flutter/material.dart';

import '../Models/system_announcement_model.dart';
import '../Services/system_announcement_service.dart';
import '../theme/app_theme.dart';

/// Shows active BlueJay system announcements at the top of the main
/// app — maintenance windows, outages, platform-wide notices. Distinct
/// from a company's own internal announcements screen; this is what
/// platform admins broadcast via AdminSystemAnnouncementsScreen.
///
/// Dismissal is per-session only (in-memory, not persisted) — a
/// critical notice should reappear next time the app opens rather
/// than staying hidden forever after one dismissal.
class SystemAnnouncementBanner extends StatefulWidget {
  const SystemAnnouncementBanner({super.key});

  @override
  State<SystemAnnouncementBanner> createState() => _SystemAnnouncementBannerState();
}

class _SystemAnnouncementBannerState extends State<SystemAnnouncementBanner> {
  final SystemAnnouncementService _service = SystemAnnouncementService();
  final Set<String> _dismissedIds = {};

  Color _severityColor(String severity) {
    switch (severity) {
      case SystemAnnouncementSeverity.critical:
        return Colors.red.shade600;
      case SystemAnnouncementSeverity.warning:
        return Colors.orange.shade700;
      default:
        return AppTheme.blue;
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case SystemAnnouncementSeverity.critical:
        return Icons.error_outline;
      case SystemAnnouncementSeverity.warning:
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SystemAnnouncementModel>>(
      stream: _service.watchActiveAnnouncements(),
      builder: (context, snapshot) {
        final announcements = (snapshot.data ?? [])
            .where((a) => !_dismissedIds.contains(a.announcementId))
            .toList();

        if (announcements.isEmpty) return const SizedBox.shrink();

        return Column(
          children: announcements.map((a) {
            final color = _severityColor(a.severity);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 2),
              color: color.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_severityIcon(a.severity), color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(a.body, style: const TextStyle(color: AppTheme.darkText, fontSize: 12)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _dismissedIds.add(a.announcementId)),
                    child: Icon(Icons.close, color: color, size: 18),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
