import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/job_model.dart';
import '../Models/schedule_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/crew_service.dart';
import '../Services/job_service.dart';
import '../Services/permission_service.dart';
import '../Services/schedule_service.dart';
import '../theme/app_theme.dart';
import 'create_job_screen.dart';
import 'employer_job_details_screen.dart';
import 'job_details_screen.dart';
import 'job_history_screen.dart';

enum _ViewMode { list, byDate, calendar }

/// Combined Jobs + Schedule screen. These two features overlap enough
/// that keeping them as separate pages was more friction than value —
/// every active job already gets a mirrored schedule entry (see
/// job_service.dart's syncScheduleForJob), so "the list of jobs" and
/// "the calendar of jobs" are really two views onto the same
/// underlying work, not two separate concerns.
///
/// List mode stays backed by the richer JobModel stream (crew names,
/// search, full status detail) since schedule entries don't carry
/// customer/address/notes. By Date and Calendar modes are backed by
/// the schedule stream instead, since day-grouping and calendar-grid
/// rendering only need title/time/type, and that stream already
/// includes non-job entries (shifts, meetings) that a jobs-only view
/// never would.
class JobsScreen extends StatefulWidget {
  /// When true, shows the full company schedule regardless of the
  /// viewer's role (used by manager/employer dashboards that already
  /// know the viewer should see everything).
  final bool showAllJobs;

  const JobsScreen({super.key, this.showAllJobs = false});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final AuthService _authService = AuthService();
  final JobService _jobService = JobService();
  final CrewService _crewService = CrewService();
  final CompanySettingsService _settingsService = CompanySettingsService();
  final ScheduleService _scheduleService = ScheduleService();

  final _searchController = TextEditingController();
  String _searchText = '';
  _ViewMode _viewMode = _ViewMode.list;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isBackfilling = false;

  late Future<_JobsReferenceData> _referenceFuture;

  // Cached once per companyId/userId/visibilityWindow so the search
  // box's per-keystroke setState() doesn't tear down and resubscribe
  // this Firestore listener on every character typed.
  String? _jobsStreamKey;
  Stream<List<JobModel>>? _jobsStream;
  // Last value the broadcast stream below delivered, fed back in as
  // StreamBuilder's initialData. Broadcast streams never replay old
  // events to a new listener — without this, switching the List/By
  // Date/Calendar button away from List and back attaches a fresh
  // listener that gets no data until Firestore happens to push another
  // change, which reads as the list being stuck loading forever.
  List<JobModel>? _lastJobsData;

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_JobsReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final allCrews = await _crewService.getCrewsByCompany(companyId: companyId, includeArchived: true);
    final crewsById = {for (final c in allCrews) c.crewId: c};

    final settings = await _settingsService.getCompanySettings(companyId);

