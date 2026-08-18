import 'package:flutter/material.dart';
import '../Firebase/firestore_schema.dart';
import '../Models/announcement_model.dart';
import '../Models/company_settings_model.dart';
import '../Models/employee_model.dart';
import '../Models/message_thread_model.dart';
import '../Models/schedule_model.dart';
import '../Models/time_entry_model.dart';
import '../Services/announcement_service.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/employee_service.dart';
import '../Services/messaging_service.dart';
import '../Services/notification_service.dart';
import '../Services/schedule_service.dart';
import '../Services/time_entry_service.dart';
import '../Widgets/dashboard_card.dart';
import '../theme/app_theme.dart';
import 'announcements_screen.dart';
import 'app_nav_drawer.dart';
import 'system_announcement_banner.dart';
import 'clock_in_screen.dart';
import 'conversation_screen.dart';
import 'employee_notifications_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'jobs_screen.dart';
import 'settings_screen.dart';
import 'time_off_requests_screen.dart';

class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  State<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> {
  final AuthService _authService = AuthService();
  final CompanySettingsService _settingsService = CompanySettingsService();
  final EmployeeService _employeeService = EmployeeService();

  int selectedIndex = 0;

  late Future<_DashboardContext> _contextFuture;

  @override
  void initState() {
    super.initState();
    _contextFuture = _loadContext();
  }

  Future<_DashboardContext> _loadContext() async {
    final profile = await _authService.getCurrentUserProfile();
    final employee = await _employeeService.getEmployee(
      companyId: profile.activeCompanyId,
      employeeId: profile.uid,
    );

    return _DashboardContext(
      companyId: profile.activeCompanyId,
      employeeId: profile.uid,
      displayName: employee?.displayName ?? profile.firstName,
      crewIds: employee?.crewIds ?? const [],
    );
  }

  void _openScheduleTab() {
    setState(() {
      selectedIndex = 1;
    });
  }

