import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// What the employee is asking to have fixed.
class CorrectionRequestType {
  CorrectionRequestType._();

  static const missingClockIn = 'missingClockIn';
  static const missingClockOut = 'missingClockOut';
  static const bothTimes = 'bothTimes'; // correcting an existing in AND out
}

/// An employee's request to fix a missing or incorrect clock in/out.
/// Stored at `companies/{companyId}/correctionRequests/{requestId}`.
///
/// Renamed from the old ad-hoc `timeCorrectionRequests` collection name
/// used in correction_requests_screen.dart — that screen gets rewired to
/// `FSCompanySub.correctionRequests` when its turn comes.
///
/// Approving a request is a two-step effect: this document records the
/// request/decision itself, and the linked TimeEntryModel gets updated
/// (with its own originalClockInAt/originalClockOutAt preserved) by
/// time_entry_service when a manager approves. This model never writes
/// to the time entry directly.
class CorrectionRequestModel {
  final String requestId;
  final String companyId;
  final String employeeId;

  /// Null if the employee is requesting an entry be created from
  /// scratch (e.g. they forgot to clock in at all and no entry exists).
  final String? timeEntryId;

  final String requestType; // CorrectionRequestType.*

  /// What the employee is asking the times to be.
  final DateTime? requestedClockInAt;
  final DateTime? requestedClockOutAt;

  final String reason;

  final String status; // FSCorrectionStatus.*

  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNotes;

  /// Snapshot of the time entry's values at the moment the request was
  /// submitted, so the review screen can show a clear before/after even
  /// if the entry changes again before the request is decided.
  final DateTime? originalClockInAt;
  final DateTime? originalClockOutAt;

  /// The values actually written back to the time entry on approval —
  /// may differ slightly from requestedClockInAt/Out if the reviewer
  /// adjusted them rather than approving verbatim.
  final DateTime? appliedClockInAt;
  final DateTime? appliedClockOutAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CorrectionRequestModel({
    required this.requestId,
    required this.companyId,
    required this.employeeId,
    this.timeEntryId,
    required this.requestType,
    this.requestedClockInAt,
    this.requestedClockOutAt,
    required this.reason,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNotes,
    this.originalClockInAt,
    this.originalClockOutAt,
    this.appliedClockInAt,
    this.appliedClockOutAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => status == FSCorrectionStatus.pending;
  bool get isApproved => status == FSCorrectionStatus.approved;
  bool get isRejected => status == FSCorrectionStatus.rejected;
  bool get isReviewed => reviewedAt != null;
  bool get isForNewEntry => timeEntryId == null;

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      FSFields.employeeId: employeeId,
      FSFields.timeEntryId: timeEntryId,
      'requestType': requestType,
      'requestedClockInAt': requestedClockInAt != null
          ? Timestamp.fromDate(requestedClockInAt!)
          : null,
      'requestedClockOutAt': requestedClockOutAt != null
          ? Timestamp.fromDate(requestedClockOutAt!)
          : null,
      'reason': reason,
      FSFields.status: status,
      FSFields.reviewedBy: reviewedBy,
      FSFields.reviewedAt:
          reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewNotes': reviewNotes,
      'originalClockInAt': originalClockInAt != null
          ? Timestamp.fromDate(originalClockInAt!)
          : null,
      'originalClockOutAt': originalClockOutAt != null
          ? Timestamp.fromDate(originalClockOutAt!)
          : null,
      'appliedClockInAt': appliedClockInAt != null
          ? Timestamp.fromDate(appliedClockInAt!)
          : null,
      'appliedClockOutAt': appliedClockOutAt != null
          ? Timestamp.fromDate(appliedClockOutAt!)
          : null,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String employeeId,
    String? timeEntryId,
    required String requestType,
    DateTime? requestedClockInAt,
    DateTime? requestedClockOutAt,
    required String reason,
    DateTime? originalClockInAt,
    DateTime? originalClockOutAt,
  }) {
    return {
      FSFields.companyId: companyId,
      FSFields.employeeId: employeeId,
      FSFields.timeEntryId: timeEntryId,
      'requestType': requestType,
      'requestedClockInAt': requestedClockInAt != null
          ? Timestamp.fromDate(requestedClockInAt)
          : null,
      'requestedClockOutAt': requestedClockOutAt != null
          ? Timestamp.fromDate(requestedClockOutAt)
          : null,
      'reason': reason,
      FSFields.status: FSCorrectionStatus.pending,
      FSFields.reviewedBy: null,
      FSFields.reviewedAt: null,
      'reviewNotes': null,
      'originalClockInAt': originalClockInAt != null
          ? Timestamp.fromDate(originalClockInAt)
          : null,
      'originalClockOutAt': originalClockOutAt != null
          ? Timestamp.fromDate(originalClockOutAt)
          : null,
      'appliedClockInAt': null,
      'appliedClockOutAt': null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory CorrectionRequestModel.fromMap(
    String requestId,
    Map<String, dynamic> map,
  ) {
    return CorrectionRequestModel(
      requestId: requestId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      employeeId: map[FSFields.employeeId]?.toString() ?? '',
      timeEntryId: map[FSFields.timeEntryId]?.toString(),
      requestType:
          map['requestType']?.toString() ?? CorrectionRequestType.bothTimes,
      requestedClockInAt: FSTimestamp.tryParse(map['requestedClockInAt']),
      requestedClockOutAt: FSTimestamp.tryParse(map['requestedClockOutAt']),
      reason: map['reason']?.toString() ?? '',
      status: map[FSFields.status]?.toString() ?? FSCorrectionStatus.pending,
      reviewedBy: map[FSFields.reviewedBy]?.toString(),
      reviewedAt: FSTimestamp.tryParse(map[FSFields.reviewedAt]),
      reviewNotes: map['reviewNotes']?.toString(),
      originalClockInAt: FSTimestamp.tryParse(map['originalClockInAt']),
      originalClockOutAt: FSTimestamp.tryParse(map['originalClockOutAt']),
      appliedClockInAt: FSTimestamp.tryParse(map['appliedClockInAt']),
      appliedClockOutAt: FSTimestamp.tryParse(map['appliedClockOutAt']),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory CorrectionRequestModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Correction request document ${doc.id} has no data.');
    }
    return CorrectionRequestModel.fromMap(doc.id, data);
  }

  CorrectionRequestModel copyWith({
    String? status,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? reviewNotes,
    DateTime? appliedClockInAt,
    DateTime? appliedClockOutAt,
    DateTime? updatedAt,
  }) {
    return CorrectionRequestModel(
      requestId: requestId,
      companyId: companyId,
      employeeId: employeeId,
      timeEntryId: timeEntryId,
      requestType: requestType,
      requestedClockInAt: requestedClockInAt,
      requestedClockOutAt: requestedClockOutAt,
      reason: reason,
      status: status ?? this.status,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      originalClockInAt: originalClockInAt,
      originalClockOutAt: originalClockOutAt,
      appliedClockInAt: appliedClockInAt ?? this.appliedClockInAt,
      appliedClockOutAt: appliedClockOutAt ?? this.appliedClockOutAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
