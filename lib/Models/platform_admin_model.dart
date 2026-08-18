import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// A platform-level administrator account — grants access to the
/// BlueJay Admin Panel. Stored at `platformAdmins/{uid}`, where the
/// doc ID is the same Firebase Auth UID as the admin's own `users/{uid}`
/// account (an admin is still a normal user for auth purposes; this
/// doc is what elevates them to platform-admin status on top of that).
///
/// Being an Owner of a customer company grants NONE of this — company
/// role and platform-admin role are two completely separate permission
/// surfaces by design (see FSPlatformAdminRole).
class PlatformAdminModel {
  final String adminId;
  final String email;
  final String displayName;
  final String role;
  final bool active;
  final String? grantedByAdminId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PlatformAdminModel({
    required this.adminId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.active,
    this.grantedByAdminId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSuperAdmin => role == FSPlatformAdminRole.superAdmin;

  /// Super admins can do everything; other roles are scoped by the
  /// screens/services that check this role explicitly (e.g. only
  /// billingAdmin need touch subscription data). Kept intentionally
  /// simple for v1 — a real per-permission matrix like company roles
  /// have can be layered on later if BlueJay's own team grows enough
  /// to need it.
  bool get canManageTickets =>
      active && (role == FSPlatformAdminRole.superAdmin || role == FSPlatformAdminRole.supportAdmin);

  bool get canManageOtherAdmins => active && isSuperAdmin;

  /// Suspending a company, marking it internal/test, or editing its
  /// billing metadata is a step more sensitive than ticket triage —
  /// kept superAdmin-only rather than opening it to supportAdmin too.
  /// Any active platform admin can still VIEW company data.
  bool get canManageCompanies => active && isSuperAdmin;

  static Map<String, dynamic> toMapForCreate({
    required String email,
    required String displayName,
    required String role,
    String? grantedByAdminId,
  }) {
    return {
      'email': email,
      'displayName': displayName,
      FSFields.role: role,
      'active': true,
      'grantedByAdminId': grantedByAdminId,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory PlatformAdminModel.fromMap(String adminId, Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    return PlatformAdminModel(
      adminId: adminId,
      email: map['email']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      role: map[FSFields.role]?.toString() ?? FSPlatformAdminRole.supportAdmin,
      active: map['active'] == true,
      grantedByAdminId: map['grantedByAdminId']?.toString(),
      createdAt: readDate(map[FSFields.createdAt]),
      updatedAt: readDate(map[FSFields.updatedAt]),
    );
  }

  factory PlatformAdminModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return PlatformAdminModel.fromMap(doc.id, doc.data() ?? {});
  }
}
