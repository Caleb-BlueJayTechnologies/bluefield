import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/company_settings_model.dart';
import '../Models/correction_request_model.dart';
import '../Models/employee_model.dart';
import '../Models/job_model.dart';
import '../Models/membership.dart';
import '../Models/notification_model.dart';
import '../Models/time_entry_model.dart';
import 'company_settings_service.dart';
import 'kill_switch_service.dart';
import 'notification_service.dart';
import 'permission_service.dart';

/// Handles clock in/out, active-entry lookups, manual time edits, and
/// correction requests.
///
/// This replaces a much larger old implementation that had to guess at
/// an employee's identity by trying five different possible field names
/// (userId, employeeUserId, email, employeeEmail...) and guess at job
/// assignment by checking four different possible list field names, plus
/// a hand-rolled flexible date-string parser for job dates. None of that
/// guessing is needed anymore: EmployeeModel.employeeId is always equal
/// to the Firebase Auth UID (see employee_model.dart), and JobModel
/// always stores real Timestamps (see job_model.dart) — so lookups here
/// are direct doc reads instead of heuristic search.
/// Thrown by clockIn when the company's geofence mode is 'lenient',
/// the position given is outside the configured zone, and the caller
/// hasn't already confirmed they want to proceed anyway. The UI
/// should catch this specifically, show an "are you sure?" dialog,
/// and retry the same clockIn call with confirmedOutsideZone: true.
class GeofenceConfirmationRequiredException implements Exception {
  final double distanceMeters;
  const GeofenceConfirmationRequiredException(this.distanceMeters);

  @override
  String toString() =>
      'You are ${distanceMeters.round()}m from the clock-in zone. Confirm to clock in anyway.';
}

