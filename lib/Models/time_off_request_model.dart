import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// Suggested seed IDs for a company's leaveTypes subcollection
/// (companies/{companyId}/leaveTypes/{id}). Companies can add their own
/// custom leave types with different IDs later — these are just the
/// common starting set, not a hardcoded enum. FMLA/protected-leave
/// classification is intentionally left as plain informational text on
/// the leave type itself (a future LeaveTypeModel file), not a legal
/// determination made anywhere in this app.
class StandardLeaveTypeIds {
  StandardLeaveTypeIds._();

  static const pto = 'pto';
  static const sick = 'sick';
  static const unpaid = 'unpaid';
  static const bereavement = 'bereavement';
  static const juryDuty = 'juryDuty';
}

/// A time-off request. Stored at
/// `companies/{companyId}/timeOffRequests/{requestId}`.
///
/// Rejection and cancellation are kept as distinct outcomes:
/// rejection is a manager/owner decision on a pending request;
/// cancellation can happen on a pending OR previously-approved request,
/// by the employee (subject to policy) or by management, and is
/// recorded separately so the history stays clear about who ended the
/// request and why.
class TimeOffRequestModel {
  final String requestId;
  final String companyId;
  final String employeeId;

  /// References companies/{companyId}/leaveTypes/{leaveTypeId}.
  final String leaveTypeId;

  final bool isFullDay;

  /// Date-only range. For a single-day request, startDate == endDate.
  final DateTime startDate;
  final DateTime endDate;

  /// Total hours being requested across the whole date range. Computed
  /// and snapshotted by the service at submission time (e.g. from the
  /// company's standard workday length), not recalculated later — so a
  /// later change to company policy doesn't retroactively change what an
  /// already-submitted request says it asked for.
  final double? totalHours;

  final String? reason;
  final String? notes;

  final String status; // FSTimeOffStatus.*

  final String? reviewedByUserId;
  final DateTime? reviewedAt;
  final String? reviewNotes;

  final String? cancelledByUserId;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  /// True if the requester or reviewer explicitly acknowledged a
  /// schedule-conflict warning (e.g. an approved job overlaps this
  /// range) rather than the system silently blocking it.
  final bool scheduleConflictAcknowledged;

  final DateTime createdAt;
  final DateTime updatedAt;