  void _openMessagesTab() {
    setState(() {
      selectedIndex = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardContext>(
      future: _contextFuture,
      builder: (context, contextSnapshot) {
        if (contextSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (contextSnapshot.hasError || !contextSnapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  contextSnapshot.error?.toString() ??
                      'Unable to load your dashboard.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final ctx = contextSnapshot.data!;

        final List<Widget> screens = [
          StreamBuilder<CompanySettingsModel>(
            stream: _settingsService.watchCompanySettings(ctx.companyId),
            builder: (context, settingsSnapshot) {
              if (settingsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (settingsSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      settingsSnapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  ),
                );
              }

              final settings = settingsSnapshot.data ??
                  CompanySettingsModel.defaults(companyId: ctx.companyId);

              return DashboardContent(
                dashboardContext: ctx,
                settings: settings,
                settingsService: _settingsService,
                onOpenMessages: _openMessagesTab,
                onOpenSchedule: _openScheduleTab,
              );
            },
          ),
          const JobsScreen(),
          const MessagesScreen(),
          const ProfileScreen(),
        ];

        return Scaffold(
          drawer: AppNavDrawer(role: FSRoles.employee, companyId: ctx.companyId),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.white,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.blue.withOpacity(0.15)),
                  ),
                  child: Image.asset('assets/images/bluefield_logo.png'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hi, ${ctx.displayName}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkText,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              _NotificationBell(
                companyId: ctx.companyId,
                userId: ctx.employeeId,
              ),
              Builder(
                builder: (buttonContext) {
                  return IconButton(
                    tooltip: 'Settings',
                    onPressed: () {
                      Navigator.of(buttonContext).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_outlined),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                const SystemAnnouncementBanner(),
                Expanded(child: IndexedStack(index: selectedIndex, children: screens)),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Schedule',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Messages',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardContext {
  final String companyId;
  final String employeeId;
  final String displayName;
  final List<String> crewIds;

  const _DashboardContext({
    required this.companyId,
    required this.employeeId,
    required this.displayName,
    this.crewIds = const [],
  });
}

class _NotificationBell extends StatelessWidget {
  final String companyId;
  final String userId;

  const _NotificationBell({required this.companyId, required this.userId});

  @override
  Widget build(BuildContext context) {
    final notificationService = NotificationService();

    return StreamBuilder<int>(
      stream: notificationService.watchUnreadCount(
        companyId: companyId,
        userId: userId,
      ),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;

        return IconButton(
          tooltip: 'Notifications',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EmployeeNotificationsScreen(),
              ),
            );
          },
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 9 ? '9+' : '$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

class DashboardContent extends StatelessWidget {
  final _DashboardContext dashboardContext;
  final CompanySettingsModel settings;
  final CompanySettingsService settingsService;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenSchedule;

  const DashboardContent({
    super.key,
    required this.dashboardContext,
    required this.settings,
    required this.settingsService,
    required this.onOpenMessages,
    required this.onOpenSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width >= 700;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back, ${dashboardContext.displayName}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkText,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Here is your workday at a glance.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.mutedText,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: isWideScreen ? 2 : 1,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: isWideScreen ? 1.55 : 1,
                  mainAxisExtent: isWideScreen ? 300 : 320,
                  children: [
                    if (settingsService.isFeatureEnabled(settings, 'teamTime'))
                      ClockStatusCard(
                        companyId: dashboardContext.companyId,
                        employeeId: dashboardContext.employeeId,
                      ),
                    if (settingsService.isFeatureEnabled(settings, 'schedule'))
                      ScheduleCard(
                        companyId: dashboardContext.companyId,
                        employeeId: dashboardContext.employeeId,
                        crewIds: dashboardContext.crewIds,
                        onOpenSchedule: onOpenSchedule,
                      ),
                    if (settingsService.isFeatureEnabled(settings, 'messaging'))
                      MessagesCard(
                        companyId: dashboardContext.companyId,
                        employeeId: dashboardContext.employeeId,
                        onOpenMessages: onOpenMessages,
                      ),
                    if (settingsService.isFeatureEnabled(settings, 'timeOff'))
                      const TimeOffCard(),
                    if (settingsService.isFeatureEnabled(settings, 'announcements'))
                      AnnouncementsCard(
                        companyId: dashboardContext.companyId,
                        userId: dashboardContext.employeeId,
                        crewIds: dashboardContext.crewIds,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClockStatusCard extends StatelessWidget {
  final String companyId;
  final String employeeId;

  const ClockStatusCard({
    super.key,
    required this.companyId,
    required this.employeeId,
  });

  String _formatSince(DateTime time) {
    final hour = time.hour == 0
        ? 12
        : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final timeEntryService = TimeEntryService();

    return DashboardCard(
      icon: Icons.access_time,
      title: 'Clock Status',
      child: StreamBuilder<TimeEntryModel?>(
        stream: timeEntryService.watchActiveClockEntry(
          companyId: companyId,
          employeeId: employeeId,
        ),
        builder: (context, snapshot) {
          final activeEntry = snapshot.data;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: activeEntry != null ? Colors.green : AppTheme.mutedText,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    activeEntry != null
                        ? 'Clocked in since ${_formatSince(activeEntry.clockInAt)}'
                        : 'Not clocked in',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkText,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(activeEntry != null ? 'Open Clock' : 'Clock In'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ClockInScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ScheduleCard extends StatelessWidget {
  final String companyId;
  final String employeeId;
  final List<String> crewIds;
  final VoidCallback onOpenSchedule;

  const ScheduleCard({
    super.key,
    required this.companyId,
    required this.employeeId,
    this.crewIds = const [],
    required this.onOpenSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final scheduleService = ScheduleService();

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onOpenSchedule,
      child: DashboardCard(
        icon: Icons.calendar_today_outlined,
        title: "Today's Schedule",
        child: StreamBuilder<List<ScheduleModel>>(
          stream: scheduleService.watchTodaysScheduleForEmployee(
            companyId: companyId,
            employeeId: employeeId,
            crewIds: crewIds,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final entries = snapshot.data ?? [];

            if (entries.isEmpty) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No shifts scheduled today.',
                    style: TextStyle(fontSize: 15, color: AppTheme.mutedText),
                  ),
                  Spacer(),
                  Text(
                    'Tap to view the full schedule.',
                    style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in entries.take(2)) ...[
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkText,
                    ),
                  ),
                  Text(
                    entry.isAllDay
                        ? 'All day'
                        : '${_formatTime(entry.startAt)} - ${_formatTime(entry.endAt)}',
                    style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                ],
                const Spacer(),
                const Text(
                  'Tap to view the full schedule.',
                  style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class MessagesCard extends StatelessWidget {
  final String companyId;
  final String employeeId;
  final VoidCallback onOpenMessages;

  const MessagesCard({
    super.key,
    required this.companyId,
    required this.employeeId,
    required this.onOpenMessages,
  });

  @override
  Widget build(BuildContext context) {
    final messagingService = MessagingService();

    return DashboardCard(
      icon: Icons.message_outlined,
      title: 'Messages',
      child: StreamBuilder<List<MessageThreadModel>>(
        stream: messagingService.watchThreadsForUser(
          companyId: companyId,
          userId: employeeId,
        ),
        builder: (context, snapshot) {
          final threads = (snapshot.data ?? []).take(3).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: threads.isEmpty
                    ? const Center(
                        child: Text(
                          'No conversations yet.',
                          style: TextStyle(color: AppTheme.mutedText),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final thread in threads) ...[
                              MessagePreview(
                                sender: thread.title?.isNotEmpty == true
                                    ? thread.title!
                                    : _labelForType(thread.type),
                                message: thread.lastMessagePreview ?? 'No messages yet',
                                unread: thread.unreadCountFor(employeeId) > 0,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ConversationScreen(
                                        companyId: companyId,
                                        threadId: thread.threadId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
              ),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: onOpenMessages,
                  child: const Text('Open Messages'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _labelForType(String type) {
    switch (type) {
      case ThreadType.crew:
        return 'Crew Chat';
      case ThreadType.manager:
        return 'Manager Chat';
      case ThreadType.companyWide:
        return 'Company-wide';
      case ThreadType.job:
        return 'Job Conversation';
      case ThreadType.direct:
      default:
        return 'Direct Message';
    }
  }
}

class MessagePreview extends StatelessWidget {
  final String sender;
  final String message;
  final bool unread;
  final VoidCallback onTap;

  const MessagePreview({
    super.key,
    required this.sender,
    required this.message,
    this.unread = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 4,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: unread ? AppTheme.blue : AppTheme.mutedText.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                      color: AppTheme.darkText,
                    ),
                  ),
                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TimeOffCard extends StatelessWidget {
  const TimeOffCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      icon: Icons.event_busy_outlined,
      title: 'Time Off',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Request time off and review your request history.',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.mutedText,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Open Time Off'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TimeOffRequestsScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AnnouncementsCard extends StatelessWidget {
  final String companyId;
  final String userId;
  final List<String> crewIds;

  const AnnouncementsCard({
    super.key,
    required this.companyId,
    required this.userId,
    this.crewIds = const [],
  });

  @override
  Widget build(BuildContext context) {
    final announcementService = AnnouncementService();

    return DashboardCard(
      icon: Icons.campaign_outlined,
      title: 'Announcements',
      // Was a raw one-time Firestore query that only filtered on
      // isArchived/isVisible — it ignored announcement targeting
      // entirely, so crew-specific, directly-targeted, and
      // managers-only announcements all leaked to every employee.
      // AnnouncementService.watchVisibleAnnouncements applies the real
      // targeting rules (Section: announcement visibility) and stays
      // live instead of one-shot.
      child: StreamBuilder<List<AnnouncementModel>>(
        stream: announcementService.watchVisibleAnnouncements(
          companyId: companyId,
          userId: userId,
          crewIds: crewIds,
          role: FSRoles.employee,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final announcements = (snapshot.data ?? []).take(3).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: announcements.isEmpty
                    ? const Center(
                        child: Text(
                          'No new announcements.',
                          style: TextStyle(fontSize: 15, color: AppTheme.mutedText),
                        ),
                      )
                    : ListView.separated(
                        itemCount: announcements.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final a = announcements[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AnnouncementsScreen(),
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (a.isPinned)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.push_pin,
                                            size: 14, color: AppTheme.blue),
                                      ),
                                    Expanded(
                                      child: Text(
                                        a.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.darkText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  a.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.mutedText,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AnnouncementsScreen(),
                      ),
                    );
                  },
                  child: const Text('View All'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
