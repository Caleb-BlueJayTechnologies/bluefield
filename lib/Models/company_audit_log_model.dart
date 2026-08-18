import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// What kind of thing a company audit entry is about.
class CompanyAuditTargetType {
  CompanyAuditTargetType._();

  static const membership = 'membership'; // role changes
  static const employee = 'employee'; // archive/restore
  static const job = 'job'; // status transitions
}

/// A single immutable entry in a company's own audit trail — scoped to
/// actions company members (owners/managers) take within their own
/// company. Distinct from the platform-wide AuditLogEntry, which
/// tracks platform ADMIN actions instead. Stored at
/// `companies/{companyId}/auditLog/{entryId}`.
///
/// This is deliberately scoped to the highest-value actions (role
/// changes, employee archive/restore, job status transitions) rather
/// than every mutation in the app — a genuinely complete audit trail
/// would mean instrumenting dozens of call sites across many services,
/// which is a much larger undertaking than this pass covers.
class CompanyAuditEntry {
  final String entryId;
  final String actorUserId;
  final String actorName;
  final String action;
  final String targetType;
  final String targetId;
  final String targetName;
  final String? oldValue;
  final String? newValue;
  final DateTime createdAt;

  const CompanyAuditEntry({
    required this.entryId,
    required this.actorUserId,
    required this.actorName,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.targetName,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  static Map<String, dynamic> toMapForCreate({
    required String actorUserId,
    required String actorName,
    required String action,
    required String targetType,
    required String targetId,
    required String targetName,
    String? oldValue,
    String? newValue,
  }) {
    return {
      'actorUserId': actorUserId,
      'actorName': actorName,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'targetName': targetName,
      'oldValue': oldValue,
      'newValue': newValue,
      FSFields.createdAt: FieldValue.serverTimestamp(),
    };
  }

  factory CompanyAuditEntry.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    return CompanyAuditEntry(
      entryId: doc.id,
      actorUserId: map['actorUserId']?.toString() ?? '',
      actorName: map['actorName']?.toString() ?? 'Unknown',
      action: map['action']?.toString() ?? '',
      targetType: map['targetType']?.toString() ?? '',
      targetId: map['targetId']?.toString() ?? '',
      targetName: map['targetName']?.toString() ?? '',
      oldValue: map['oldValue']?.toString(),
      newValue: map['newValue']?.toString(),
      createdAt: readDate(map[FSFields.createdAt]),
    );
  }
}