  const TimeOffRequestModel({
    required this.requestId,
    required this.companyId,
    required this.employeeId,
    required this.leaveTypeId,
    required this.isFullDay,
    required this.startDate,
    required this.endDate,
    this.totalHours,
    this.reason,
    this.notes,
    required this.status,
    this.reviewedByUserId,
    this.reviewedAt,
    this.reviewNotes,
    this.cancelledByUserId,
    this.cancelledAt,
    this.cancellationReason,
    this.scheduleConflictAcknowledged = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => status == FSTimeOffStatus.pending;
  bool get isApproved => status == FSTimeOffStatus.approved;
  bool get isRejected => status == FSTimeOffStatus.rejected;
  bool get isCancelled => status == FSTimeOffStatus.cancelled;
  bool get isReviewed => reviewedAt != null;

  bool get isMultiDay =>
      startDate.year != endDate.year ||
      startDate.month != endDate.month ||
      startDate.day != endDate.day;

  /// Whether this request can still be cancelled by policy — pending or
  /// approved requests can be; already-rejected or already-cancelled
  /// ones can't be cancelled again. Whether the CURRENT USER is allowed
  /// to cancel it is a permission check the service layer makes, not
  /// this model.
  bool get isCancellable => isPending || isApproved;

  static bool isValidDateRange(DateTime start, DateTime end) =>
      !end.isBefore(start);

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      FSFields.employeeId: employeeId,
      'leaveTypeId': leaveTypeId,
      'isFullDay': isFullDay,
      FSFields.startDate: Timestamp.fromDate(startDate),
      FSFields.endDate: Timestamp.fromDate(endDate),
      'totalHours': totalHours,
      'reason': reason,
      'notes': notes,
      FSFields.status: status,
      'reviewedByUserId': reviewedByUserId,
      FSFields.reviewedAt:
          reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewNotes': reviewNotes,
      'cancelledByUserId': cancelledByUserId,
      'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
      'cancellationReason': cancellationReason,
      'scheduleConflictAcknowledged': scheduleConflictAcknowledged,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
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
  }) {
    return {
      FSFields.companyId: companyId,
      FSFields.employeeId: employeeId,
      'leaveTypeId': leaveTypeId,
      'isFullDay': isFullDay,
      FSFields.startDate: Timestamp.fromDate(startDate),
      FSFields.endDate: Timestamp.fromDate(endDate),
      'totalHours': totalHours,
      'reason': reason,
      'notes': notes,
      FSFields.status: FSTimeOffStatus.pending,
      'reviewedByUserId': null,
      FSFields.reviewedAt: null,
      'reviewNotes': null,
      'cancelledByUserId': null,
      'cancelledAt': null,
      'cancellationReason': null,
      'scheduleConflictAcknowledged': scheduleConflictAcknowledged,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory TimeOffRequestModel.fromMap(
    String requestId,
    Map<String, dynamic> map,
  ) {
    final start = FSTimestamp.tryParse(map[FSFields.startDate]);
    final end = FSTimestamp.tryParse(map[FSFields.endDate]);
    final fallback = start ?? DateTime.now();

    return TimeOffRequestModel(
      requestId: requestId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      employeeId: map[FSFields.employeeId]?.toString() ?? '',
      leaveTypeId: map['leaveTypeId']?.toString() ?? StandardLeaveTypeIds.pto,
      isFullDay: map['isFullDay'] ?? true,
      startDate: start ?? fallback,
      endDate: end ?? fallback,
      totalHours: (map['totalHours'] as num?)?.toDouble(),
      reason: map['reason']?.toString(),
      notes: map['notes']?.toString(),
      status: map[FSFields.status]?.toString() ?? FSTimeOffStatus.pending,
      reviewedByUserId: map['reviewedByUserId']?.toString(),
      reviewedAt: FSTimestamp.tryParse(map[FSFields.reviewedAt]),
      reviewNotes: map['reviewNotes']?.toString(),
      cancelledByUserId: map['cancelledByUserId']?.toString(),
      cancelledAt: FSTimestamp.tryParse(map['cancelledAt']),
      cancellationReason: map['cancellationReason']?.toString(),
      scheduleConflictAcknowledged:
          map['scheduleConflictAcknowledged'] == true,
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory TimeOffRequestModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Time off request document ${doc.id} has no data.');
    }
    return TimeOffRequestModel.fromMap(doc.id, data);
  }

  TimeOffRequestModel copyWith({
    String? leaveTypeId,
    bool? isFullDay,
    DateTime? startDate,
    DateTime? endDate,
    double? totalHours,
    String? reason,
    String? notes,
    String? status,
    String? reviewedByUserId,
    DateTime? reviewedAt,
    String? reviewNotes,
    String? cancelledByUserId,
    DateTime? cancelledAt,
    String? cancellationReason,
    bool? scheduleConflictAcknowledged,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TimeOffRequestModel(
      requestId: requestId,
      companyId: companyId,
      employeeId: employeeId,
      leaveTypeId: leaveTypeId ?? this.leaveTypeId,
      isFullDay: isFullDay ?? this.isFullDay,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      totalHours: totalHours ?? this.totalHours,
      reason: reason ?? this.reason,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      reviewedByUserId: reviewedByUserId ?? this.reviewedByUserId,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      cancelledByUserId: cancelledByUserId ?? this.cancelledByUserId,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      scheduleConflictAcknowledged:
          scheduleConflictAcknowledged ?? this.scheduleConflictAcknowledged,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
