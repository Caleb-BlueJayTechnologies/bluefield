import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/job_model.dart';
import '../Models/membership.dart';
import '../Models/schedule_model.dart';
import '../Models/time_off_request_model.dart';
import 'permission_service.dart';

/// A single detected scheduling conflict, for the UI to display as a
/// warning. Conflicts are informational, not blocking — Section 6 is
/// explicit that the system should warn, not silently prevent, unless a
/// company's own settings say otherwise (that override check happens at
/// the screen/settings layer, not here).
class ScheduleConflict {
  final String description;
  final String conflictingScheduleId;

  const ScheduleConflict({
    required this.description,
    required this.conflictingScheduleId,
  });
}

class ScheduleService {
  final FirebaseFirestore _firestore;

  ScheduleService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _schedulesRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.schedules);
  }

  /// Mirrors EmployeeModel's own backward-compatible crew reading —
  /// this file reads the raw employee doc map directly rather than
  /// going through EmployeeModel, so it needs its own copy of the
  /// same "new crewIds array, or fall back to the old single crewId
  /// string" logic.
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

  CollectionReference<Map<String, dynamic>> _timeOffRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeOffRequests);
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

  Future<ScheduleModel?> getSchedule({
    required String companyId,
    required String scheduleId,
  }) async {
    final doc = await _schedulesRef(companyId).doc(scheduleId).get();
    if (!doc.exists) return null;
    return ScheduleModel.fromSnapshot(doc);
  }

  Stream<ScheduleModel?> watchSchedule({
    required String companyId,
    required String scheduleId,
  }) {
    return _schedulesRef(companyId)
        .doc(scheduleId)
        .snapshots()
        .map((doc) => doc.exists ? ScheduleModel.fromSnapshot(doc) : null);
  }

  /// Management view: every schedule (draft and published) in a date
  /// window — day/week/month/list views all just pick the window size.
  ///
  /// Only filters server-side by startAt <= windowEnd (a single
  /// inequality, needs no composite index). The true overlap check
  /// (endAt >= windowStart) happens client-side below — Firestore's
  /// support for inequality filters on two different fields in one
  /// query needs manual composite-index configuration rather than the
  /// usual one-click index creation, so it's simpler and more reliable
  /// to just filter the smaller remainder in Dart, same as
  /// getSchedulesForEmployee already does further down this file.
  Future<List<ScheduleModel>> queryCompanySchedules({
    required String companyId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final snapshot = await _schedulesRef(companyId)
        .where(FSFields.startAt,
            isLessThanOrEqualTo: Timestamp.fromDate(windowEnd))
        .orderBy(FSFields.startAt)
        .get();

    final entries = snapshot.docs.map((d) => ScheduleModel.fromSnapshot(d));

    return entries.where((s) => s.endAt.isAfter(windowStart)).toList();
  }

  /// Live version of [queryCompanySchedules] — same single-inequality-
  /// then-client-filter approach (see that method's comment for why:
  /// avoids Firestore's dual-different-field-inequality index problem).
  Stream<List<ScheduleModel>> watchCompanySchedules({
    required String companyId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    return _schedulesRef(companyId)
        .where(FSFields.startAt, isLessThanOrEqualTo: Timestamp.fromDate(windowEnd))
        .orderBy(FSFields.startAt)
        .snapshots()
        .map((snapshot) {
      final entries = snapshot.docs.map((d) => ScheduleModel.fromSnapshot(d));
      return entries.where((s) => s.endAt.isAfter(windowStart)).toList();
    });
  }

  /// Employee view: only PUBLISHED entries assigned directly to them or
  /// to their crew, within a date window. Drafts never reach employees.
  Future<List<ScheduleModel>> getSchedulesForEmployee({
    required String companyId,
    required String employeeId,
    List<String> crewIds = const [],
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final directSnapshot = await _schedulesRef(companyId)
        .where('employeeIds', arrayContains: employeeId)
        .where(FSFields.status, isEqualTo: ScheduleStatus.published)
        .get();

    var results = directSnapshot.docs.map((d) => ScheduleModel.fromSnapshot(d));

    if (crewIds.isNotEmpty) {
      final byId = <String, ScheduleModel>{for (final s in results) s.scheduleId: s};
      // One query per crew — Firestore can't OR across multiple
      // array-contains values in a single query, so each crew the
      // employee belongs to needs its own lookup, merged by ID after.
      // Fired concurrently rather than awaited one at a time since the
      // queries are independent of each other.
      final crewSnapshots = await Future.wait(crewIds.map(
        (crewId) => _schedulesRef(companyId)
            .where('crewIds', arrayContains: crewId)
            .where(FSFields.status, isEqualTo: ScheduleStatus.published)
            .get(),
      ));
      for (final crewSnapshot in crewSnapshots) {
        for (final d in crewSnapshot.docs) {
          final s = ScheduleModel.fromSnapshot(d);
          byId[s.scheduleId] = s;
        }
      }
      results = byId.values;
    }

    return results
        .where((s) => s.startAt.isBefore(windowEnd) && s.endAt.isAfter(windowStart))
        .toList();
  }

  /// Applies the correct visibility rule automatically, same pattern as
  /// JobService.getVisibleJobs: owners/managers with schedule.viewAll
  /// get the full company view; everyone else gets the assigned-only
  /// employee view.
  Future<List<ScheduleModel>> getVisibleSchedules({
    required String companyId,
    required String requestingUserId,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final membershipDoc =
        await _membershipsRef(companyId).doc(requestingUserId).get();
    if (!membershipDoc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(membershipDoc);

    if (PermissionService.roleHasPermission(
        membership.role, Permission.scheduleViewAll)) {
      return queryCompanySchedules(
        companyId: companyId,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
    }

    final employeeDoc = await _employeesRef(companyId).doc(requestingUserId).get();
    final crewIds = _readCrewIdsFromDoc(employeeDoc.data());

    return getSchedulesForEmployee(
      companyId: companyId,
      employeeId: requestingUserId,
      crewIds: crewIds,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );
  }

  /// Live version of [getVisibleSchedules] — same pattern as
  /// JobService.watchVisibleJobs: fetches the viewer's role/crewId
  /// once, then streams the raw schedules collection and re-applies
  /// visibility + the date-window overlap check on every snapshot
  /// update. This is what schedule_screen.dart and
  /// calendar_schedule_screen.dart should use instead of the one-time
  /// Future version, so a newly created job's linked schedule entry
  /// (or a manually created shift/meeting) shows up immediately.
  Stream<List<ScheduleModel>> watchVisibleSchedules({
    required String companyId,
    required String requestingUserId,
    required DateTime windowStart,
    required DateTime windowEnd,
    String visibilityWindow = 'week',
  }) async* {
    final membershipDoc = await _membershipsRef(companyId).doc(requestingUserId).get();
    if (!membershipDoc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(membershipDoc);
    final canViewAll =
        PermissionService.roleHasPermission(membership.role, Permission.scheduleViewAll);

    List<String> crewIds = const [];
    if (!canViewAll) {
      final employeeDoc = await _employeesRef(companyId).doc(requestingUserId).get();
      crewIds = _readCrewIdsFromDoc(employeeDoc.data());
    }

    yield* _schedulesRef(companyId).snapshots().map((snapshot) {
      var entries = snapshot.docs.map((d) => ScheduleModel.fromSnapshot(d)).toList();

      if (!canViewAll) {
        entries = entries
            .where((s) =>
                s.status == ScheduleStatus.published &&
                (s.employeeIds.contains(requestingUserId) ||
                    crewIds.any((c) => s.crewIds.contains(c))))
            .toList();

        // Same company-configurable cap JobService.watchVisibleJobs
        // already applies to the Jobs list (CompanySettingsModel.
        // jobVisibilityWindow) — without this, an employee/manager
        // without scheduleViewAll could set the setting to "day" on
        // the Jobs list yet still page the Schedule calendar forward
        // through every future month and see everything anyway, since
        // this stream previously only filtered by role/crew, never by
        // how far ahead the company allows a restricted viewer to look.
        entries = _applyVisibilityWindow(entries, visibilityWindow);
      }

      return entries
          .where((s) => s.startAt.isBefore(windowEnd) && s.endAt.isAfter(windowStart))
          .toList();
    });
  }

  /// Mirrors JobService's own _applyVisibilityWindow exactly (same
  /// window keys: nextJob/day/week/month/default), just against a
  /// ScheduleModel's startAt/endAt instead of a JobModel's
  /// startDate/endDate — kept as a separate copy rather than a shared
  /// helper since the two models don't share a common date-range type.
  List<ScheduleModel> _applyVisibilityWindow(List<ScheduleModel> entries, String window) {
    final now = DateTime.now();

    if (window == 'nextJob') {
      final upcoming = entries.where((s) => s.endAt.isAfter(now)).toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
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

    return entries
        .where((s) => s.startAt.isBefore(windowEnd) && s.endAt.isAfter(windowStart.subtract(const Duration(seconds: 1))))
        .toList();
  }

  /// Convenience for the employee dashboard's "Today's Schedule" card —
  /// the screen navigates to the existing Schedule tab and opens today
  /// rather than pushing a duplicate screen; this just supplies today's
  /// entries for whatever view renders it.
  Future<List<ScheduleModel>> getTodaysScheduleForEmployee({
    required String companyId,
    required String employeeId,
    List<String> crewIds = const [],
  }) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return getSchedulesForEmployee(
      companyId: companyId,
      employeeId: employeeId,
      crewIds: crewIds,
      windowStart: dayStart,
      windowEnd: dayEnd,
    );
  }

  /// Live version of [getTodaysScheduleForEmployee] — the employee
  /// dashboard's "Today's Schedule" card previously did a one-time
  /// Future fetch, so a newly published shift (or an edit to today's
  /// shift) made while the dashboard was already open didn't show up
  /// until the screen was reopened. Streams the raw schedules
  /// collection and re-applies the same employee/crew/published/
  /// today-window filter on every snapshot update — same pattern as
  /// [watchVisibleSchedules].
  Stream<List<ScheduleModel>> watchTodaysScheduleForEmployee({
    required String companyId,
    required String employeeId,
    List<String> crewIds = const [],
  }) {
    return _schedulesRef(companyId).snapshots().map((snapshot) {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final entries = snapshot.docs
          .map((d) => ScheduleModel.fromSnapshot(d))
          .where((s) =>
              s.status == ScheduleStatus.published &&
              (s.employeeIds.contains(employeeId) ||
                  crewIds.any((c) => s.crewIds.contains(c))));

      return entries
          .where((s) => s.startAt.isBefore(dayEnd) && s.endAt.isAfter(dayStart))
          .toList();
    });
  }

  // --- Create / update ---

  /// Keeps a job's calendar presence in sync with the job itself —
  /// this is the piece that was missing entirely: nothing previously
  /// wrote to the schedules collection when a job was created, so the
  /// Schedule tab (which only ever reads from `schedules`, never from
  /// `jobs` directly) stayed empty no matter how many jobs existed.
  /// Upserts by jobId so repeated calls (job edits) update the same
  /// schedule entry rather than creating duplicates. No independent
  /// permission check — the caller (JobService) has already verified
  /// the acting user's job-level permission for this action, and
  /// re-checking schedule.edit here could fail a legitimate job
  /// creator who doesn't happen to also hold that separate permission.
  Future<void> syncScheduleForJob({
    required String companyId,
    required String jobId,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    bool isAllDay = true,
    List<String> crewIds = const [],
    List<String> employeeIds = const [],
    required String actingUserId,
  }) async {
    final existing = await _schedulesRef(companyId)
        .where(FSFields.jobId, isEqualTo: jobId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final scheduleId = existing.docs.first.id;
      await _schedulesRef(companyId).doc(scheduleId).update({
        'title': title,
        'isAllDay': isAllDay,
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
        'crewIds': crewIds,
        'employeeIds': employeeIds,
        'lastEditedByUserId': actingUserId,
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    final scheduleRef = _schedulesRef(companyId).doc();
    await scheduleRef.set(ScheduleModel.toMapForCreate(
      companyId: companyId,
      title: title,
      isAllDay: isAllDay,
      startAt: startAt,
      endAt: endAt,
      type: ScheduleType.job,
      jobId: jobId,
      crewIds: crewIds,
      employeeIds: employeeIds,
      // Job-linked schedule entries publish immediately — a job that's
      // been assigned and scheduled is, by definition, no longer a
      // draft the way a hand-built shift might be.
      status: ScheduleStatus.published,
      createdByUserId: actingUserId,
    ));
  }

  /// Called when a job is completed or cancelled — removes its
  /// calendar presence rather than leaving a stale entry behind. Job
  /// History is the permanent record for completed work, so there's
  /// no reason for Schedule to keep showing it too. (Reopening a job
  /// restores its schedule entry — see JobService.reopenJob.)
  Future<void> removeScheduleForJob({
    required String companyId,
    required String jobId,
  }) async {
    final existing = await _schedulesRef(companyId)
        .where(FSFields.jobId, isEqualTo: jobId)
        .get();

    for (final doc in existing.docs) {
      await doc.reference.delete();
    }
  }

  /// Repair sweep: deletes any job-linked schedule entry whose
  /// underlying job has already gone terminal (completed, cancelled,
  /// or archived). completeJob/cancelJob normally remove their own
  /// schedule entry the moment the status change happens
  /// (removeScheduleForJob above), so this shouldn't normally find
  /// anything — it exists to catch entries that drifted out of sync
  /// (e.g. jobs completed before that removal logic existed, or a
  /// removal that failed partway) so a completed job doesn't keep
  /// showing up in By Date/Calendar indefinitely. Called by
  /// JobService.backfillScheduleSync ("Sync Existing Jobs").
  Future<int> removeOrphanedTerminalJobSchedules({
    required String companyId,
  }) async {
    final scheduleSnapshot =
        await _schedulesRef(companyId).where('type', isEqualTo: ScheduleType.job).get();

    final jobLinkedEntries = scheduleSnapshot.docs
        .map((d) => ScheduleModel.fromSnapshot(d))
        .where((s) => s.jobId != null)
        .toList();

    if (jobLinkedEntries.isEmpty) return 0;

    final jobIds = jobLinkedEntries.map((s) => s.jobId!).toSet().toList();
    final jobsRef = _firestore.collection(FSCollections.companies).doc(companyId).collection(FSCompanySub.jobs);

    // Firestore's whereIn caps at 30 values per query, same chunking
    // pattern used elsewhere in this file for per-crew lookups.
    final terminalJobIds = <String>{};
    for (var i = 0; i < jobIds.length; i += 30) {
      final chunk = jobIds.sublist(i, i + 30 > jobIds.length ? jobIds.length : i + 30);
      final jobsSnapshot = await jobsRef.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in jobsSnapshot.docs) {
        final job = JobModel.fromSnapshot(doc);
        if (job.isTerminal) terminalJobIds.add(job.jobId);
      }
      // A schedule entry can also be orphaned because the job it
      // pointed to was deleted outright — jobs are never hard-deleted
      // by this app (jobs.delete is disallowed), but defend against it
      // anyway rather than leaving a permanently-stale entry behind.
      final foundIds = jobsSnapshot.docs.map((d) => d.id).toSet();
      terminalJobIds.addAll(chunk.where((id) => !foundIds.contains(id)));
    }

    var removedCount = 0;
    for (final entry in jobLinkedEntries) {
      if (terminalJobIds.contains(entry.jobId)) {
        await _schedulesRef(companyId).doc(entry.scheduleId).delete();
        removedCount++;
      }
    }
    return removedCount;
  }

  Future<String> createSchedule({
    required String companyId,
    required String actingUserId,
    required String title,
    String? description,
    bool isAllDay = false,
    required DateTime startAt,
    required DateTime endAt,
    String type = ScheduleType.shift,
    String? jobId,
    List<String> crewIds = const [],
    List<String> employeeIds = const [],
    String status = ScheduleStatus.draft,
    bool conflictOverrideAcknowledged = false,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.scheduleEdit,
    );

    if (title.trim().isEmpty) {
      throw Exception('A schedule title is required.');
    }
    if (!ScheduleModel.isValidTimeRange(startAt, endAt)) {
      throw Exception('End time must be after start time.');
    }

    final scheduleRef = _schedulesRef(companyId).doc();
    await scheduleRef.set(ScheduleModel.toMapForCreate(
      companyId: companyId,
      title: title.trim(),
      description: description,
      isAllDay: isAllDay,
      startAt: startAt,
      endAt: endAt,
      type: type,
      jobId: jobId,
      crewIds: crewIds,
      employeeIds: employeeIds,
      status: status,
      conflictOverrideAcknowledged: conflictOverrideAcknowledged,
      createdByUserId: actingUserId,
    ));

    return scheduleRef.id;
  }

  Future<void> updateSchedule({
    required String companyId,
    required String actingUserId,
    required String scheduleId,
    String? title,
    String? description,
    bool? isAllDay,
    DateTime? startAt,
    DateTime? endAt,
    List<String>? crewIds,
    List<String>? employeeIds,
    bool? conflictOverrideAcknowledged,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.scheduleEdit,
    );

    if (startAt != null && endAt != null &&
        !ScheduleModel.isValidTimeRange(startAt, endAt)) {
      throw Exception('End time must be after start time.');
    }

    final updates = <String, dynamic>{
      'lastEditedByUserId': actingUserId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
    if (title != null) updates['title'] = title.trim();
    if (description != null) updates['description'] = description;
    if (isAllDay != null) updates['isAllDay'] = isAllDay;
    if (startAt != null) updates[FSFields.startAt] = Timestamp.fromDate(startAt);
    if (endAt != null) updates[FSFields.endAt] = Timestamp.fromDate(endAt);
    if (crewIds != null) updates['crewIds'] = crewIds;
    if (employeeIds != null) updates['employeeIds'] = employeeIds;
    if (conflictOverrideAcknowledged != null) {
      updates['conflictOverrideAcknowledged'] = conflictOverrideAcknowledged;
    }

    await _schedulesRef(companyId).doc(scheduleId).update(updates);
  }

  Future<void> deleteSchedule({
    required String companyId,
    required String actingUserId,
    required String scheduleId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.scheduleEdit,
    );
    await _schedulesRef(companyId).doc(scheduleId).delete();
  }

  /// Publishing is what actually notifies employees — see
  /// notification_service.dart (not built yet) for the actual push/
  /// in-app notification once it exists. The screen calling this should
  /// trigger that notification step after a successful publish.
  Future<void> publishSchedule({
    required String companyId,
    required String actingUserId,
    required String scheduleId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.schedulePublish,
    );

    await _schedulesRef(companyId).doc(scheduleId).update({
      FSFields.status: ScheduleStatus.published,
      'publishedAt': FieldValue.serverTimestamp(),
      'publishedBy': actingUserId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> moveToDraft({
    required String companyId,
    required String actingUserId,
    required String scheduleId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.schedulePublish,
    );

    await _schedulesRef(companyId).doc(scheduleId).update({
      FSFields.status: ScheduleStatus.draft,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Conflict detection ---

  /// Checks a proposed (or existing, via [excludeScheduleId]) time slot
  /// for overlaps: the same employee/crew double-booked on another
  /// schedule entry, or overlapping an approved time-off request. This
  /// warns — it never blocks on its own; the screen decides whether to
  /// require [ScheduleModel.conflictOverrideAcknowledged] before saving
  /// based on the company's own settings.
  Future<List<ScheduleConflict>> checkConflicts({
    required String companyId,
    required DateTime startAt,
    required DateTime endAt,
    List<String> employeeIds = const [],
    List<String> crewIds = const [],
    String? excludeScheduleId,
  }) async {
    final conflicts = <ScheduleConflict>[];

    // Widen the query window to the surrounding days so we don't miss
    // an overlap from a schedule entry that starts before/ends after
    // the proposed slot's own calendar day.
    final windowStart = DateTime(startAt.year, startAt.month, startAt.day)
        .subtract(const Duration(days: 1));
    final windowEnd = DateTime(endAt.year, endAt.month, endAt.day)
        .add(const Duration(days: 2));

    final nearby = await queryCompanySchedules(
      companyId: companyId,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );

    for (final other in nearby) {
      if (other.scheduleId == excludeScheduleId) continue;
      final overlaps = other.startAt.isBefore(endAt) && other.endAt.isAfter(startAt);
      if (!overlaps) continue;

      final sharedEmployees =
          other.employeeIds.toSet().intersection(employeeIds.toSet());
      final sharedCrews = other.crewIds.toSet().intersection(crewIds.toSet());

      if (sharedEmployees.isNotEmpty) {
        conflicts.add(ScheduleConflict(
          description:
              '${sharedEmployees.length} employee(s) already scheduled for "${other.title}" during this time.',
          conflictingScheduleId: other.scheduleId,
        ));
      }
      if (sharedCrews.isNotEmpty) {
        conflicts.add(ScheduleConflict(
          description: 'A shared crew is already scheduled for "${other.title}" during this time.',
          conflictingScheduleId: other.scheduleId,
        ));
      }
    }

    if (employeeIds.isNotEmpty) {
      final timeOffSnapshot = await _timeOffRef(companyId)
          .where(FSFields.employeeId, whereIn: employeeIds)
          .where(FSFields.status, isEqualTo: FSTimeOffStatus.approved)
          .get();

      for (final doc in timeOffSnapshot.docs) {
        final request = TimeOffRequestModel.fromSnapshot(doc);
        final requestEnd =
            request.endDate.add(const Duration(days: 1)); // date-only -> end of day
        final overlaps =
            request.startDate.isBefore(endAt) && requestEnd.isAfter(startAt);
        if (overlaps) {
          conflicts.add(ScheduleConflict(
            description: 'Overlaps approved time off for one or more assigned employees.',
            conflictingScheduleId: request.requestId,
          ));
        }
      }
    }

    return conflicts;
  }
}