    return _JobsReferenceData(
      companyId: companyId,
      userId: profile.uid,
      crewsById: crewsById,
      canManageJobs: PermissionService.roleHasPermission(profile.role, Permission.jobsEdit),
      visibilityWindow: settings.jobVisibilityWindow,
    );
  }

  bool _matchesSearch(JobModel job, Map<String, CrewModel> crewsById) {
    if (_searchText.isEmpty) return true;
    final crewNames = job.assignedCrewIds.map((id) => crewsById[id]?.crewName ?? '').join(' ').toLowerCase();
    return job.title.toLowerCase().contains(_searchText) ||
        (job.customerName ?? '').toLowerCase().contains(_searchText) ||
        (job.jobLocation ?? '').toLowerCase().contains(_searchText) ||
        (job.customerAddress ?? '').toLowerCase().contains(_searchText) ||
        crewNames.contains(_searchText);
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

  Future<void> _runBackfill(_JobsReferenceData reference) async {
    setState(() => _isBackfilling = true);
    try {
      final count = await _jobService.backfillScheduleSync(
        companyId: reference.companyId,
        actingUserId: reference.userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Everything was already in sync.'
                : 'Calendar synced — $count change${count == 1 ? '' : 's'} made.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isBackfilling = false);
    }
  }

  Future<void> _openScheduleEntry(String companyId, ScheduleModel entry) async {
    if (entry.type == ScheduleType.job && entry.jobId != null) {
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Jobs & Schedule', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Job History',
            icon: const Icon(Icons.history_outlined),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const JobHistoryScreen()));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<_ViewMode>(
                segments: const [
                  ButtonSegment(value: _ViewMode.list, label: Text('List'), icon: Icon(Icons.view_list_outlined)),
                  ButtonSegment(value: _ViewMode.byDate, label: Text('By Date'), icon: Icon(Icons.event_note_outlined)),
                  ButtonSegment(value: _ViewMode.calendar, label: Text('Calendar'), icon: Icon(Icons.calendar_month_outlined)),
                ],
                selected: {_viewMode},
                onSelectionChanged: (selection) => setState(() => _viewMode = selection.first),
              ),
              const SizedBox(height: 14),
              if (_viewMode == _ViewMode.list)
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search active jobs...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                )
              else
                FutureBuilder<_JobsReferenceData>(
                  future: _referenceFuture,
                  builder: (context, refSnapshot) {
                    final reference = refSnapshot.data;
                    return Column(
                      children: [
                        if (reference != null && reference.canManageJobs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _isBackfilling ? null : () => _runBackfill(reference),
                                icon: _isBackfilling
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.sync, size: 18),
                                label: Text(_isBackfilling ? 'Syncing...' : 'Sync Existing Jobs'),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => setState(() {
                                _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                              }),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Text(
                                _monthLabel(_visibleMonth),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() {
                                _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
                              }),
                              icon: const Icon(Icons.chevron_right),
                            ),
                            TextButton(
                              onPressed: () {
                                final now = DateTime.now();
                                setState(() => _visibleMonth = DateTime(now.year, now.month));
                              },
                              child: const Text('Today'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<_JobsReferenceData>(
                  future: _referenceFuture,
                  builder: (context, refSnapshot) {
                    if (refSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (refSnapshot.hasError || !refSnapshot.hasData) {
                      return Center(
                        child: Text(
                          refSnapshot.error?.toString() ?? 'Unable to load jobs.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      );
                    }

                    final reference = refSnapshot.data!;

                    return _viewMode == _ViewMode.list
                        ? _buildJobsList(reference)
                        : _buildScheduleView(reference);
                  },
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<_JobsReferenceData>(
                future: _referenceFuture,
                builder: (context, refSnapshot) {
                  final reference = refSnapshot.data;
                  if (reference == null || !reference.canManageJobs) return const SizedBox.shrink();

                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateJobScreen()));
                      },
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Create Job'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Stream<List<JobModel>> _ensureJobsStream(_JobsReferenceData reference) {
    final key = '${reference.companyId}::${reference.userId}::${reference.visibilityWindow}';
    if (_jobsStreamKey != key || _jobsStream == null) {
      _jobsStreamKey = key;
      _lastJobsData = null;
      // asBroadcastStream() is required here, not just an optimization:
      // watchVisibleJobs() is an async* generator, which is a
      // single-subscription Stream by default — it can only ever be
      // listen()'d once in its lifetime, even after that listener
      // cancels. Switching the List/By Date/Calendar segmented button
      // away from List and back tears down and rebuilds this
      // StreamBuilder<JobModel> (different widget subtree in between),
      // so without this wrapper the second listen() on the same cached
      // stream instance throws "Bad state: Stream has already been
      // listened to." Broadcasting keeps the underlying Firestore
      // subscription alive across that teardown/rebuild instead of
      // trying to relisten to an exhausted single-subscription source.
      _jobsStream = _jobService
          .watchVisibleJobs(
            companyId: reference.companyId,
            requestingUserId: reference.userId,
            visibilityWindow: reference.visibilityWindow,
          )
          .asBroadcastStream()
          // Track the latest value so a StreamBuilder that gets
          // rebuilt (see above) can be seeded with it via initialData
          // instead of sitting on a spinner until the next Firestore
          // change happens to come in.
          .map((jobs) => _lastJobsData = jobs);
    }
    return _jobsStream!;
  }

  Widget _buildJobsList(_JobsReferenceData reference) {
    return StreamBuilder<List<JobModel>>(
      // Visibility-aware: owners/managers with jobs.viewAll see
      // everything, everyone else only sees jobs assigned to them
      // directly or via their crew. Live.
      stream: _ensureJobsStream(reference),
      initialData: _lastJobsData,
      builder: (context, jobsSnapshot) {
        if (jobsSnapshot.connectionState == ConnectionState.waiting && !jobsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (jobsSnapshot.hasError) {
          return Center(
            child: Text(jobsSnapshot.error.toString(), textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.mutedText)),
          );
        }

        final allJobs = jobsSnapshot.data ?? [];
        final activeJobs = allJobs.where((j) => j.isActive).toList()
          ..sort((a, b) => (a.startTime ?? a.startDate).compareTo(b.startTime ?? b.startDate));
        final filtered = activeJobs.where((j) => _matchesSearch(j, reference.crewsById)).toList();

        if (allJobs.isEmpty) {
          return const Center(
            child: Text('No jobs created yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
          );
        }
        if (activeJobs.isEmpty) {
          return const Center(
            child: Text(
              'No active jobs. Completed jobs are in Job History.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.mutedText, fontSize: 16),
            ),
          );
        }
        if (filtered.isEmpty) {
          return const Center(
            child: Text('No active jobs match your search.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
          );
        }

        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final job = filtered[index];
            final crewNames = job.assignedCrewIds.map((id) => reference.crewsById[id]?.crewName).whereType<String>().toList();

            return EmployerJobCard(
              job: job,
              crewLabel: crewNames.isEmpty ? 'Unassigned' : crewNames.join(', '),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EmployerJobDetailsScreen(jobData: {...job.toMap(), FSFields.jobId: job.jobId}),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildScheduleView(_JobsReferenceData reference) {
    final windowStart = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final windowEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0, 23, 59, 59);

    return StreamBuilder<List<ScheduleModel>>(
      stream: widget.showAllJobs
          ? _scheduleService.watchCompanySchedules(companyId: reference.companyId, windowStart: windowStart, windowEnd: windowEnd)
          : _scheduleService.watchVisibleSchedules(
              companyId: reference.companyId,
              requestingUserId: reference.userId,
              windowStart: windowStart,
              windowEnd: windowEnd,
            ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(snapshot.error.toString(), textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.mutedText)),
          );
        }

        final rawEntries = snapshot.data ?? [];
        final visibleEntries = (widget.showAllJobs ? rawEntries : rawEntries.where((e) => e.isPublished).toList())
          ..sort((a, b) => a.startAt.compareTo(b.startAt));

        if (visibleEntries.isEmpty) {
          return const Center(
            child: Text('Nothing scheduled this month.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
          );
        }

        return _viewMode == _ViewMode.byDate
            ? _DateGroupedList(entries: visibleEntries, onTap: (entry) => _openScheduleEntry(reference.companyId, entry))
            : _CalendarGridView(
                visibleMonth: _visibleMonth,
                entries: visibleEntries,
                onDayTap: (entries) => _showDayEntries(reference.companyId, entries),
              );
      },
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
                        _openScheduleEntry(companyId, entry);
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

class _JobsReferenceData {
  final String companyId;
  final String userId;
  final Map<String, CrewModel> crewsById;
  final bool canManageJobs;
  final String visibilityWindow;

  const _JobsReferenceData({
    required this.companyId,
    required this.userId,
    required this.crewsById,
    required this.canManageJobs,
    this.visibilityWindow = 'week',
  });
}

class EmployerJobCard extends StatelessWidget {
  final JobModel job;
  final String crewLabel;
  final VoidCallback onTap;

  const EmployerJobCard({super.key, required this.job, required this.crewLabel, required this.onTap});

  Color _statusColor(String status) {
    switch (status) {
      case FSJobStatus.inProgress:
        return const Color(0xFFE8F5E9);
      case FSJobStatus.scheduled:
        return const Color(0xFFFFF3E0);
      case FSJobStatus.cancelled:
        return const Color(0xFFFFEBEE);
      default:
        return const Color(0xFFEAF1F8);
    }
  }

  Color _iconColor(String status) {
    switch (status) {
      case FSJobStatus.inProgress:
        return const Color(0xFF2E7D32);
      case FSJobStatus.scheduled:
        return const Color(0xFFE65100);
      case FSJobStatus.cancelled:
        return const Color(0xFFC62828);
      default:
        return AppTheme.blue;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case FSJobStatus.draft:
        return 'Draft';
      case FSJobStatus.scheduled:
        return 'Scheduled';
      case FSJobStatus.inProgress:
        return 'In Progress';
      case FSJobStatus.completed:
        return 'Completed';
      case FSJobStatus.cancelled:
        return 'Cancelled';
      case FSJobStatus.archived:
        return 'Archived';
      default:
        return status;
    }
  }

  String _formatDateRange(JobModel job) {
    final start = job.startDate;
    final end = job.endDate;
    final dateText = job.isMultiDay
        ? '${start.month}/${start.day} - ${end.month}/${end.day}'
        : '${start.month}/${start.day}/${start.year}';

    if (job.isAllDay) return dateText;

    final startTime = job.startTime;
    if (startTime == null) return dateText;
    final hour = startTime.hour == 0 ? 12 : (startTime.hour > 12 ? startTime.hour - 12 : startTime.hour);
    final minute = startTime.minute.toString().padLeft(2, '0');
    final period = startTime.hour >= 12 ? 'PM' : 'AM';
    return '$dateText • $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(job.status);
    final iconColor = _iconColor(job.status);
    final address = job.jobLocation ?? job.customerAddress ?? 'No address';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: statusColor,
                child: Icon(Icons.local_shipping_outlined, color: iconColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                    ),
                    const SizedBox(height: 5),
                    Text(_formatDateRange(job), style: const TextStyle(color: AppTheme.mutedText)),
                    const SizedBox(height: 4),
                    Text(
                      job.hasAdditionalLocations
                          ? '$address • +${job.additionalJobLocations.length} more location${job.additionalJobLocations.length == 1 ? '' : 's'} • $crewLabel'
                          : '$address • $crewLabel',
                      style: const TextStyle(color: AppTheme.mutedText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  _statusLabel(job.status),
                  style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateGroupedList extends StatelessWidget {
  final List<ScheduleModel> entries;
  final ValueChanged<ScheduleModel> onTap;

  const _DateGroupedList({required this.entries, required this.onTap});

  String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

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
      entriesByDate.putIfAbsent(_dateKey(entry.startAt), () => []).add(entry);
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

  static const int _maxBarsPerCell = 3;

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    // Bucket every entry into EVERY day it spans, not just its start
    // day — a 3-day job used to only ever show up on day one.
    final entriesByDay = <int, List<ScheduleModel>>{};
    for (final entry in entries) {
      var cursor = DateTime(entry.startAt.year, entry.startAt.month, entry.startAt.day);
      final lastDay = DateTime(entry.endAt.year, entry.endAt.month, entry.endAt.day);
      while (!cursor.isAfter(lastDay)) {
        if (cursor.year == visibleMonth.year && cursor.month == visibleMonth.month) {
          entriesByDay.putIfAbsent(cursor.day, () => []).add(entry);
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    final firstOfMonth = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday % 7;

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final cellDate = DateTime(visibleMonth.year, visibleMonth.month, day);
      final dayEntries = entriesByDay[day] ?? [];
      final hasEntries = dayEntries.isNotEmpty;
      final now = DateTime.now();
      final isToday = now.year == visibleMonth.year && now.month == visibleMonth.month && now.day == day;

      final visibleBars = dayEntries.take(_maxBarsPerCell).toList();
      final overflowCount = dayEntries.length - visibleBars.length;

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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday ? AppTheme.blue : AppTheme.darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ...visibleBars.map((entry) {
                    // Rounded only at the entry's TRUE start/end day —
                    // square through any day it merely continues
                    // across. Consecutive days in the same week row
                    // then read as one continuous bar, same as Google
                    // Calendar's month view (which also only breaks a
                    // multi-day bar at week-row boundaries).
                    final isStartEdge = _isSameDate(cellDate, entry.startAt);
                    final isEndEdge = _isSameDate(cellDate, entry.endAt);

                    return Container(
                      margin: EdgeInsets.only(
                        left: isStartEdge ? 3 : 0,
                        right: isEndEdge ? 3 : 0,
                        bottom: 2,
                      ),
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.blue,
                        borderRadius: BorderRadius.horizontal(
                          left: isStartEdge ? const Radius.circular(3) : Radius.zero,
                          right: isEndEdge ? const Radius.circular(3) : Radius.zero,
                        ),
                      ),
                    );
                  }),
                  if (overflowCount > 0)
                    Text('+$overflowCount', style: const TextStyle(fontSize: 9, color: AppTheme.mutedText)),
                ],
              ),
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
            childAspectRatio: 0.75,
            children: cells,
          ),
        ),
        const SizedBox(height: 8),
        const Text('Tap a day with a bar to see what\'s scheduled.', style: TextStyle(color: AppTheme.mutedText, fontSize: 12)),
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
