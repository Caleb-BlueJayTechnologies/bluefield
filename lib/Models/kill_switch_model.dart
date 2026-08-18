import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// An emergency platform-wide kill switch. Stored at
/// `killSwitches/{switchKey}` — the key is the doc ID (e.g.
/// 'messaging', 'jobCreation', 'timeClockIn'). Unlike a feature flag,
/// there's no per-company targeting: when isKilled is true, that
/// system is disabled for every company at once. Meant for incident
/// response — stopping something broken immediately without a code
/// deploy — not staged rollout.
class KillSwitchModel {
  final String switchKey;
  final String description;
  final bool isKilled;
  final String? activatedByAdminId;
  final DateTime? activatedAt;
  final String? deactivatedByAdminId;
  final DateTime? deactivatedAt;

  const KillSwitchModel({
    required this.switchKey,
    required this.description,
    this.isKilled = false,
    this.activatedByAdminId,
    this.activatedAt,
    this.deactivatedByAdminId,
    this.deactivatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'isKilled': isKilled,
      'activatedByAdminId': activatedByAdminId,
      'activatedAt': activatedAt != null ? Timestamp.fromDate(activatedAt!) : null,
      'deactivatedByAdminId': deactivatedByAdminId,
      'deactivatedAt': deactivatedAt != null ? Timestamp.fromDate(deactivatedAt!) : null,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String description,
  }) {
    return {
      'description': description,
      'isKilled': false,
      'activatedByAdminId': null,
      'activatedAt': null,
      'deactivatedByAdminId': null,
      'deactivatedAt': null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory KillSwitchModel.fromMap(String switchKey, Map<String, dynamic> map) {
    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return null;
    }

    return KillSwitchModel(
      switchKey: switchKey,
      description: map['description']?.toString() ?? '',
      isKilled: map['isKilled'] == true,
      activatedByAdminId: map['activatedByAdminId']?.toString(),
      activatedAt: readDate(map['activatedAt']),
      deactivatedByAdminId: map['deactivatedByAdminId']?.toString(),
      deactivatedAt: readDate(map['deactivatedAt']),
    );
  }

  factory KillSwitchModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Kill switch document ${doc.id} has no data.');
    }
    return KillSwitchModel.fromMap(doc.id, data);
  }
}
