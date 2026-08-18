import 'package:flutter/material.dart';
import '../Services/auth_service.dart';
import '../Services/notification_service.dart';
import '../Models/notification_model.dart';
import '../theme/app_theme.dart';

class EmployeeNotificationsScreen extends StatefulWidget {
  const EmployeeNotificationsScreen({super.key});

  @override
  State<EmployeeNotificationsScreen> createState() =>
      _EmployeeNotificationsScreenState();
}

class _EmployeeNotificationsScreenState
    extends State<EmployeeNotificationsScreen> {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();

  late Future<({String companyId, String userId})> _contextFuture;

  @override
  void initState() {
    super.initState();
    _contextFuture = _loadContext();
  }

  Future<({String companyId, String userId})> _loadContext() async {
    final profile = await _authService.getCurrentUserProfile();
    return (companyId: profile.activeCompanyId, userId: profile.uid);
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.month}/${time.day}/${time.year}';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case NotificationType.scheduleAssignment:
      case NotificationType.scheduleChange:
        return Icons.calendar_month_outlined;
      case NotificationType.jobAssignment:
      case NotificationType.jobCancellation:
        return Icons.work_outline;
      case NotificationType.newMessage:
        return Icons.chat_bubble_outline;
      case NotificationType.newAnnouncement:
        return Icons.campaign_outlined;
      case NotificationType.timeOffDecision:
        return Icons.event_busy_outlined;
      case NotificationType.correctionDecision:
        return Icons.access_time;
      case NotificationType.pendingApproval:
        return Icons.pending_actions_outlined;
      case NotificationType.employeeInvitation:
        return Icons.person_add_outlined;
      default:
        return Icons.notifications_outlined;
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
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: AppTheme.darkText,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          FutureBuilder(
            future: _contextFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final ctx = snapshot.data!;
              return TextButton(
                onPressed: () async {
                  await _notificationService.markAllAsRead(
                    companyId: ctx.companyId,
                    userId: ctx.userId,
                  );
                },
                child: const Text('Mark all read'),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder(
        future: _contextFuture,
        builder: (context, contextSnapshot) {
          if (contextSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!contextSnapshot.hasData) {
            return const Center(child: Text('Unable to load notifications.'));
          }

          final ctx = contextSnapshot.data!;

          return StreamBuilder<List<NotificationModel>>(
            stream: _notificationService.watchNotifications(
              companyId: ctx.companyId,
              userId: ctx.userId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final notifications = snapshot.data ?? [];

              if (notifications.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No notifications yet.',
                      style: TextStyle(color: AppTheme.mutedText, fontSize: 15),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final notification = notifications[index];

                  return Card(
                    elevation: 0,
                    color: notification.isRead
                        ? Colors.white
                        : AppTheme.blue.withOpacity(0.06),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      onTap: () async {
                        if (!notification.isRead) {
                          await _notificationService.markAsRead(
                            companyId: ctx.companyId,
                            notificationId: notification.notificationId,
                          );
                        }
                        // Deep-link routing by notification.deepLinkRoute
                        // isn't wired up yet — this app doesn't have a
                        // named-route table (main.dart uses direct
                        // MaterialPageRoute pushes). Marking read is the
                        // functional part; navigating to the specific
                        // related screen can be added once route names
                        // exist to map deepLinkRoute values onto.
                      },
                      leading: CircleAvatar(
                        backgroundColor: notification.isRead
                            ? AppTheme.background
                            : AppTheme.blue.withOpacity(0.15),
                        child: Icon(
                          _iconForType(notification.type),
                          color: AppTheme.blue,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight:
                              notification.isRead ? FontWeight.w600 : FontWeight.bold,
                          color: AppTheme.darkText,
                        ),
                      ),
                      subtitle: Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _timeAgo(notification.createdAt),
                        style: const TextStyle(fontSize: 11, color: AppTheme.mutedText),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
