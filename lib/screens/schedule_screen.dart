import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/schedule_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/job_service.dart';
import '../Services/permission_service.dart';
import '../Services/schedule_service.dart';
import '../theme/app_theme.dart';
import 'job_details_screen.dart';

enum _ScheduleViewMode { list, calendar }

class ScheduleScreen extends StatefulWidget {
  /// When true, shows the full company schedule regardless of the
  /// viewer's role (used by manager/employer dashboards that already
  /// know the viewer should see everything). When false, visibility is
  /// permission-driven via ScheduleService.watchVisibleSchedules.
  final bool showAllJobs;

  const ScheduleScreen({super.key, this.showAllJobs = false});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final AuthService _authService = AuthService();
  final ScheduleService _scheduleService = ScheduleService();
  final JobService _jobService = JobService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  _ScheduleViewMode _viewMode = _ScheduleViewMode.list;
  bool _isBackfilling = false;
  late Future<_ScheduleIdentity> _identityFuture;

  @override
  void initState() {
    super.initState();
    _identityFuture = _loadIdentity();
  }

  Future<_ScheduleIdentity> _loadIdentity() async {
    final profile = await _authService.getCurrentUserProfile();
    final settings = await _settingsService.getCompanySettings(profile.activeCompanyId);
    return _ScheduleIdentity(
      companyId: profile.activeCompanyId,
      userId: profile.uid,
      canManageJobs: PermissionService.roleHasPermission(profile.role, Permission.jobsEdit),
      canViewAllSchedule: PermissionService.roleHasPermission(profile.role, Permission.scheduleViewAll),
      visibilityWindow: settings.jobVisibilityWindow,
    );
  }

  String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  String _visibilityWindowLabel(String window) {
    switch (window) {
      case 'nextJob':
        return 'for your next job';
      case 'day':
        return 'for today';
      case 'month':
        return 'for the next 30 days';
      case 'week':
      default:
        return 'for the next 7 days';
    }
  }

