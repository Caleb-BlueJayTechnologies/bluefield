import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// A user's security role within one specific company. Stored at
/// `companies/{companyId}/memberships/{userId}`.
///
/// This is the ONLY place that determines what a user is allowed to do
/// in a company — never trust a role field stored anywhere else.
/// A company can have any number of memberships with role == owner or
/// role == manager (Section 3: multiple owners/managers are required,
/// not an edge case).
///
/// Job title (e.g. "Operations Director", "Crew Lead") is intentionally
/// NOT on this model — see EmployeeModel for that. Title is display-only
/// and must never be used to gate access.
class MembershipModel {
  /// Same value as [userId]. Kept as an explicit field (not just relying
  /// on the doc ID) so it survives being passed around outside a snapshot.
  final String membershipId;

  final String userId;
  final String companyId;

  final String role; // FSRoles.owner / manager / employee
  final String status; // FSMembershipStatus.active / archived / suspended

  /// Who invited this user, if they joined via invitation. Null for the
  /// company's original registering owner.
  final String? invitedBy;
  final DateTime? invitedAt;
  final DateTime? joinedAt;

  final DateTime? archivedAt;
  final String? archivedBy;
  final String? archiveReason;

  /// Who most recently changed this membership's role, and when — needed
  /// so promotions/demotions are auditable (Section 3 requirement).
  final String? roleChangedBy;
  final DateTime? roleChangedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  const MembershipModel({
    required this.membershipId,
    required this.userId,
    required this.companyId,
    required this.role,
    required this.status,
    this.invitedBy,
    this.invitedAt,
    this.joinedAt,
    this.archivedAt,
    this.archivedBy,
    this.archiveReason,
    this.roleChangedBy,
    this.roleChangedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOwner => role == FSRoles.owner;
  bool get isManager => role == FSRoles.manager;
  bool get isEmployee => role == FSRoles.employee;

  bool get isActive => status == FSMembershipStatus.active;
  bool get isArchived => status == FSMembershipStatus.archived;
  bool get isSuspended => status == FSMembershipStatus.suspended;

  /// Whether this membership currently grants access at all. Suspended
  /// and archived memberships must not be able to read or write company
  /// data — enforce the same check in Firestore rules, not just here.
  bool get grantsAccess => isActive;

  Map<String, dynamic> toMap() {
    return {
      FSFields.userId: userId,
      FSFields.companyId: companyId,
      FSFields.role: role,
      FSFields.status: status,
      'invitedBy': invitedBy,
      'invitedAt': invitedAt != null ? Timestamp.fromDate(invitedAt!) : null,
      'joinedAt': joinedAt != null ? Timestamp.fromDate(joinedAt!) : null,
      FSFields.archivedAt:
          archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      FSFields.archivedBy: archivedBy,
      FSFields.archiveReason: archiveReason,
      'roleChangedBy': roleChangedBy,
      'roleChangedAt': roleChangedAt != null
          ? Timestamp.fromDate(roleChangedAt!)
          : null,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  /// For the initial `set()` when a membership is first created (company
  /// registration or invitation acceptance). Uses server timestamps.
  static Map<String, dynamic> toMapForCreate({
    required String userId,
    required String companyId,
    required String role,
    String status = FSMembershipStatus.active,
    String? invitedBy,
  }) {
    return {
      FSFields.userId: userId,
      FSFields.companyId: companyId,
      FSFields.role: role,
      FSFields.status: status,
      'invitedBy': invitedBy,
      'invitedAt': invitedBy != null ? FieldValue.serverTimestamp() : null,
      'joinedAt': FieldValue.serverTimestamp(),
      FSFields.archivedAt: null,
      FSFields.archivedBy: null,
      FSFields.archiveReason: null,
      'roleChangedBy': null,
      'roleChangedAt': null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory MembershipModel.fromMap(String membershipId, Map<String, dynamic> map) {
    return MembershipModel(
      membershipId: membershipId,
      userId: map[FSFields.userId]?.toString() ?? membershipId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      role: map[FSFields.role]?.toString().toLowerCase().trim() ??
          FSRoles.employee,
      status: map[FSFields.status]?.toString().toLowerCase().trim() ??
          FSMembershipStatus.active,
      invitedBy: map['invitedBy']?.toString(),
      invitedAt: FSTimestamp.tryParse(map['invitedAt']),
      joinedAt: FSTimestamp.tryParse(map['joinedAt']),
      archivedAt: FSTimestamp.tryParse(map[FSFields.archivedAt]),
      archivedBy: map[FSFields.archivedBy]?.toString(),
      archiveReason: map[FSFields.archiveReason]?.toString(),
      roleChangedBy: map['roleChangedBy']?.toString(),
      roleChangedAt: FSTimestamp.tryParse(map['roleChangedAt']),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory MembershipModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Membership document ${doc.id} has no data.');
    }
    return MembershipModel.fromMap(doc.id, data);
  }

  MembershipModel copyWith({
    String? role,
    String? status,
    String? invitedBy,
    DateTime? invitedAt,
    DateTime? joinedAt,
    DateTime? archivedAt,
    String? archivedBy,
    String? archiveReason,
    String? roleChangedBy,
    DateTime? roleChangedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MembershipModel(
      membershipId: membershipId,
      userId: userId,
      companyId: companyId,
      role: role ?? this.role,
      status: status ?? this.status,
      invitedBy: invitedBy ?? this.invitedBy,
      invitedAt: invitedAt ?? this.invitedAt,
      joinedAt: joinedAt ?? this.joinedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      archiveReason: archiveReason ?? this.archiveReason,
      roleChangedBy: roleChangedBy ?? this.roleChangedBy,
      roleChangedAt: roleChangedAt ?? this.roleChangedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
