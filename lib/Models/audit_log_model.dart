import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// What kind of thing this entry is about — used for filtering the
/// log view, not for permissions.
class AuditTargetType {
  AuditTargetType._();

  static const company = 'company';
  static const platformAdmin = 'platformAdmin';
}

/// A single immutable audit entry: who did what, to what, when — and
/// what the value was before/after, where that's meaningful. Nothing
/// should ever update or delete one of these once written.
class AuditLogEntry {
  final String entryId;
  final String adminId;
  final String adminName;
  final String action;
  final String targetType;
  final String targetId;
  final String targetName;
  final String? oldValue;
  final String? newValue;
  final DateTime createdAt;

  const AuditLogEntry({
    required this.entryId,
    required this.adminId,
    required this.adminName,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.targetName,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  static Map<String, dynamic> toMapForCreate({
    required String adminId,
    required String adminName,
    required String action,
    required String targetType,
    required String targetId,
    required String targetName,
    String? oldValue,
    String? newValue,
  }) {
    return {
      'adminId': adminId,
      'adminName': adminName,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'targetName': targetName,
      'oldValue': oldValue,
      'newValue': newValue,
      FSFields.createdAt: FieldValue.serverTimestamp(),
    };
  }

  factory AuditLogEntry.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    return AuditLogEntry(
      entryId: doc.id,
      adminId: map['adminId']?.toString() ?? '',
      adminName: map['adminName']?.toString() ?? 'Unknown Admin',
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
