import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/schedule_model.dart';
import '../Services/auth_service.dart';
import '../Services/job_service.dart';
import '../Services/schedule_service.dart';
import '../theme/app_theme.dart';
import 'job_details_screen.dart';

class CalendarScheduleScreen extends StatefulWidget {
  const CalendarScheduleScreen({super.key});

  @override
  State<CalendarScheduleScreen> createState() => _CalendarScheduleScreenState();
}

class _CalendarScheduleScreenState extends State<CalendarScheduleScreen> {
  final AuthService _authService = AuthService();
  final ScheduleService _scheduleService = ScheduleService();
  final JobService _jobService = JobService();

  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<_CalendarIdentity> _identityFuture;

  @override
  void initState() {
    super.initState();
    _identityFuture = _loadIdentity();
  }

  Future<_CalendarIdentity> _loadIdentity() async {
    final profile = await _authService.getCurrentUserProfile();
    return _CalendarIdentity(companyId: profile.activeCompanyId, userId: profile.uid);
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

  Future<void> _showDayEntries(String companyId, Map<int, List<ScheduleModel>> entriesByDay, int day) async {
    final entries = entriesByDay[day] ?? [];
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
                  '${_monthLabel(_visibleMonth)} $day',
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
                      onTap: () async {
                        Navigator.pop(context);
                        if (entry.type == ScheduleType.job && entry.jobId != null) {
                          final job = await _jobService.getJob(companyId: companyId, jobId: entry.jobId!);
                          if (job == null || !mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => JobDetailsScreen(jobData: {...job.toMap(), FSFields.jobId: job.jobId}),
                            ),
                          );
                        }
                      },
                    )),
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Calendar View', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<_CalendarIdentity>(
        future: _identityFuture,
        builder: (context, identitySnapshot) {
          if (identitySnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (identitySnapshot.hasError || !identitySnapshot.hasData) {
            return Center(
              child: Text(
                identitySnapshot.error?.toString() ?? 'Unable to load calendar.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.mutedText),
              ),
            );
          }

          final identity = identitySnapshot.data!;
          final windowStart = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
          final windowEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0, 23, 59, 59);

          return StreamBuilder<List<ScheduleModel>>(
            // Same visibility rule as schedule_screen.dart, live:
            // owners/managers with schedule.viewAll see everything,
            // everyone else only sees entries assigned to them or
            // their crew, and drafts never reach them.
            stream: _scheduleService.watchVisibleSchedules(
              companyId: identity.companyId,
              requestingUserId: identity.userId,
              windowStart: windowStart,
              windowEnd: windowEnd,
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

              final entries = snapshot.data ?? [];
              final entriesByDay = <int, List<ScheduleModel>>{};
              for (final entry in entries) {
                if (!entry.isPublished) continue;
                entriesByDay.putIfAbsent(entry.startAt.day, () => []).add(entry);
              }

              final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
              final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
              final leadingBlanks = firstOfMonth.weekday % 7; // Sunday-first grid

              final cells = <Widget>[];
              for (var i = 0; i < leadingBlanks; i++) {
                cells.add(const SizedBox.shrink());
              }
              for (var day = 1; day <= daysInMonth; day++) {
                final hasEntries = (entriesByDay[day] ?? []).isNotEmpty;
                final isToday = DateTime.now().year == _visibleMonth.year &&
                    DateTime.now().month == _visibleMonth.month &&
                    DateTime.now().day == day;

                cells.add(
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: hasEntries ? () => _showDayEntries(identity.companyId, entriesByDay, day) : null,
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

              return Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(onPressed: _previousMonth, icon: const Icon(Icons.chevron_left)),
                        Expanded(
                          child: Text(
                            _monthLabel(_visibleMonth),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                          ),
                        ),
                        IconButton(onPressed: _nextMonth, icon: const Icon(Icons.chevron_right)),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CalendarIdentity {
  final String companyId;
  final String userId;

  const _CalendarIdentity({required this.companyId, required this.userId});
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