  void _previousMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    });
  }

  void _goToCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
    });
  }

  String _monthLabel(DateTime month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[month.month - 1]} ${month.year}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  Future<void> _runBackfill(_ScheduleIdentity identity) async {
    setState(() => _isBackfilling = true);
    try {
      final count = await _jobService.backfillScheduleSync(
        companyId: identity.companyId,
        actingUserId: identity.userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(count == 0 ? 'Everything was already in sync.' : 'Synced $count job(s) to the calendar.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isBackfilling = false);
    }
  }

  Future<void> _openEntry(String companyId, ScheduleModel entry) async {
    if (entry.type == ScheduleType.job && entry.jobId != null) {
      try {
        final job = await _jobService.getJob(companyId: companyId, jobId: entry.jobId!);
        if (job == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Linked job was not found.')));
          return;
        }
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => JobDetailsScreen(jobData: {...job.toMap(), FSFields.jobId: job.jobId}),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                const SizedBox(height: 8),
                Text(
                  entry.isAllDay ? 'All day' : '${_formatTime(entry.startAt)} - ${_formatTime(entry.endAt)}',
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
                if (entry.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(entry.description!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (Navigator.of(context).canPop()) ...[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      color: AppTheme.darkText,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  const Expanded(
                    child: Text('Schedule', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                  ),
                  // List/Calendar toggle — this is the calendar grid
                  // view that used to live in its own, never-linked
                  // screen (calendar_schedule_screen.dart). Both modes
                  // now share the exact same data stream below instead
                  // of each opening their own separate listener.
                  IconButton(
                    tooltip: _viewMode == _ScheduleViewMode.list ? 'Switch to calendar view' : 'Switch to list view',
                    onPressed: () {
                      setState(() {
                        _viewMode =
                            _viewMode == _ScheduleViewMode.list ? _ScheduleViewMode.calendar : _ScheduleViewMode.list;
                      });
                    },
                    icon: Icon(_viewMode == _ScheduleViewMode.list ? Icons.calendar_month_outlined : Icons.view_list_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Your assigned shifts, jobs, and events.', style: TextStyle(fontSize: 15, color: AppTheme.mutedText)),
              const SizedBox(height: 16),
              FutureBuilder<_ScheduleIdentity>(
                future: _identityFuture,
                builder: (context, identitySnapshot) {
                  final identity = identitySnapshot.data;
                  if (identity == null || !identity.canManageJobs) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _isBackfilling ? null : () => _runBackfill(identity),
                        icon: _isBackfilling
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync, size: 18),
                        label: Text(_isBackfilling ? 'Syncing...' : 'Sync Existing Jobs'),
                      ),
                    ),
                  );
                },
              ),
              Row(
                children: [
                  IconButton(onPressed: _previousMonth, icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Text(
                      _monthLabel(_visibleMonth),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                    ),
                  ),
                  IconButton(onPressed: _nextMonth, icon: const Icon(Icons.chevron_right)),
                  TextButton(onPressed: _goToCurrentMonth, child: const Text('Today')),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<_ScheduleIdentity>(
                  future: _identityFuture,
                  builder: (context, identitySnapshot) {
                    if (identitySnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (identitySnapshot.hasError || !identitySnapshot.hasData) {
                      return Center(
                        child: Text(
                          identitySnapshot.error?.toString() ?? 'Unable to load schedule.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      );
                    }

                    final identity = identitySnapshot.data!;
                    final windowStart = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
                    final windowEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0, 23, 59, 59);

                    return StreamBuilder<List<ScheduleModel>>(
                      stream: widget.showAllJobs
                          ? _scheduleService.watchCompanySchedules(
                              companyId: identity.companyId,
                              windowStart: windowStart,
                              windowEnd: windowEnd,
                            )
                          : _scheduleService.watchVisibleSchedules(
                              companyId: identity.companyId,
                              requestingUserId: identity.userId,
                              windowStart: windowStart,
                              windowEnd: windowEnd,
                              visibilityWindow: identity.visibilityWindow,
                            ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              snapshot.error.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.mutedText),
                            ),
                          );
                        }

                        final rawEntries = snapshot.data ?? [];
                        final visibleEntries =
                            (widget.showAllJobs ? rawEntries : rawEntries.where((e) => e.isPublished).toList())
                              ..sort((a, b) => a.startAt.compareTo(b.startAt));

                        if (visibleEntries.isEmpty) {
                          // A restricted viewer paging into a month
                          // outside their company's configured
                          // visibility window (e.g. "Whole day only")
                          // will always land here for that month — say
                          // so, rather than reading like a genuinely
                          // empty schedule.
                          final isRestricted =
                              !identity.canViewAllSchedule && identity.visibilityWindow != 'week';
                          return Center(
                            child: Text(
                              isRestricted
                                  ? 'Nothing scheduled — your company only shows upcoming jobs ${_visibilityWindowLabel(identity.visibilityWindow)}.'
                                  : 'Nothing scheduled this month.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.mutedText, fontSize: 16),
                            ),
                          );
                        }

                        return _viewMode == _ScheduleViewMode.list
                            ? _ListView(
                                entries: visibleEntries,
                                dateKeyOf: _dateKey,
                                onTap: (entry) => _openEntry(identity.companyId, entry),
                              )
                            : _CalendarGridView(
                                visibleMonth: _visibleMonth,
                                entries: visibleEntries,
                                onDayTap: (entries) => _showDayEntries(identity.companyId, entries),
                              );
                      },
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

  Future<void> _showDayEntries(String companyId, List<ScheduleModel> entries) async {
    if (entries.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_monthLabel(_visibleMonth)} ${entries.first.startAt.day}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                ),
                const SizedBox(height: 12),
                ...entries.map((entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        entry.type == ScheduleType.job ? Icons.local_shipping_outlined : Icons.event_outlined,
                        color: AppTheme.blue,
                      ),
                      title: Text(entry.title),
                      subtitle: Text(entry.isAllDay ? 'All day' : '${_formatTime(entry.startAt)} - ${_formatTime(entry.endAt)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        _openEntry(companyId, entry);
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScheduleIdentity {
  final String companyId;
  final String userId;
  final bool canManageJobs;
  final bool canViewAllSchedule;
  final String visibilityWindow;

  const _ScheduleIdentity({
    required this.companyId,
    required this.userId,
    required this.canManageJobs,
    required this.canViewAllSchedule,
    required this.visibilityWindow,
  });
}

class _ListView extends StatelessWidget {
  final List<ScheduleModel> entries;
  final String Function(DateTime) dateKeyOf;
  final ValueChanged<ScheduleModel> onTap;

  const _ListView({required this.entries, required this.dateKeyOf, required this.onTap});

  String _formatTime(DateTime value) {
    final hour = value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final entriesByDate = <String, List<ScheduleModel>>{};
    for (final entry in entries) {
      entriesByDate.putIfAbsent(dateKeyOf(entry.startAt), () => []).add(entry);
    }

    final sortedDateKeys = entriesByDate.keys.toList()
      ..sort((a, b) {
        final aEntry = entriesByDate[a]!.first;
        final bEntry = entriesByDate[b]!.first;
        return aEntry.startAt.compareTo(bEntry.startAt);
      });

    return ListView.builder(
      itemCount: sortedDateKeys.length,
      itemBuilder: (context, index) {
        final key = sortedDateKeys[index];
        final dayEntries = entriesByDate[key]!;
        final day = dayEntries.first.startAt;

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${day.month}/${day.day}/${day.year}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.mutedText),
              ),
              const SizedBox(height: 8),
              ...dayEntries.map((entry) => _ScheduleEntryCard(
                    entry: entry,
                    timeLabel: entry.isAllDay ? 'All day' : '${_formatTime(entry.startAt)} - ${_formatTime(entry.endAt)}',
                    onTap: () => onTap(entry),
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _CalendarGridView extends StatelessWidget {
  final DateTime visibleMonth;
  final List<ScheduleModel> entries;
  final ValueChanged<List<ScheduleModel>> onDayTap;

  const _CalendarGridView({required this.visibleMonth, required this.entries, required this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final entriesByDay = <int, List<ScheduleModel>>{};
    for (final entry in entries) {
      entriesByDay.putIfAbsent(entry.startAt.day, () => []).add(entry);
    }

    final firstOfMonth = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday % 7; // Sunday-first grid

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final dayEntries = entriesByDay[day] ?? [];
      final hasEntries = dayEntries.isNotEmpty;
      final now = DateTime.now();
      final isToday = now.year == visibleMonth.year && now.month == visibleMonth.month && now.day == day;

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasEntries ? () => onDayTap(dayEntries) : null,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isToday ? AppTheme.blue.withOpacity(0.12) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isToday ? AppTheme.blue : Colors.grey.shade200),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: isToday ? AppTheme.blue : AppTheme.darkText,
                  ),
                ),
                if (hasEntries)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: AppTheme.blue, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        const Row(
          children: [
            _WeekdayLabel('S'), _WeekdayLabel('M'), _WeekdayLabel('T'),
            _WeekdayLabel('W'), _WeekdayLabel('T'), _WeekdayLabel('F'), _WeekdayLabel('S'),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GridView.count(
            crossAxisCount: 7,
            childAspectRatio: 0.9,
            children: cells,
          ),
        ),
        const SizedBox(height: 8),
        const Text('Tap a day with a dot to see what\'s scheduled.', style: TextStyle(color: AppTheme.mutedText, fontSize: 12)),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.mutedText, fontSize: 12)),
      ),
    );
  }
}

class _ScheduleEntryCard extends StatelessWidget {
  final ScheduleModel entry;
  final String timeLabel;
  final VoidCallback onTap;

  const _ScheduleEntryCard({required this.entry, required this.timeLabel, required this.onTap});

  IconData get _icon {
    switch (entry.type) {
      case ScheduleType.job:
        return Icons.local_shipping_outlined;
      case ScheduleType.meeting:
        return Icons.groups_outlined;
      default:
        return Icons.event_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(_icon, color: AppTheme.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                    Text(timeLabel, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13)),
                  ],
                ),
              ),
              if (entry.isDraft)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(999)),
                  child: const Text('Draft', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.mutedText)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
