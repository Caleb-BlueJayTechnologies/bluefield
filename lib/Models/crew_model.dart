import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// A crew or team within a company. Stored at
/// `companies/{companyId}/crews/{crewId}`.
///
/// Membership is intentionally NOT stored here as a list. The source of
/// truth for "who is on this crew" is EmployeeModel.crewId — query
/// employees where crewId == this crew's ID. Storing a second memberIds
/// list here would let the two fall out of sync (the exact "duplicate
/// crew membership records" problem the plan calls out), and active
/// member counts should be computed from that same query rather than
/// cached on this doc.
///
/// Whether a company calls this concept "Crew" or "Team" is a display
/// label controlled by company settings, not stored per-crew.
class CrewModel {
  final String crewId;
  final String companyId;

  final String crewName;
  final String? description;

  /// employeeId of the crew leader, if one is set. Informational —
  /// does not itself grant any extra permission; a crew leader's actual
  /// access still comes from their MembershipModel.role.
  final String? leaderId;

  /// Display color used in schedule/calendar views.
  final String color;

  final bool isArchived;
  final DateTime? archivedAt;
  final String? archivedBy;
  final String? archiveReason;

  final String? createdBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CrewModel({
    required this.crewId,
    required this.companyId,
    required this.crewName,
    this.description,
    this.leaderId,
    required this.color,
    required this.isArchived,
    this.archivedAt,
    this.archivedBy,
    this.archiveReason,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasLeader => leaderId != null && leaderId!.trim().isNotEmpty;
  bool get isActive => !isArchived;

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'crewName': crewName,
      'description': description,
      'leaderId': leaderId,
      'color': color,
      FSFields.isArchived: isArchived,
      FSFields.archivedAt:
          archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      FSFields.archivedBy: archivedBy,
      FSFields.archiveReason: archiveReason,
      FSFields.createdBy: createdBy,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String crewName,
    String? description,
    String? leaderId,
    String color = '#2196F3',
    String? createdBy,
  }) {
    return {
      FSFields.companyId: companyId,
      'crewName': crewName,
      'description': description,
      'leaderId': leaderId,
      'color': color,
      FSFields.isArchived: false,
      FSFields.archivedAt: null,
      FSFields.archivedBy: null,
      FSFields.archiveReason: null,
      FSFields.createdBy: createdBy,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory CrewModel.fromMap(String crewId, Map<String, dynamic> map) {
    return CrewModel(
      crewId: crewId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      crewName: map['crewName']?.toString() ?? '',
      description: map['description']?.toString(),
      leaderId: map['leaderId']?.toString(),
      color: map['color']?.toString() ?? '#2196F3',
      isArchived: map[FSFields.isArchived] == true ||
          map['isActive'] == false, // migration-safe: old docs used isActive
      archivedAt: FSTimestamp.tryParse(map[FSFields.archivedAt]),
      archivedBy: map[FSFields.archivedBy]?.toString(),
      archiveReason: map[FSFields.archiveReason]?.toString(),
      createdBy: map[FSFields.createdBy]?.toString(),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory CrewModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Crew document ${doc.id} has no data.');
    }
    return CrewModel.fromMap(doc.id, data);
  }

  CrewModel copyWith({
    String? crewName,
    String? description,
    bool clearLeader = false,
    String? leaderId,
    String? color,
    bool? isArchived,
    DateTime? archivedAt,
    String? archivedBy,
    String? archiveReason,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CrewModel(
      crewId: crewId,
      companyId: companyId,
      crewName: crewName ?? this.crewName,
      description: description ?? this.description,
      leaderId: clearLeader ? null : (leaderId ?? this.leaderId),
      color: color ?? this.color,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      archiveReason: archiveReason ?? this.archiveReason,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
