import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/membership.dart';
import '../Models/time_off_request_model.dart';
import 'company_settings_service.dart';
import 'permission_service.dart';

class TimeOffService {
  final FirebaseFirestore _firestore;
  final CompanySettingsService _settingsService;

  TimeOffService({
    FirebaseFirestore? firestore,
    CompanySettingsService? settingsService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _settingsService = settingsService ?? CompanySettingsService();

  CollectionReference<Map<String, dynamic>> _requestsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeOffRequests);
  }

  CollectionReference<Map<String, dynamic>> _membershipsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships);
  }

  Future<MembershipModel> _requireMembership({
    required String companyId,
    required String userId,
  }) async {
    final doc = await _membershipsRef(companyId).doc(userId).get();
    if (!doc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(doc);
    if (!membership.grantsAccess) {
      throw Exception('Your access to this company is not active.');
    }
    return membership;
  }

  Future<void> _requirePermission({
    required String companyId,
    required String actingUserId,
    required String permissionKey,
  }) async {
    final membership =
        await _requireMembership(companyId: companyId, userId: actingUserId);
    if (!PermissionService.roleHasPermission(membership.role, permissionKey)) {
      throw Exception('You do not have permission to do that.');
    }
  }

  DateTime _startOfDay(DateTime v) => DateTime(v.year, v.month, v.day);

  // --- Read (privacy-scoped) ---

  /// Employees only ever see their own request history — never other
  /// employees' approvals, rejections, reasons, or balances (Section 10
  /// privacy requirement).
  Future<List<TimeOffRequestModel>> getMyRequests({
    required String companyId,
    required String employeeId,
  }) async {
    final snapshot = await _requestsRef(companyId)
        .where(FSFields.employeeId, isEqualTo: employeeId)
        .orderBy(FSFields.createdAt, descending: true)
        .get();
    return snapshot.docs.map((d) => TimeOffRequestModel.fromSnapshot(d)).toList();
  }

  Stream<List<TimeOffRequestModel>> watchMyRequests({
    required String companyId,
    required String employeeId,
  }) {
    return _requestsRef(companyId)
        .where(FSFields.employeeId, isEqualTo: employeeId)
        .orderBy(FSFields.createdAt, descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TimeOffRequestModel.fromSnapshot(d)).toList());
  }

  /// Full team view — requires timeOff.viewTeam permission (owners and
  /// managers by default).
  Future<List<TimeOffRequestModel>> getTeamRequests({
    required String companyId,
    required String requestingUserId,
    String? status,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: requestingUserId,
      permissionKey: Permission.timeOffViewTeam,
    );

    Query<Map<String, dynamic>> query = _requestsRef(companyId);
    if (status != null) {
      query = query.where(FSFields.status, isEqualTo: status);
    }
    final snapshot = await query.orderBy(FSFields.createdAt, descending: true).get();
    return snapshot.docs.map((d) => TimeOffRequestModel.fromSnapshot(d)).toList();
  }

  Stream<List<TimeOffRequestModel>> watchPendingRequests({
    required String companyId,
  }) {
    return _requestsRef(companyId)
        .where(FSFields.status, isEqualTo: FSTimeOffStatus.pending)
        .orderBy(FSFields.createdAt, descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TimeOffRequestModel.fromSnapshot(d)).toList());
  }

  // --- Submit ---

  Future<String> submitTimeOffRequest({
    required String companyId,
    required String employeeId,
    required String leaveTypeId,
    required bool isFullDay,
    required DateTime startDate,
    required DateTime endDate,
    double? totalHours,
    String? reason,
    String? notes,
    bool scheduleConflictAcknowledged = false,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: employeeId,
      permissionKey: Permission.timeOffSubmit,
    );

    final settings = await _settingsService.getCompanySettings(companyId);
    _settingsService.requireTimeOffTypeEnabled(settings, leaveTypeId);

    final normalizedStart = _startOfDay(startDate);
    final normalizedEnd = _startOfDay(endDate);

    if (!TimeOffRequestModel.isValidDateRange(normalizedStart, normalizedEnd)) {
      throw Exception('End date cannot be before start date.');
    }

    // Default hours: standard 8-hour day × number of days, if the
    // caller didn't supply an explicit total (e.g. for a partial day).
    // This is a simple default, not a configurable policy yet — flagged
    // as an assumption rather than a real accrual/workday-length rule.
    final resolvedHours = totalHours ??
        (isFullDay
            ? (normalizedEnd.difference(normalizedStart).inDays + 1) * 8.0
            : null);

    final requestRef = _requestsRef(companyId).doc();
    await requestRef.set(TimeOffRequestModel.toMapForCreate(
      companyId: companyId,
      employeeId: employeeId,
      leaveTypeId: leaveTypeId,
      isFullDay: isFullDay,
      startDate: normalizedStart,
      endDate: normalizedEnd,
      totalHours: resolvedHours,
      reason: reason,
      notes: notes,
      scheduleConflictAcknowledged: scheduleConflictAcknowledged,
    ));

    return requestRef.id;
  }

  // --- Approve / reject (pending -> terminal) ---

  Future<void> approveRequest({
    required String companyId,
    required String reviewerUserId,
    required String requestId,
    String? reviewNotes,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: reviewerUserId,
      permissionKey: Permission.timeOffApprove,
    );

    final requestRef = _requestsRef(companyId).doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(requestRef);
      if (!doc.exists) throw Exception('Time off request was not found.');
      final request = TimeOffRequestModel.fromSnapshot(doc);

      if (!request.isPending) {
        throw Exception('Only pending requests can be approved.');
      }

      transaction.update(requestRef, {
        FSFields.status: FSTimeOffStatus.approved,
        'reviewedByUserId': reviewerUserId,
        FSFields.reviewedAt: FieldValue.serverTimestamp(),
        'reviewNotes': reviewNotes,
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectRequest({
    required String companyId,
    required String reviewerUserId,
    required String requestId,
    String? reviewNotes,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: reviewerUserId,
      permissionKey: Permission.timeOffReject,
    );

    final requestRef = _requestsRef(companyId).doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(requestRef);
      if (!doc.exists) throw Exception('Time off request was not found.');
      final request = TimeOffRequestModel.fromSnapshot(doc);

      if (!request.isPending) {
        throw Exception('Only pending requests can be rejected.');
      }

      transaction.update(requestRef, {
        FSFields.status: FSTimeOffStatus.rejected,
        'reviewedByUserId': reviewerUserId,
        FSFields.reviewedAt: FieldValue.serverTimestamp(),
        'reviewNotes': reviewNotes,
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  // --- Cancel (pending OR approved -> cancelled; distinct from reject) ---

  /// The requesting employee can cancel their own pending or approved
  /// request; management can cancel anyone's, subject to
  /// timeOff.approve. Rejected/already-cancelled requests can't be
  /// cancelled again — see TimeOffRequestModel.isCancellable.
  Future<void> cancelRequest({
    required String companyId,
    required String actingUserId,
    required String requestId,
    String? cancellationReason,
  }) async {
    final membership =
        await _requireMembership(companyId: companyId, userId: actingUserId);

    final requestRef = _requestsRef(companyId).doc(requestId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(requestRef);
      if (!doc.exists) throw Exception('Time off request was not found.');
      final request = TimeOffRequestModel.fromSnapshot(doc);

      final isOwnRequest = request.employeeId == actingUserId;
      final canManage = PermissionService.roleHasPermission(
          membership.role, Permission.timeOffApprove);

      if (!isOwnRequest && !canManage) {
        throw Exception('You cannot cancel this request.');
      }

      if (!request.isCancellable) {
        throw Exception('This request can no longer be cancelled.');
      }

      transaction.update(requestRef, {
        FSFields.status: FSTimeOffStatus.cancelled,
        'cancelledByUserId': actingUserId,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancellationReason': cancellationReason,
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }
}