class TimeEntryService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final CompanySettingsService _settingsService;
  final NotificationService _notificationService;
  final KillSwitchService _killSwitchService;

  TimeEntryService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    CompanySettingsService? settingsService,
    NotificationService? notificationService,
    KillSwitchService? killSwitchService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _settingsService = settingsService ?? CompanySettingsService(),
        _notificationService = notificationService ?? NotificationService(),
        _killSwitchService = killSwitchService ?? KillSwitchService();

  User? get currentUser => _auth.currentUser;

  /// Great-circle distance between two points in meters. Accurate
  /// enough for a "how far from the job site" check at this scale —
  /// no need for anything more precise than the Haversine formula.
  static double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180);

  /// Pure read, no side effects — lets the UI decide what to show
  /// (nothing, a block message, a confirmation dialog) before
  /// actually attempting to clock in. hasZone is false if the company
  /// hasn't set one yet, in which case no check should happen at all.
  Future<({bool hasZone, double? distanceMeters, bool isWithinRadius})> checkGeofenceStatus({
    required String companyId,
    required double latitude,
    required double longitude,
  }) async {
    final settings = await _settingsService.getCompanySettings(companyId);
    if (!settings.hasClockInZone) {
      return (hasZone: false, distanceMeters: null, isWithinRadius: true);
    }

    final distance = _distanceMeters(
      latitude,
      longitude,
      settings.clockInZoneLatitude!,
      settings.clockInZoneLongitude!,
    );
    return (hasZone: true, distanceMeters: distance, isWithinRadius: distance <= settings.geofenceRadiusMeters);
  }

  /// Every active owner/manager in the company — the notification
  /// recipient list for an outside-zone clock-in/out.
  Future<List<String>> _managersAndOwners(String companyId) async {
    final snapshot = await _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships)
        .where(FSFields.role, whereIn: [FSRoles.owner, FSRoles.manager])
        .where(FSFields.status, isEqualTo: FSMembershipStatus.active)
        .get();
    return snapshot.docs.map((d) => d.id).toList();
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in.');
    }
    return user;
  }

  CollectionReference<Map<String, dynamic>> _timeEntriesRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeEntries);
  }

  CollectionReference<Map<String, dynamic>> _correctionRequestsRef(
    String companyId,
  ) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.correctionRequests);
  }

  // --- Identity / company resolution ---

  Future<String> getCurrentCompanyId() async {
    final user = _requireUser();
    final userDoc =
        await _firestore.collection(FSCollections.users).doc(user.uid).get();
    final data = userDoc.data();

    if (data == null) {
      throw Exception('User document was not found.');
    }

    final companyId = data['activeCompanyId']?.toString().trim() ?? '';
    if (companyId.isEmpty) {
      throw Exception('User is not linked to a company.');
    }
    return companyId;
  }

  /// Fetches and validates the current user's membership in [companyId].
  /// Throws if there's no membership, or if it's not active (archived /
  /// suspended memberships must not be able to clock in).
  Future<MembershipModel> getCurrentMembership(String companyId) async {
    final user = _requireUser();
    final doc = await _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships)
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      throw Exception('You do not have access to this company.');
    }

    final membership = MembershipModel.fromSnapshot(doc);
    if (!membership.grantsAccess) {
      throw Exception('Your access to this company is not active.');
    }
    return membership;
  }

  /// Direct doc read — employeeId is always the user's UID, so there's
  /// no searching required. Returns null only if the employee profile
  /// hasn't been created yet (shouldn't normally happen post-onboarding).
  Future<EmployeeModel?> getCurrentEmployeeProfile(String companyId) async {
    final user = _requireUser();
    final doc = await _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.employees)
        .doc(user.uid)
        .get();

    final data = doc.data();
    if (data == null) return null;
    return EmployeeModel.fromSnapshot(doc);
  }

  // --- Company settings passthrough (see company_settings_service.dart) ---

  Future<CompanySettingsModel> getCurrentCompanySettings() async {
    final companyId = await getCurrentCompanyId();
    return _settingsService.getCompanySettings(companyId);
  }

  Future<CompanySettingsModel> getCompanySettings(String companyId) {
    return _settingsService.getCompanySettings(companyId.trim());
  }

  Stream<CompanySettingsModel> watchCurrentCompanySettings() async* {
    final companyId = await getCurrentCompanyId();
    yield* _settingsService.watchCompanySettings(companyId);
  }

  Stream<CompanySettingsModel> watchCompanySettings(String companyId) {
    return _settingsService.watchCompanySettings(companyId.trim());
  }

  Future<bool> isClockInOutEnabled({String? companyId}) async {
    final id = companyId ?? await getCurrentCompanyId();
    final settings = await _settingsService.getCompanySettings(id);
    return _settingsService.isClockInOutEnabled(settings);
  }

  Future<void> requireClockInOutEnabled({String? companyId}) async {
    final id = companyId ?? await getCurrentCompanyId();
    final settings = await _settingsService.getCompanySettings(id);
    _settingsService.requireClockInOutEnabled(settings);
  }

  // --- Today's assigned jobs (for the clock-in job picker) ---

  /// Jobs scheduled for today that this employee could plausibly clock
  /// into — assigned directly, or assigned via their crew. Returned for
  /// the UI to present as a picker; clockIn() itself no longer guesses.
  Future<List<JobModel>> getTodaysAssignedJobs(String companyId) async {
    final user = _requireUser();
    final employee = await getCurrentEmployeeProfile(companyId);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final snapshot = await _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.jobs)
        .where(FSFields.status, whereIn: [
      FSJobStatus.scheduled,
      FSJobStatus.inProgress,
    ]).get();

    final jobs = snapshot.docs.map((d) => JobModel.fromSnapshot(d));

    return jobs.where((job) {
      final jobStart = DateTime(
        job.startDate.year,
        job.startDate.month,
        job.startDate.day,
      );
      final jobEnd = DateTime(
        job.endDate.year,
        job.endDate.month,
        job.endDate.day,
      );
      final coversToday =
          !today.isBefore(jobStart) && !today.isAfter(jobEnd);
      if (!coversToday) return false;

      final assignedDirectly = job.assignedEmployeeIds.contains(user.uid);
      final assignedViaCrew = employee?.hasCrew == true &&
          employee!.crewIds.any((c) => job.assignedCrewIds.contains(c));

      return assignedDirectly || assignedViaCrew;
    }).toList();
  }

  // --- Active entry watching ---

  Stream<TimeEntryModel?> watchActiveClockEntry({
    required String companyId,
    required String employeeId,
  }) {
    return _timeEntriesRef(companyId)
        .where(FSFields.employeeId, isEqualTo: employeeId)
        .where(FSFields.clockOutAt, isNull: true)
        .limit(1)
        .snapshots()
        .map((snap) =>
            snap.docs.isEmpty ? null : TimeEntryModel.fromSnapshot(snap.docs.first));
  }

  Stream<List<TimeEntryModel>> watchActiveCompanyClockEntries(
    String companyId,
  ) {
    return _timeEntriesRef(companyId)
        .where(FSFields.clockOutAt, isNull: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TimeEntryModel.fromSnapshot(d)).toList());
  }

  /// Who's currently on break — meaning clocked IN right now (their
  /// shift never ends for a break, see startBreak/endBreak below) with
  /// an active, unended entry in [BreakEntry] within that entry's
  /// breaks list. A simple filter over watchActiveCompanyClockEntries,
  /// now that breaks no longer clock anyone out.
  Stream<List<TimeEntryModel>> watchEmployeesOnBreak(String companyId) {
    return watchActiveCompanyClockEntries(companyId)
        .map((entries) => entries.where((e) => e.isOnBreak).toList());
  }

  // --- Clock in / out ---

  Future<void> clockIn({
    String? jobId,
    String? crewId,
    double? latitude,
    double? longitude,
    bool confirmedOutsideZone = false,
    String? notes,
  }) async {
    final user = _requireUser();
    final companyId = await getCurrentCompanyId();

    // Platform-wide emergency switch, distinct from the per-company
    // clock-in/out toggle requireClockInOutEnabled checks just below —
    // this one's for a platform admin to instantly stop new clock-ins
    // for every company at once during an incident, without needing a
    // deploy. See KillSwitchModel's doc comment.
    if (await _killSwitchService.isKilled('timeClockIn')) {
      throw Exception('Clock-in is temporarily disabled. Please try again shortly.');
    }

    await requireClockInOutEnabled(companyId: companyId);
    await getCurrentMembership(companyId); // throws if access isn't active

    final activeSnapshot = await _timeEntriesRef(companyId)
        .where(FSFields.employeeId, isEqualTo: user.uid)
        .where(FSFields.clockOutAt, isNull: true)
        .limit(1)
        .get();

    if (activeSnapshot.docs.isNotEmpty) {
      throw Exception('You are already clocked in.');
    }

    var isOutsideZone = false;
    if (latitude != null && longitude != null) {
      final settings = await _settingsService.getCompanySettings(companyId);
      final mode = settings.clockInGeofenceMode;

      if (mode != 'off' && settings.hasClockInZone) {
        final status = await checkGeofenceStatus(companyId: companyId, latitude: latitude, longitude: longitude);
        if (!status.isWithinRadius) {
          isOutsideZone = true;

          if (mode == 'strict') {
            throw Exception(
                'You are ${status.distanceMeters!.round()}m from the clock-in zone. Clock-in is blocked outside the zone.');
          }

          if (mode == 'lenient' && !confirmedOutsideZone) {
            throw GeofenceConfirmationRequiredException(status.distanceMeters!);
          }
        }
      }
    }

    final clockInLocation = (latitude != null && longitude != null) ? '$latitude,$longitude' : null;

    final entryRef = _timeEntriesRef(companyId).doc();
    await entryRef.set(TimeEntryModel.toMapForClockIn(
      companyId: companyId,
      employeeId: user.uid,
      jobId: jobId,
      crewId: crewId,
      clockInLocation: clockInLocation,
      notes: notes,
    ));

    if (isOutsideZone) {
      await entryRef.update({'isOutsideGeofenceAtClockIn': true});
      try {
        final recipients = await _managersAndOwners(companyId);
        final employee = await _firestore
            .collection(FSCollections.companies)
            .doc(companyId)
            .collection(FSCompanySub.employees)
            .doc(user.uid)
            .get();
        final employeeName = employee.data()?['firstName']?.toString() ?? 'An employee';
        await _notificationService.notifyMultipleUsers(
          companyId: companyId,
          userIds: recipients,
          type: NotificationType.companyAlert,
          title: 'Clock-in outside zone',
          body: '$employeeName clocked in outside the configured clock-in zone.',
          relatedId: entryRef.id,
        );
      } catch (_) {
        // The clock-in itself already succeeded above — a failed
        // notification shouldn't undo or block that.
      }
    }
  }

  Future<void> clockOut({
    required String companyId,
    required String timeEntryId,
    double? latitude,
    double? longitude,
  }) async {
    final user = _requireUser();
    final normalizedCompanyId = companyId.trim();
    final normalizedEntryId = timeEntryId.trim();

    if (normalizedCompanyId.isEmpty) {
      throw Exception('A company ID is required.');
    }
    if (normalizedEntryId.isEmpty) {
      throw Exception('A time entry ID is required.');
    }

    final currentCompanyId = await getCurrentCompanyId();
    if (currentCompanyId != normalizedCompanyId) {
      throw Exception('This time entry does not belong to your active company.');
    }

    await requireClockInOutEnabled(companyId: normalizedCompanyId);

    final entryRef = _timeEntriesRef(normalizedCompanyId).doc(normalizedEntryId);
    final entryDoc = await entryRef.get();

    if (!entryDoc.exists) {
      throw Exception('Clock entry was not found.');
    }

    final entry = TimeEntryModel.fromSnapshot(entryDoc);

    if (entry.employeeId != user.uid) {
      throw Exception('You cannot clock out another employee from this screen.');
    }

    if (!entry.isActive) {
      throw Exception('This time entry is no longer active.');
    }

    if (entry.isLocked) {
      throw Exception('This time entry belongs to a locked pay period.');
    }

    // Clock-out never blocks on geofence, by design — being unable to
    // end a shift would be a real problem if someone genuinely can't
    // get back to the zone. This only ever notifies.
    var isOutsideZone = false;
    if (latitude != null && longitude != null) {
      final settings = await _settingsService.getCompanySettings(normalizedCompanyId);
      if (settings.clockOutGeofenceEnabled && settings.hasClockInZone) {
        final status = await checkGeofenceStatus(companyId: normalizedCompanyId, latitude: latitude, longitude: longitude);
        isOutsideZone = !status.isWithinRadius;
      }
    }

    final clockOutLocation = (latitude != null && longitude != null) ? '$latitude,$longitude' : null;

    // Clocking out never traps someone mid-break — if a break was left
    // running, it's closed out here rather than blocking the clock-out
    // or silently leaving an open-ended break on a completed shift.
    final activeBreak = entry.activeBreak;
    final closedBreaks = activeBreak == null
        ? entry.breaks
        : entry.breaks
            .map((b) => identical(b, activeBreak) ? b.copyWith(endedAt: DateTime.now()) : b)
            .toList();

    await entryRef.update({
      FSFields.clockOutAt: FieldValue.serverTimestamp(),
      'clockOutLocation': clockOutLocation,
      // isBreak is never written true anymore — breaks are tracked via
      // the breaks list below without ending the entry at all. The
      // field is kept only so historical entries from before this
      // change still read correctly.
      'isBreak': false,
      'isOutsideGeofenceAtClockOut': isOutsideZone,
      'breaks': closedBreaks.map((b) => b.toMap()).toList(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    if (isOutsideZone) {
      try {
        final recipients = await _managersAndOwners(normalizedCompanyId);
        final employee = await _firestore
            .collection(FSCollections.companies)
            .doc(normalizedCompanyId)
            .collection(FSCompanySub.employees)
            .doc(user.uid)
            .get();
        final employeeName = employee.data()?['firstName']?.toString() ?? 'An employee';
        await _notificationService.notifyMultipleUsers(
          companyId: normalizedCompanyId,
          userIds: recipients,
          type: NotificationType.companyAlert,
          title: 'Clock-out outside zone',
          body: '$employeeName clocked out outside the configured clock-in zone.',
          relatedId: entryRef.id,
        );
      } catch (_) {
        // The clock-out itself already succeeded above.
      }
    }
  }

  // --- Breaks ---
  //
  // A break never clocks anyone out — clockInAt/clockOutAt on the
  // shift's entry are untouched by starting or ending one. Instead a
  // BreakEntry gets appended to that same entry's breaks list, so the
  // "time running" the employee sees keeps counting straight through
  // it (still working from the same clockInAt), while management can
  // still see exactly when breaks happened and whether they were paid.

  Future<void> startBreak({
    required String companyId,
    required String timeEntryId,
    required bool isPaid,
  }) async {
    final user = _requireUser();
    final settings = await _settingsService.getCompanySettings(companyId);
    _settingsService.requireBreaksEnabled(settings);

    final entryRef = _timeEntriesRef(companyId).doc(timeEntryId);
    final entryDoc = await entryRef.get();
    if (!entryDoc.exists) {
      throw Exception('Clock entry was not found.');
    }

    final entry = TimeEntryModel.fromSnapshot(entryDoc);
    if (entry.employeeId != user.uid) {
      throw Exception('You cannot start a break on another employee\'s clock entry.');
    }
    if (!entry.isActive) {
      throw Exception('You must be clocked in to start a break.');
    }
    if (entry.isOnBreak) {
      throw Exception('You are already on a break.');
    }

    final updatedBreaks = [
      ...entry.breaks,
      BreakEntry(startedAt: DateTime.now(), isPaid: isPaid),
    ];

    await entryRef.update({
      'breaks': updatedBreaks.map((b) => b.toMap()).toList(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> endBreak({
    required String companyId,
    required String timeEntryId,
  }) async {
    final user = _requireUser();

    final entryRef = _timeEntriesRef(companyId).doc(timeEntryId);
    final entryDoc = await entryRef.get();
    if (!entryDoc.exists) {
      throw Exception('Clock entry was not found.');
    }

    final entry = TimeEntryModel.fromSnapshot(entryDoc);
    if (entry.employeeId != user.uid) {
      throw Exception('You cannot end a break on another employee\'s clock entry.');
    }

    final activeBreak = entry.activeBreak;
    if (activeBreak == null) {
      throw Exception('You are not currently on a break.');
    }

    final updatedBreaks = entry.breaks
        .map((b) => identical(b, activeBreak) ? b.copyWith(endedAt: DateTime.now()) : b)
        .toList();

    await entryRef.update({
      'breaks': updatedBreaks.map((b) => b.toMap()).toList(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Manual edits (management only — permission check is the caller's job) ---

  Future<void> editTimeEntry({
    required String companyId,
    required String timeEntryId,
    required String editedByUserId,
    required String editReason,
    DateTime? newClockInAt,
    DateTime? newClockOutAt,
  }) async {
    final entryRef = _timeEntriesRef(companyId).doc(timeEntryId);
    final entryDoc = await entryRef.get();

    if (!entryDoc.exists) {
      throw Exception('Time entry was not found.');
    }

    final entry = TimeEntryModel.fromSnapshot(entryDoc);

    // Was previously unguarded — any caller who could reach this
    // method could edit any entry, with only the calling screen's own
    // (manager-only) UI standing in the way. Two legitimate paths now:
    // manager-level permission, or self-edit on your own entry when
    // the company has explicitly turned that on.
    final membership = await getCurrentMembership(companyId);
    final isManagerLevel = PermissionService.roleHasPermission(membership.role, Permission.timeEditEntries);

    if (!isManagerLevel) {
      if (entry.employeeId != editedByUserId) {
        throw Exception('You can only edit your own time entries.');
      }
      final settings = await _settingsService.getCompanySettings(companyId);
      if (!settings.employeeSelfEditEnabled) {
        throw Exception('Self-editing your own time entries is not enabled for your company.');
      }
    }

    if (entry.isLocked) {
      throw Exception('This time entry belongs to a locked pay period.');
    }

    if (editReason.trim().isEmpty) {
      throw Exception('An edit reason is required.');
    }

    await entryRef.update({
      if (newClockInAt != null) FSFields.clockInAt: Timestamp.fromDate(newClockInAt),
      if (newClockOutAt != null) FSFields.clockOutAt: Timestamp.fromDate(newClockOutAt),
      'editedBy': editedByUserId,
      'editedAt': FieldValue.serverTimestamp(),
      'editReason': editReason.trim(),
      FSFields.originalValue: Timestamp.fromDate(entry.clockInAt),
      'originalClockOutAt':
          entry.clockOutAt != null ? Timestamp.fromDate(entry.clockOutAt!) : null,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Correction requests ---

  Stream<List<CorrectionRequestModel>> watchPendingCorrectionRequests(
    String companyId,
  ) {
    return _correctionRequestsRef(companyId)
        .where(FSFields.status, isEqualTo: FSCorrectionStatus.pending)
        .orderBy(FSFields.createdAt, descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => CorrectionRequestModel.fromSnapshot(d)).toList());
  }

  Stream<List<CorrectionRequestModel>> watchMyCorrectionRequests({
    required String companyId,
    required String employeeId,
  }) {
    return _correctionRequestsRef(companyId)
        .where(FSFields.employeeId, isEqualTo: employeeId)
        .orderBy(FSFields.createdAt, descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => CorrectionRequestModel.fromSnapshot(d)).toList());
  }

  Future<void> submitCorrectionRequest({
    required String companyId,
    required String employeeId,
    String? timeEntryId,
    required String requestType,
    DateTime? requestedClockInAt,
    DateTime? requestedClockOutAt,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception('Please explain what needs to be corrected.');
    }

    if (timeEntryId != null) {
      final existingPending = await _correctionRequestsRef(companyId)
          .where(FSFields.timeEntryId, isEqualTo: timeEntryId)
          .where(FSFields.status, isEqualTo: FSCorrectionStatus.pending)
          .limit(1)
          .get();

      if (existingPending.docs.isNotEmpty) {
        throw Exception(
            'There is already a pending correction request for this entry.');
      }
    }

    DateTime? originalClockInAt;
    DateTime? originalClockOutAt;

    if (timeEntryId != null) {
      final entryDoc = await _timeEntriesRef(companyId).doc(timeEntryId).get();
      if (entryDoc.exists) {
        final entry = TimeEntryModel.fromSnapshot(entryDoc);
        originalClockInAt = entry.clockInAt;
        originalClockOutAt = entry.clockOutAt;
      }
    }

    final requestRef = _correctionRequestsRef(companyId).doc();
    await requestRef.set(CorrectionRequestModel.toMapForCreate(
      companyId: companyId,
      employeeId: employeeId,
      timeEntryId: timeEntryId,
      requestType: requestType,
      requestedClockInAt: requestedClockInAt,
      requestedClockOutAt: requestedClockOutAt,
      reason: reason.trim(),
      originalClockInAt: originalClockInAt,
      originalClockOutAt: originalClockOutAt,
    ));

    if (timeEntryId != null) {
      await _timeEntriesRef(companyId).doc(timeEntryId).update({
        'hasPendingCorrectionRequest': true,
      });
    }
  }

  Future<void> reviewCorrectionRequest({
    required String companyId,
    required String requestId,
    required String reviewerUserId,
    required bool approve,
    String? reviewNotes,
  }) async {
    // Was previously unguarded here — reachable by anyone who could
    // call this method, with only correction_requests_screen.dart's UI
    // gate standing in the way. Re-checked the same way editTimeEntry
    // re-checks its own caller, rather than trusting the screen.
    final user = _requireUser();
    if (user.uid != reviewerUserId) {
      throw Exception('You cannot review a correction request as someone else.');
    }
    final reviewerMembership = await getCurrentMembership(companyId);
    if (!PermissionService.roleHasPermission(reviewerMembership.role, Permission.timeApproveCorrections)) {
      throw Exception('You do not have permission to review correction requests.');
    }

    final requestRef = _correctionRequestsRef(companyId).doc(requestId);

    // Everything below runs inside one transaction so that (a) two
    // concurrent approvals of the same pending request — a double tap,
    // or two managers acting at once — can't both pass the isPending
    // check and each create their own duplicate time entry for a
    // missing-clock-out request, and (b) the pending->approved status
    // flip and the entry write it triggers can never partially apply.
    await _firestore.runTransaction((transaction) async {
      final requestDoc = await transaction.get(requestRef);
      if (!requestDoc.exists) {
        throw Exception('Correction request was not found.');
      }

      final request = CorrectionRequestModel.fromSnapshot(requestDoc);
      if (!request.isPending) {
        throw Exception('This request has already been reviewed.');
      }

      DocumentReference<Map<String, dynamic>>? entryRef;
      TimeEntryModel? entry;
      if (request.timeEntryId != null) {
        entryRef = _timeEntriesRef(companyId).doc(request.timeEntryId);
        final entryDoc = await transaction.get(entryRef);
        if (entryDoc.exists) {
          entry = TimeEntryModel.fromSnapshot(entryDoc);
        }
      }

      // A locked entry belongs to a locked (likely already-exported)
      // pay period. Approving a correction against it would silently
      // rewrite hours payroll already ran with, bypassing the same
      // lock editTimeEntry enforces. The period must be reopened first.
      if (approve && entry != null && entry.isLocked) {
        throw Exception(
            'This time entry belongs to a locked pay period. Unlock the pay period before approving this correction.');
      }

      final newStatus =
          approve ? FSCorrectionStatus.approved : FSCorrectionStatus.rejected;

      transaction.update(requestRef, {
        FSFields.status: newStatus,
        FSFields.reviewedBy: reviewerUserId,
        FSFields.reviewedAt: FieldValue.serverTimestamp(),
        'reviewNotes': reviewNotes,
        if (approve) 'appliedClockInAt': request.requestedClockInAt != null
            ? Timestamp.fromDate(request.requestedClockInAt!)
            : null,
        if (approve) 'appliedClockOutAt': request.requestedClockOutAt != null
            ? Timestamp.fromDate(request.requestedClockOutAt!)
            : null,
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });

      if (entryRef != null) {
        if (approve) {
          transaction.update(entryRef, {
            if (request.requestedClockInAt != null)
              FSFields.clockInAt: Timestamp.fromDate(request.requestedClockInAt!),
            if (request.requestedClockOutAt != null)
              FSFields.clockOutAt: Timestamp.fromDate(request.requestedClockOutAt!),
            'editedBy': reviewerUserId,
            'editedAt': FieldValue.serverTimestamp(),
            'editReason': 'Approved correction request',
            if (request.originalClockInAt != null)
              FSFields.originalValue: Timestamp.fromDate(request.originalClockInAt!),
            if (request.originalClockOutAt != null)
              'originalClockOutAt': Timestamp.fromDate(request.originalClockOutAt!),
            'hasPendingCorrectionRequest': false,
            FSFields.updatedAt: FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(entryRef, {'hasPendingCorrectionRequest': false});
        }
      } else if (approve &&
          request.requestedClockInAt != null &&
          request.requestType != CorrectionRequestType.missingClockOut) {
        // No existing entry — create a brand-new one from the approved request.
        final newEntryRef = _timeEntriesRef(companyId).doc();
        transaction.set(
            newEntryRef,
            TimeEntryModel(
              timeEntryId: newEntryRef.id,
              companyId: companyId,
              employeeId: request.employeeId,
              clockInAt: request.requestedClockInAt!,
              clockOutAt: request.requestedClockOutAt,
              source: TimeEntrySource.correction,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ).toMap());
      }
    });
  }

  // --- Display helpers (kept for existing screens) ---

  String formatTime(DateTime? date) {
    if (date == null) return 'Unknown time';
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  String formatDuration(Duration? duration) {
    if (duration == null) return 'Unknown duration';
    final minutes = duration.inMinutes < 0 ? 0 : duration.inMinutes;
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours <= 0) return '$remainingMinutes min';
    return '${hours}h ${remainingMinutes}m';
  }
}
