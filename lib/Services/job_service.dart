import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/job_model.dart';
import '../Models/membership.dart';
import 'company_audit_log_service.dart';
import 'kill_switch_service.dart';
import 'messaging_service.dart';
import 'permission_service.dart';
import 'schedule_service.dart';

/// Job/work-order management (Section 7).
///
/// Scope note: reusable job TEMPLATES (save a job as a template, create
/// a job from one) are deferred out of this file — they weren't on the
/// Section 28 sellable-beta checklist, unlike visibility/multi-day/
/// assignment which are. [duplicateJob] below covers the "copy an
/// existing job" need in the meantime; true named templates get their
/// own model/service pass later without blocking beta readiness.
class JobService {
  final FirebaseFirestore _firestore;
  final ScheduleService _scheduleService;
  final MessagingService _messagingService;
  final CompanyAuditLogService _auditLogService;
  final KillSwitchService _killSwitchService;

  JobService({
    FirebaseFirestore? firestore,
    ScheduleService? scheduleService,
    MessagingService? messagingService,
    CompanyAuditLogService? auditLogService,
    KillSwitchService? killSwitchService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _scheduleService = scheduleService ?? ScheduleService(),
        _messagingService = messagingService ?? MessagingService(),
        _auditLogService = auditLogService ?? CompanyAuditLogService(),
        _killSwitchService = killSwitchService ?? KillSwitchService();

  /// Best-effort display name lookup for audit log readability.
  Future<String?> _fullNameForUser(String userId) async {
    final doc = await _firestore.collection(FSCollections.users).doc(userId).get();
    final data = doc.data();
    if (data == null) return null;
    final first = data['firstName']?.toString() ?? '';
    final last = data['lastName']?.toString() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? null : full;
  }

  /// Mirrors EmployeeModel's own backward-compatible crew reading —
  /// this file reads the raw employee doc map directly in a couple of
  /// spots rather than going through EmployeeModel, so it needs its
  /// own copy of the same "new crewIds array, or fall back to the old
  /// single crewId string" logic.
  List<String> _readCrewIdsFromDoc(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final list = data['crewIds'];
    if (list is List) {
      return list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    final legacy = data[FSFields.crewId]?.toString();
    if (legacy != null && legacy.trim().isNotEmpty) {
      return [legacy];
    }
    return const [];
  }

  /// Narrows an already-assigned-only job list down to a configurable
  /// look-ahead window, per the ticket asking for owner-configurable
  /// visibility (whole day / next job only / week / month) for
  /// employees and managers without jobs.viewAll.
  List<JobModel> _applyVisibilityWindow(List<JobModel> jobs, String window) {
    final now = DateTime.now();

    if (window == 'nextJob') {
      final upcoming = jobs.where((j) => !j.isTerminal).toList()
        ..sort((a, b) => (a.startTime ?? a.startDate).compareTo(b.startTime ?? b.startDate));
      return upcoming.isEmpty ? [] : [upcoming.first];
    }

    late DateTime windowEnd;
    switch (window) {
      case 'day':
        windowEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'month':
        windowEnd = now.add(const Duration(days: 30));
        break;
      case 'week':
      default:
        windowEnd = now.add(const Duration(days: 7));
        break;
    }
    final windowStart = DateTime(now.year, now.month, now.day);

    return jobs.where((j) => j.startDate.isBefore(windowEnd) && j.endDate.isAfter(windowStart.subtract(const Duration(seconds: 1)))).toList();
  }

  /// Combines a job's date-only startDate/endDate with its optional
  /// precise startTime/endTime into the full DateTimes a schedule
  /// entry needs. No time set means all-day, spanning the full date
  /// range at day granularity.
  ({DateTime startAt, DateTime endAt, bool isAllDay}) _scheduleWindowForJob({
    required DateTime startDate,
    required DateTime endDate,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    if (startTime == null) {
      return (
        startAt: DateTime(startDate.year, startDate.month, startDate.day),
        endAt: DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59),
        isAllDay: true,
      );
    }

    final resolvedEnd = endTime ?? startTime.add(const Duration(hours: 1));
    return (
      startAt: DateTime(startDate.year, startDate.month, startDate.day, startTime.hour, startTime.minute),
      endAt: DateTime(endDate.year, endDate.month, endDate.day, resolvedEnd.hour, resolvedEnd.minute),
      isAllDay: false,
    );
  }

  CollectionReference<Map<String, dynamic>> _jobsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.jobs);
  }

  CollectionReference<Map<String, dynamic>> _employeesRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.employees);
  }

  CollectionReference<Map<String, dynamic>> _membershipsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships);
  }

  Future<MembershipModel> _requirePermission({
    required String companyId,
    required String actingUserId,
    required String permissionKey,
  }) async {
    final doc = await _membershipsRef(companyId).doc(actingUserId).get();
    if (!doc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(doc);
    if (!membership.grantsAccess) {
      throw Exception('Your access to this company is not active.');
    }
    if (!PermissionService.roleHasPermission(membership.role, permissionKey)) {
      throw Exception('You do not have permission to do that.');
    }
    return membership;
  }

  // --- Read ---

  Future<JobModel?> getJob({
    required String companyId,
    required String jobId,
  }) async {
    final doc = await _jobsRef(companyId).doc(jobId).get();
    if (!doc.exists) return null;
    return JobModel.fromSnapshot(doc);
  }

  Stream<JobModel?> watchJob({
    required String companyId,
    required String jobId,
  }) {
    return _jobsRef(companyId)
        .doc(jobId)
        .snapshots()
        .map((doc) => doc.exists ? JobModel.fromSnapshot(doc) : null);
  }

  /// General-purpose query for management screens (job list, history,
  /// crew-details "assign job" picker). Owners/managers with
  /// jobs.viewAll only — employees should use [getJobsForEmployee]
  /// instead, which applies visibility filtering.
  ///
  /// Only the startDate<=onOrBeforeDate bound is applied server-side
  /// (a single inequality on the same field the query orders by, so it
  /// needs no composite index). onOrAfterDate is checked client-side
  /// against endDate afterward — combining inequality filters on two
  /// different fields (startDate and endDate together) is exactly the
  /// case where Firestore requires manual composite-index configuration
  /// rather than the usual one-click index creation, so it's simpler
  /// and more reliable to filter the smaller remainder in Dart.
  Future<List<JobModel>> queryJobs({
    required String companyId,
    List<String>? statuses,
    String? crewId,
    DateTime? onOrAfterDate,
    DateTime? onOrBeforeDate,
    int limit = 200,
  }) async {
    Query<Map<String, dynamic>> query = _jobsRef(companyId);

    if (statuses != null && statuses.isNotEmpty) {
      query = query.where(FSFields.status, whereIn: statuses);
    }
    if (crewId != null) {
      query = query.where('assignedCrewIds', arrayContains: crewId);
    }
    if (onOrBeforeDate != null) {
      query = query.where(FSFields.startDate,
          isLessThanOrEqualTo: Timestamp.fromDate(onOrBeforeDate));
    }

    query = query.orderBy(FSFields.startDate).limit(limit);

    final snapshot = await query.get();
    var jobs = snapshot.docs.map((d) => JobModel.fromSnapshot(d)).toList();

    if (onOrAfterDate != null) {
      jobs = jobs
          .where((j) => !j.endDate.isBefore(onOrAfterDate))
          .toList();
    }

    return jobs;

  }

  /// Jobs visible to a specific employee: assigned directly, OR assigned
  /// to their crew. Two separate array-contains queries merged and
  /// deduplicated — Firestore can't OR across two different array
  /// fields in one query. Unassigned/draft jobs are correctly excluded
  /// since they won't appear in either query.
  Future<List<JobModel>> getJobsForEmployee({
    required String companyId,
    required String employeeId,
    List<String> crewIds = const [],
  }) async {
    final directSnapshot = await _jobsRef(companyId)
        .where('assignedEmployeeIds', arrayContains: employeeId)
        .get();

    final directJobs = directSnapshot.docs.map((d) => JobModel.fromSnapshot(d));

    if (crewIds.isEmpty) {
      return directJobs.toList();
    }

    final byId = <String, JobModel>{for (final job in directJobs) job.jobId: job};

    // One query per crew (Firestore can't OR across array-contains
    // values), fired concurrently instead of awaited one at a time —
    // each query is independent, so there's no reason a crew list of
    // any real size should pay for N sequential round-trips.
    final crewSnapshots = await Future.wait(crewIds.map(
      (crewId) => _jobsRef(companyId).where('assignedCrewIds', arrayContains: crewId).get(),
    ));
    for (final crewSnapshot in crewSnapshots) {
      for (final d in crewSnapshot.docs) {
        final job = JobModel.fromSnapshot(d);
        byId[job.jobId] = job;
      }
    }
    return byId.values.toList();
  }

  /// Live version of [getVisibleJobs] — fetches the viewer's
  /// role/crewId once (roles rarely change mid-session, matching the
  /// pattern used elsewhere for reference data), then streams the raw
  /// jobs collection and re-applies the same visibility rule on every
  /// snapshot update. This is what jobs_screen.dart should use instead
  /// of the one-time Future version, so a newly created job (or a
  /// status/assignment change) shows up immediately without the user
  /// needing to pull-to-refresh or restart the app.
  Stream<List<JobModel>> watchVisibleJobs({
    required String companyId,
    required String requestingUserId,
    List<String>? statuses,
    String visibilityWindow = 'week',
  }) async* {
    final membershipDoc = await _membershipsRef(companyId).doc(requestingUserId).get();
    if (!membershipDoc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(membershipDoc);
    final canViewAll =
        PermissionService.roleHasPermission(membership.role, Permission.jobsViewAll);

    List<String> crewIds = const [];
    if (!canViewAll) {
      final employeeDoc = await _employeesRef(companyId).doc(requestingUserId).get();
      crewIds = _readCrewIdsFromDoc(employeeDoc.data());
    }

    yield* _jobsRef(companyId).snapshots().map((snapshot) {
      var jobs = snapshot.docs.map((d) => JobModel.fromSnapshot(d)).toList();

      if (!canViewAll) {
        jobs = jobs
            .where((j) =>
                j.assignedEmployeeIds.contains(requestingUserId) ||
                crewIds.any((c) => j.assignedCrewIds.contains(c)))
            .toList();

        // Owners with jobs.viewAll always see everything; this window
        // only narrows what an assigned-only viewer sees, per the
        // company's configured jobVisibilityWindow setting.
        jobs = _applyVisibilityWindow(jobs, visibilityWindow);
      }

      if (statuses != null && statuses.isNotEmpty) {
        jobs = jobs.where((j) => statuses.contains(j.status)).toList();
      }

      return jobs;
    });
  }

  /// Convenience entry point that applies the correct visibility rule
  /// for whoever is asking: owners and managers with jobs.viewAll get
  /// everything (optionally filtered), everyone else gets
  /// [getJobsForEmployee]'s assigned-only view.
  Future<List<JobModel>> getVisibleJobs({
    required String companyId,
    required String requestingUserId,
    List<String>? statuses,
  }) async {
    final membershipDoc =
        await _membershipsRef(companyId).doc(requestingUserId).get();
    if (!membershipDoc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(membershipDoc);

    if (PermissionService.roleHasPermission(
        membership.role, Permission.jobsViewAll)) {
      return queryJobs(companyId: companyId, statuses: statuses);
    }

    final employeeDoc = await _employeesRef(companyId).doc(requestingUserId).get();
    final crewIds = _readCrewIdsFromDoc(employeeDoc.data());

    final jobs = await getJobsForEmployee(
      companyId: companyId,
      employeeId: requestingUserId,
      crewIds: crewIds,
    );

    if (statuses == null || statuses.isEmpty) return jobs;
    return jobs.where((j) => statuses.contains(j.status)).toList();
  }

  // --- Create ---

  Future<String> createJob({
    required String companyId,
    required String actingUserId,
    required String title,
    String? description,
    String? notes,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? jobLocation,
    List<String> additionalJobLocations = const [],
    required DateTime startDate,
    required DateTime endDate,
    DateTime? startTime,
    DateTime? endTime,
    List<String> assignedCrewIds = const [],
    List<String> directEmployeeIds = const [],
    List<String> assignedVehicleIds = const [],
    List<String> assignedEquipmentIds = const [],
    String status = FSJobStatus.draft,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsCreate,
    );

    // Platform-wide emergency switch — lets a platform admin instantly
    // stop new jobs being created for every company at once during an
    // incident, without a deploy. See KillSwitchModel's doc comment.
    if (await _killSwitchService.isKilled('jobCreation')) {
      throw Exception('Creating jobs is temporarily disabled. Please try again shortly.');
    }

    if (title.trim().isEmpty) {
      throw Exception('A job title is required.');
    }
    if (!JobModel.isValidDateRange(startDate, endDate)) {
      throw Exception('End date cannot be before start date.');
    }

    final resolvedEmployeeIds = await _resolveDirectAssignments(
      companyId: companyId,
      assignedCrewIds: assignedCrewIds,
      directEmployeeIds: directEmployeeIds,
    );

    final jobRef = _jobsRef(companyId).doc();
    await jobRef.set(JobModel.toMapForCreate(
      companyId: companyId,
      title: title.trim(),
      description: description,
      notes: notes,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      customerAddress: customerAddress,
      jobLocation: jobLocation,
      additionalJobLocations: additionalJobLocations,
      startDate: startDate,
      endDate: endDate,
      startTime: startTime,
      endTime: endTime,
      assignedCrewIds: assignedCrewIds,
      assignedEmployeeIds: resolvedEmployeeIds,
      assignedVehicleIds: assignedVehicleIds,
      assignedEquipmentIds: assignedEquipmentIds,
      status: status,
      createdByUserId: actingUserId,
    ));

    final window = _scheduleWindowForJob(
      startDate: startDate,
      endDate: endDate,
      startTime: startTime,
      endTime: endTime,
    );
    await _scheduleService.syncScheduleForJob(
      companyId: companyId,
      jobId: jobRef.id,
      title: title.trim(),
      startAt: window.startAt,
      endAt: window.endAt,
      isAllDay: window.isAllDay,
      crewIds: assignedCrewIds,
      employeeIds: resolvedEmployeeIds,
      actingUserId: actingUserId,
    );

    return jobRef.id;
  }

  /// One-time utility for jobs that existed BEFORE syncScheduleForJob was
  /// wired into createJob/updateJobDetails/updateAssignments — those
  /// jobs never went through the code path that creates a schedule
  /// entry, so they're structurally missing from the calendar no
  /// matter how long you wait. Re-syncs every active (non-terminal)
  /// job's schedule entry in one pass. Safe to run more than once —
  /// syncScheduleForJob itself upserts by jobId, so already-synced jobs
  /// are just updated in place, not duplicated.
  ///
  /// Also runs the reverse repair: removes any job-linked schedule
  /// entry left behind for a job that's already completed/cancelled/
  /// archived (see ScheduleService.removeOrphanedTerminalJobSchedules).
  /// completeJob/cancelJob clean up after themselves immediately, but
  /// this is what "Sync Existing Jobs" uses to fix any that slipped
  /// through — including jobs completed before that cleanup logic
  /// existed — which is why a completed job could otherwise keep
  /// showing up in By Date/Calendar indefinitely.
  Future<int> backfillScheduleSync({
    required String companyId,
    required String actingUserId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsEdit,
    );

    final snapshot = await _jobsRef(companyId)
        .where(FSFields.status, whereIn: [FSJobStatus.scheduled, FSJobStatus.inProgress])
        .get();

    var syncedCount = 0;
    for (final doc in snapshot.docs) {
      final job = JobModel.fromSnapshot(doc);
      final window = _scheduleWindowForJob(
        startDate: job.startDate,
        endDate: job.endDate,
        startTime: job.startTime,
        endTime: job.endTime,
      );
      await _scheduleService.syncScheduleForJob(
        companyId: companyId,
        jobId: job.jobId,
        title: job.title,
        startAt: window.startAt,
        endAt: window.endAt,
        isAllDay: window.isAllDay,
        crewIds: job.assignedCrewIds,
        employeeIds: job.assignedEmployeeIds,
        actingUserId: actingUserId,
      );
      syncedCount++;
    }

    final removedCount = await _scheduleService.removeOrphanedTerminalJobSchedules(companyId: companyId);

    return syncedCount + removedCount;
  }

  /// Removes any directly-assigned employee who's already covered by one
  /// of the assigned crews, so the stored assignedEmployeeIds list never
  /// double-counts someone (Section 7: "avoid duplicate employees when
  /// selecting an entire crew and individuals").
  Future<List<String>> _resolveDirectAssignments({
    required String companyId,
    required List<String> assignedCrewIds,
    required List<String> directEmployeeIds,
  }) async {
    if (assignedCrewIds.isEmpty || directEmployeeIds.isEmpty) {
      return directEmployeeIds;
    }

    final crewMembersSnapshot = await _employeesRef(companyId)
        .where(FSFields.crewId, whereIn: assignedCrewIds)
        .get();
    final crewMemberIds =
        crewMembersSnapshot.docs.map((d) => d.id).toSet();

    return JobModel.dedupeDirectAssignments(
      directEmployeeIds: directEmployeeIds,
      employeeIdsInAssignedCrews: crewMemberIds,
    );
  }

  // --- Update ---

  Future<void> updateJobDetails({
    required String companyId,
    required String actingUserId,
    required String jobId,
    String? title,
    String? description,
    String? notes,
    bool clearCustomer = false,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    bool clearLocation = false,
    String? jobLocation,
    List<String>? additionalJobLocations,
    DateTime? startDate,
    DateTime? endDate,
    bool clearTimes = false,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsEdit,
    );

    if (startDate != null && endDate != null &&
        !JobModel.isValidDateRange(startDate, endDate)) {
      throw Exception('End date cannot be before start date.');
    }

    final updates = <String, dynamic>{
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
    if (title != null) {
      if (title.trim().isEmpty) throw Exception('A job title is required.');
      updates['title'] = title.trim();
    }
    if (description != null) updates['description'] = description;
    if (notes != null) updates['notes'] = notes;
    if (clearCustomer) {
      updates['customerName'] = null;
      updates['customerPhone'] = null;
      updates['customerEmail'] = null;
      updates['customerAddress'] = null;
    } else {
      if (customerName != null) updates['customerName'] = customerName;
      if (customerPhone != null) updates['customerPhone'] = customerPhone;
      if (customerEmail != null) updates['customerEmail'] = customerEmail;
      if (customerAddress != null) updates['customerAddress'] = customerAddress;
    }
    if (clearLocation) {
      updates['jobLocation'] = null;
      updates['additionalJobLocations'] = <String>[];
    } else {
      if (jobLocation != null) updates['jobLocation'] = jobLocation;
      if (additionalJobLocations != null) {
        updates['additionalJobLocations'] =
            additionalJobLocations.take(JobModel.maxAdditionalLocations).toList();
      }
    }
    if (startDate != null) updates[FSFields.startDate] = Timestamp.fromDate(startDate);
    if (endDate != null) updates[FSFields.endDate] = Timestamp.fromDate(endDate);
    if (clearTimes) {
      updates['startTime'] = null;
      updates['endTime'] = null;
    } else {
      if (startTime != null) updates['startTime'] = Timestamp.fromDate(startTime);
      if (endTime != null) updates['endTime'] = Timestamp.fromDate(endTime);
    }

    await _jobsRef(companyId).doc(jobId).update(updates);

    final refreshed = await getJob(companyId: companyId, jobId: jobId);
    if (refreshed != null) {
      final window = _scheduleWindowForJob(
        startDate: refreshed.startDate,
        endDate: refreshed.endDate,
        startTime: refreshed.startTime,
        endTime: refreshed.endTime,
      );
      await _scheduleService.syncScheduleForJob(
        companyId: companyId,
        jobId: jobId,
        title: refreshed.title,
        startAt: window.startAt,
        endAt: window.endAt,
        isAllDay: window.isAllDay,
        crewIds: refreshed.assignedCrewIds,
        employeeIds: refreshed.assignedEmployeeIds,
        actingUserId: actingUserId,
      );
    }
  }

  Future<void> updateAssignments({
    required String companyId,
    required String actingUserId,
    required String jobId,
    required List<String> assignedCrewIds,
    required List<String> directEmployeeIds,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsAssignEmployees,
    );

    final resolvedEmployeeIds = await _resolveDirectAssignments(
      companyId: companyId,
      assignedCrewIds: assignedCrewIds,
      directEmployeeIds: directEmployeeIds,
    );

    await _jobsRef(companyId).doc(jobId).update({
      'assignedCrewIds': assignedCrewIds,
      'assignedEmployeeIds': resolvedEmployeeIds,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    final refreshed = await getJob(companyId: companyId, jobId: jobId);
    if (refreshed != null) {
      final window = _scheduleWindowForJob(
        startDate: refreshed.startDate,
        endDate: refreshed.endDate,
        startTime: refreshed.startTime,
        endTime: refreshed.endTime,
      );
      await _scheduleService.syncScheduleForJob(
        companyId: companyId,
        jobId: jobId,
        title: refreshed.title,
        startAt: window.startAt,
        endAt: window.endAt,
        isAllDay: window.isAllDay,
        crewIds: assignedCrewIds,
        employeeIds: resolvedEmployeeIds,
        actingUserId: actingUserId,
      );

      // If this job already has a message thread (someone opened
      // "Message" before this assignment change), keep its
      // participants in sync — otherwise anyone newly assigned here
      // stays permanently locked out of a thread that already exists,
      // since thread creation only ever builds the participant list
      // once, at creation time.
      if (refreshed.conversationThreadId != null) {
        await _messagingService.syncJobThreadParticipants(
          companyId: companyId,
          threadId: refreshed.conversationThreadId!,
          assignedEmployeeIds: resolvedEmployeeIds,
          assignedCrewIds: assignedCrewIds,
        );
      }
    }
  }

  /// Sets the job's full vehicle list at once — same reasoning as
  /// assignEquipment: a picker UI lets someone select several at
  /// once, so this replaces the whole list rather than one at a time.
  Future<void> assignVehicles({
    required String companyId,
    required String actingUserId,
    required String jobId,
    required List<String> vehicleIds,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.vehiclesAssign,
    );

    await _jobsRef(companyId).doc(jobId).update({
      'assignedVehicleIds': vehicleIds,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  /// Sets the job's full equipment list at once — a picker UI lets
  /// someone select several items in one go, so this replaces the
  /// whole list rather than adding/removing one at a time like a
  /// single-vehicle assignment would.
  Future<void> assignEquipment({
    required String companyId,
    required String actingUserId,
    required String jobId,
    required List<String> equipmentIds,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.equipmentAssign,
    );

    await _jobsRef(companyId).doc(jobId).update({
      'assignedEquipmentIds': equipmentIds,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Status transitions ---

  Future<void> _setStatus({
    required String companyId,
    required String jobId,
    required String newStatus,
    required String changedByUserId,
    Map<String, dynamic> extraFields = const {},
  }) async {
    String? oldStatus;
    String? jobTitle;
    try {
      final beforeDoc = await _jobsRef(companyId).doc(jobId).get();
      if (beforeDoc.exists) {
        final before = JobModel.fromSnapshot(beforeDoc);
        oldStatus = before.status;
        jobTitle = before.title;
      }
    } catch (_) {
      // Non-critical — the status update below still proceeds even if
      // this lookup fails.
    }

    await _jobsRef(companyId).doc(jobId).update({
      FSFields.status: newStatus,
      FSFields.statusChangedAt: FieldValue.serverTimestamp(),
      FSFields.statusChangedBy: changedByUserId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
      ...extraFields,
    });

    try {
      final actorName = await _fullNameForUser(changedByUserId) ?? changedByUserId;
      await _auditLogService.record(
        companyId: companyId,
        actorUserId: changedByUserId,
        actorName: actorName,
        action: 'jobStatusChanged',
        targetType: 'job',
        targetId: jobId,
        targetName: jobTitle ?? jobId,
        oldValue: oldStatus,
        newValue: newStatus,
      );
    } catch (_) {
      // The status change itself already succeeded above.
    }
  }

  /// Moves a draft job to scheduled (i.e. published/visible to assigned
  /// staff). Employees only ever see scheduled/inProgress/completed jobs
  /// through [getJobsForEmployee] since draft jobs simply won't be
  /// something they'd normally be assigned to yet — enforce "don't show
  /// drafts to employees" at the screen level regardless.
  Future<void> publishJob({
    required String companyId,
    required String actingUserId,
    required String jobId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsEdit,
    );
    await _setStatus(
      companyId: companyId,
      jobId: jobId,
      newStatus: FSJobStatus.scheduled,
      changedByUserId: actingUserId,
    );
  }

  Future<void> startJob({
    required String companyId,
    required String actingUserId,
    required String jobId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsEdit,
    );
    await _setStatus(
      companyId: companyId,
      jobId: jobId,
      newStatus: FSJobStatus.inProgress,
      changedByUserId: actingUserId,
    );
  }

  Future<void> cancelJob({
    required String companyId,
    required String actingUserId,
    required String jobId,
    required String reason,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsCancel,
    );

    if (reason.trim().isEmpty) {
      throw Exception('A cancellation reason is required.');
    }

    final job = await getJob(companyId: companyId, jobId: jobId);
    if (job == null) throw Exception('Job was not found.');
    if (job.isTerminal) {
      throw Exception('This job is already ${job.status} and cannot be cancelled.');
    }

    await _setStatus(
      companyId: companyId,
      jobId: jobId,
      newStatus: FSJobStatus.cancelled,
      changedByUserId: actingUserId,
      extraFields: {
        'cancellationReason': reason.trim(),
        'cancelledBy': actingUserId,
        'cancelledAt': FieldValue.serverTimestamp(),
      },
    );

    await _scheduleService.removeScheduleForJob(companyId: companyId, jobId: jobId);
  }

  /// True if this job needs the stronger multi-day confirmation dialog
  /// before completing — the screen should show:
  /// "Complete this multi-day job? This job is scheduled through
  /// [endDate]. Completing it now will close the job and remove it from
  /// all remaining scheduled days." per Section 7's suggested copy.
  bool requiresMultiDayCompletionWarning(JobModel job) => job.isMultiDay;

  /// Marks the job completed. This is a single status change on the one
  /// job record — since a multi-day job is never split into per-day
  /// documents, there's no risk of "only completing today's copy" by
  /// construction. The screen is responsible for showing
  /// [requiresMultiDayCompletionWarning]'s confirmation first.
  Future<void> completeJob({
    required String companyId,
    required String actingUserId,
    required String jobId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsComplete,
    );

    final job = await getJob(companyId: companyId, jobId: jobId);
    if (job == null) throw Exception('Job was not found.');
    if (job.isTerminal) {
      throw Exception('This job is already ${job.status}.');
    }

    await _setStatus(
      companyId: companyId,
      jobId: jobId,
      newStatus: FSJobStatus.completed,
      changedByUserId: actingUserId,
      extraFields: {
        'completedBy': actingUserId,
        'completedAt': FieldValue.serverTimestamp(),
      },
    );

    // Job History is the record for completed work — Schedule shouldn't
    // keep showing something that's already done.
    await _scheduleService.removeScheduleForJob(companyId: companyId, jobId: jobId);
  }

  Future<void> reopenJob({
    required String companyId,
    required String actingUserId,
    required String jobId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsReopen,
    );

    final job = await getJob(companyId: companyId, jobId: jobId);
    if (job == null) throw Exception('Job was not found.');
    if (!job.isTerminal) {
      throw Exception('Only completed or cancelled jobs can be reopened.');
    }

    await _setStatus(
      companyId: companyId,
      jobId: jobId,
      newStatus: FSJobStatus.scheduled,
      changedByUserId: actingUserId,
      extraFields: {
        'reopenedBy': actingUserId,
        'reopenedAt': FieldValue.serverTimestamp(),
      },
    );

    // Restore its calendar presence — it was removed when the job
    // completed/was cancelled, and reopening puts it back into active
    // work.
    final window = _scheduleWindowForJob(
      startDate: job.startDate,
      endDate: job.endDate,
      startTime: job.startTime,
      endTime: job.endTime,
    );
    await _scheduleService.syncScheduleForJob(
      companyId: companyId,
      jobId: jobId,
      title: job.title,
      startAt: window.startAt,
      endAt: window.endAt,
      isAllDay: window.isAllDay,
      crewIds: job.assignedCrewIds,
      employeeIds: job.assignedEmployeeIds,
      actingUserId: actingUserId,
    );
  }

  // --- Duplication ---

  Future<String> duplicateJob({
    required String companyId,
    required String actingUserId,
    required String sourceJobId,
    required DateTime newStartDate,
    required DateTime newEndDate,
    bool copyCustomer = true,
    bool copyAssignments = true,
    bool copyNotes = true,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.jobsDuplicate,
    );

    final source = await getJob(companyId: companyId, jobId: sourceJobId);
    if (source == null) throw Exception('Source job was not found.');

    if (!JobModel.isValidDateRange(newStartDate, newEndDate)) {
      throw Exception('End date cannot be before start date.');
    }

    final jobRef = _jobsRef(companyId).doc();
    await jobRef.set(JobModel.toMapForCreate(
      companyId: companyId,
      title: source.title,
      description: source.description,
      notes: copyNotes ? source.notes : null,
      customerName: copyCustomer ? source.customerName : null,
      customerPhone: copyCustomer ? source.customerPhone : null,
      customerEmail: copyCustomer ? source.customerEmail : null,
      customerAddress: copyCustomer ? source.customerAddress : null,
      jobLocation: source.jobLocation,
      startDate: newStartDate,
      endDate: newEndDate,
      assignedCrewIds: copyAssignments ? source.assignedCrewIds : const [],
      assignedEmployeeIds:
          copyAssignments ? source.assignedEmployeeIds : const [],
      assignedVehicleIds: copyAssignments ? source.assignedVehicleIds : const [],
      assignedEquipmentIds: copyAssignments ? source.assignedEquipmentIds : const [],
      status: FSJobStatus.draft,
      createdByUserId: actingUserId,
    ));

    return jobRef.id;
  }
}

