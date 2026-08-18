import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/platform_admin_model.dart';
import 'audit_log_service.dart';

class PlatformAdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuditLogService _auditLog = AuditLogService();

  /// The one account that is ALWAYS a platform super admin, regardless
  /// of what's in the platformAdmins collection — even if that
  /// document is deleted, never created, or accidentally deactivated.
  /// This is the single account that must never be lockable-out of the
  /// Admin Panel. Every other admin (if any are ever added) goes
  /// through the normal Firestore-doc system via grantAdminAccess,
  /// which only this account (or another super admin it grants) can
  /// call.
  ///
  /// SET THIS to the exact email you sign into the BlueField app with
  /// before shipping — not your Firebase Console login, the actual
  /// app account email.
  static const String bootstrapSuperAdminEmail = 'caleb.bluejaytech@gmail.com';

  CollectionReference<Map<String, dynamic>> get _adminsRef =>
      _firestore.collection(FSCollections.platformAdmins);

  bool _isBootstrapAdmin(User user) {
    final email = user.email?.trim().toLowerCase() ?? '';
    return email.isNotEmpty && email == bootstrapSuperAdminEmail.trim().toLowerCase();
  }

  PlatformAdminModel _bootstrapAdminModel(User user) {
    return PlatformAdminModel(
      adminId: user.uid,
      email: user.email ?? bootstrapSuperAdminEmail,
      displayName: user.displayName?.trim().isNotEmpty == true ? user.displayName! : 'Super Admin',
      role: FSPlatformAdminRole.superAdmin,
      active: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Null means "not a platform admin at all" — this is the actual
  /// gate every Admin Panel screen must check before rendering
  /// anything. A user can be an Owner of ten companies and still get
  /// null here; the two systems never cross.
  Future<PlatformAdminModel?> getCurrentAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    if (_isBootstrapAdmin(user)) {
      // Self-heal: if the doc doesn't exist yet (first run) or was
      // ever deactivated, silently restore it rather than requiring a
      // manual Firestore edit every time. This is the ONE account this
      // is allowed to happen for automatically. Wrapped in try/catch
      // deliberately — this account's access must never depend on the
      // write actually succeeding (e.g. before security rules are
      // deployed, or any other transient Firestore issue). Email
      // match alone is what grants access; the doc is just for
      // consistency/tracking other admins might read later.
      try {
        final doc = await _adminsRef.doc(user.uid).get();
        if (!doc.exists || doc.data()?['active'] != true) {
          await _adminsRef.doc(user.uid).set(
                PlatformAdminModel.toMapForCreate(
                  email: user.email ?? bootstrapSuperAdminEmail,
                  displayName: user.displayName?.trim().isNotEmpty == true ? user.displayName! : 'Super Admin',
                  role: FSPlatformAdminRole.superAdmin,
                ),
                SetOptions(merge: true),
              );
        }
      } catch (_) {
        // Ignored on purpose — see comment above.
      }
      return _bootstrapAdminModel(user);
    }

    // Not being a platform admin is the overwhelmingly common case for
    // every account that reaches this branch — fail safe to null on
    // any read issue rather than letting it propagate up and break
    // whatever screen happened to call getCurrentAdmin() (this exact
    // failure mode broke the entire Settings screen for every
    // non-admin account before the rules fix for this).
    try {
      final doc = await _adminsRef.doc(user.uid).get();
      if (!doc.exists) return null;

      final admin = PlatformAdminModel.fromSnapshot(doc);
      return admin.active ? admin : null;
    } catch (_) {
      return null;
    }
  }

  /// Live version for the Admin Panel's own auth gate — if an admin's
  /// access is revoked while they're mid-session, this reflects it
  /// immediately rather than only on next login.
  Stream<PlatformAdminModel?> watchCurrentAdmin() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(null);

    if (_isBootstrapAdmin(user)) {
      return _adminsRef.doc(user.uid).snapshots().asyncMap((doc) async {
        if (!doc.exists || doc.data()?['active'] != true) {
          try {
            await _adminsRef.doc(user.uid).set(
                  PlatformAdminModel.toMapForCreate(
                    email: user.email ?? bootstrapSuperAdminEmail,
                    displayName: user.displayName?.trim().isNotEmpty == true ? user.displayName! : 'Super Admin',
                    role: FSPlatformAdminRole.superAdmin,
                  ),
                  SetOptions(merge: true),
                );
          } catch (_) {
            // Ignored on purpose — see getCurrentAdmin's comment: this
            // account's access must never depend on the write succeeding.
          }
        }
        return _bootstrapAdminModel(user);
      }).transform(
        StreamTransformer<PlatformAdminModel, PlatformAdminModel?>.fromHandlers(
          handleData: (data, sink) => sink.add(data),
          // Even a READ-level rules failure on the stream itself (not
          // just the self-heal write above) must still resolve to the
          // bootstrap admin rather than propagate a stream error that
          // would break AdminGateScreen's StreamBuilder.
          handleError: (error, stackTrace, sink) => sink.add(_bootstrapAdminModel(user)),
        ),
      );
    }

    return _adminsRef.doc(user.uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final admin = PlatformAdminModel.fromSnapshot(doc);
      return admin.active ? admin : null;
    });
  }

  Future<PlatformAdminModel?> getAdmin(String adminId) async {
    final doc = await _adminsRef.doc(adminId).get();
    if (!doc.exists) return null;
    return PlatformAdminModel.fromSnapshot(doc);
  }

  Future<List<PlatformAdminModel>> getAllAdmins() async {
    final snapshot = await _adminsRef.get();
    return snapshot.docs.map((d) => PlatformAdminModel.fromSnapshot(d)).toList();
  }

  Stream<List<PlatformAdminModel>> watchAllAdmins() {
    return _adminsRef.snapshots().map(
          (snapshot) => snapshot.docs.map((d) => PlatformAdminModel.fromSnapshot(d)).toList(),
        );
  }

  /// Resolves a user's UID + display name from their email, so a
  /// super admin can grant access without needing to already know
  /// someone's raw Firebase UID — they only ever see an email.
  /// Returns null if no account with that email exists yet (the
  /// person needs to sign up for BlueField first, same as any other
  /// user — this doesn't create an account).
  Future<({String uid, String email, String displayName})?> findUserByEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return null;

    // Emails aren't normalized to a consistent case anywhere in this
    // app (registration/add-employee both store whatever was typed),
    // so an exact-match query on one casing risks silently missing a
    // real account. Try as-typed first, then a lowercased fallback.
    for (final candidate in {trimmed, trimmed.toLowerCase()}) {
      final snapshot =
          await _firestore.collection(FSCollections.users).where('email', isEqualTo: candidate).limit(1).get();
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        final firstName = data['firstName']?.toString() ?? '';
        final lastName = data['lastName']?.toString() ?? '';
        final displayName = '$firstName $lastName'.trim();
        return (uid: doc.id, email: candidate, displayName: displayName.isEmpty ? candidate : displayName);
      }
    }
    return null;
  }

  Future<void> _requireSuperAdmin(String actingAdminId) async {
    // Same fix as AdminCompanyService._requireCompanyManager — uses
    // getCurrentAdmin() (bootstrap-aware) instead of a plain
    // getAdmin(actingAdminId) lookup, so the bootstrap admin is never
    // incorrectly denied here just because their platformAdmins doc
    // hasn't self-healed yet this session.
    final acting = await getCurrentAdmin();
    if (acting == null || acting.adminId != actingAdminId || !acting.canManageOtherAdmins) {
      throw Exception('Only a super admin can manage other platform admins.');
    }
  }

  /// Grants platform-admin access to an existing Firebase Auth user.
  /// [targetUid] must already be a real Auth account (this does not
  /// create one) — typically a BlueJay employee who already has a
  /// normal `users/{uid}` doc from signing up, now being elevated.
  Future<void> grantAdminAccess({
    required String actingAdminId,
    required String targetUid,
    required String email,
    required String displayName,
    required String role,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    await _adminsRef.doc(targetUid).set(PlatformAdminModel.toMapForCreate(
          email: email,
          displayName: displayName,
          role: role,
          grantedByAdminId: actingAdminId,
        ));

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'platformAdmin.grant',
      targetType: 'platformAdmin',
      targetId: targetUid,
      targetName: displayName,
      newValue: role,
    );
  }

  Future<void> updateAdminRole({
    required String actingAdminId,
    required String targetAdminId,
    required String newRole,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    final target = await getAdmin(targetAdminId);

    await _adminsRef.doc(targetAdminId).update({
      FSFields.role: newRole,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'platformAdmin.changeRole',
      targetType: 'platformAdmin',
      targetId: targetAdminId,
      targetName: target?.displayName ?? targetAdminId,
      oldValue: target?.role,
      newValue: newRole,
    );
  }

  Future<void> setAdminActive({
    required String actingAdminId,
    required String targetAdminId,
    required bool active,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    if (actingAdminId == targetAdminId && !active) {
      throw Exception('You cannot deactivate your own admin access.');
    }

    final target = await getAdmin(targetAdminId);

    await _adminsRef.doc(targetAdminId).update({
      'active': active,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: active ? 'platformAdmin.activate' : 'platformAdmin.deactivate',
      targetType: 'platformAdmin',
      targetId: targetAdminId,
      targetName: target?.displayName ?? targetAdminId,
    );
  }
}
