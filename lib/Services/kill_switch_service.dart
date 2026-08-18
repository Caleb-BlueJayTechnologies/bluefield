import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/kill_switch_model.dart';
import 'audit_log_service.dart';
import 'platform_admin_service.dart';

class KillSwitchService {
  final FirebaseFirestore _firestore;
  final PlatformAdminService _adminService;
  final AuditLogService _auditLog;

  KillSwitchService({
    FirebaseFirestore? firestore,
    PlatformAdminService? adminService,
    AuditLogService? auditLogService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _adminService = adminService ?? PlatformAdminService(),
        _auditLog = auditLogService ?? AuditLogService();

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(FSCollections.killSwitches);

  /// This is the highest blast-radius action in the admin panel —
  /// flipping this instantly disables something for every company at
  /// once. Same gate as managing other admins and system
  /// announcements: super admin only.
  Future<void> _requireSuperAdmin(String actingAdminId) async {
    final acting = await _adminService.getCurrentAdmin();
    if (acting == null || acting.adminId != actingAdminId || !acting.canManageOtherAdmins) {
      throw Exception('Only a super admin can manage kill switches.');
    }
  }

  /// The actual check the main app calls before letting someone use a
  /// switched-off feature. No permission gating — just a read.
  /// Defaults to false (not killed) if the switch doesn't exist yet,
  /// so a typo'd or not-yet-created key never accidentally disables
  /// something.
  Future<bool> isKilled(String switchKey) async {
    final doc = await _ref.doc(switchKey).get();
    if (!doc.exists) return false;
    return KillSwitchModel.fromSnapshot(doc).isKilled;
  }

  Stream<List<KillSwitchModel>> watchAllSwitches() {
    return _ref.snapshots().map((snap) {
      final switches = snap.docs.map((d) => KillSwitchModel.fromSnapshot(d)).toList()
        ..sort((a, b) => a.switchKey.compareTo(b.switchKey));
      return switches;
    });
  }

  Future<void> createSwitch({
    required String actingAdminId,
    required String switchKey,
    required String description,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    final trimmedKey = switchKey.trim();
    if (trimmedKey.isEmpty) {
      throw Exception('A switch key is required.');
    }

    final existing = await _ref.doc(trimmedKey).get();
    if (existing.exists) {
      throw Exception('A kill switch with this key already exists.');
    }

    await _ref.doc(trimmedKey).set(KillSwitchModel.toMapForCreate(description: description.trim()));

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'killSwitch.create',
      targetType: 'killSwitch',
      targetId: trimmedKey,
      targetName: trimmedKey,
      newValue: description.trim(),
    );
  }

  Future<void> activate({
    required String actingAdminId,
    required String switchKey,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    await _ref.doc(switchKey).update({
      'isKilled': true,
      'activatedByAdminId': actingAdminId,
      'activatedAt': FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    // This is the highest blast-radius action in the admin panel (see
    // class doc comment on _requireSuperAdmin above) — it was flipping
    // a Firestore doc with no record anywhere of who did it or when,
    // so an incident review or a "wait, who turned this off?" question
    // had no answer. Logged the same way every other admin mutation
    // already is.
    await _auditLog.log(
      adminId: actingAdminId,
      action: 'killSwitch.activate',
      targetType: 'killSwitch',
      targetId: switchKey,
      targetName: switchKey,
      newValue: 'killed',
    );
  }

  Future<void> deactivate({
    required String actingAdminId,
    required String switchKey,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    await _ref.doc(switchKey).update({
      'isKilled': false,
      'deactivatedByAdminId': actingAdminId,
      'deactivatedAt': FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'killSwitch.deactivate',
      targetType: 'killSwitch',
      targetId: switchKey,
      targetName: switchKey,
      newValue: 'restored',
    );
  }

  Future<void> deleteSwitch({
    required String actingAdminId,
    required String switchKey,
  }) async {
    await _requireSuperAdmin(actingAdminId);
    await _ref.doc(switchKey).delete();

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'killSwitch.delete',
      targetType: 'killSwitch',
      targetId: switchKey,
      targetName: switchKey,
    );
  }
}
