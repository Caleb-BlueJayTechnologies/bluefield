import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/system_announcement_model.dart';
import 'platform_admin_service.dart';

class SystemAnnouncementService {
  final FirebaseFirestore _firestore;
  final PlatformAdminService _adminService;

  SystemAnnouncementService({FirebaseFirestore? firestore, PlatformAdminService? adminService})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _adminService = adminService ?? PlatformAdminService();

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(FSCollections.systemAnnouncements);

  /// Broadcasting to every company at once is high blast-radius, so
  /// this is gated the same way as managing other platform admins —
  /// super admin only, not just any authenticated admin.
  Future<void> _requireSuperAdmin(String actingAdminId) async {
    final acting = await _adminService.getCurrentAdmin();
    if (acting == null || acting.adminId != actingAdminId || !acting.canManageOtherAdmins) {
      throw Exception('Only a super admin can manage system announcements.');
    }
  }

  /// Everyone in the main app sees active, non-expired announcements —
  /// no admin gating on reads, since these are meant to be broadcast.
  Stream<List<SystemAnnouncementModel>> watchActiveAnnouncements() {
    return _ref.where('isActive', isEqualTo: true).snapshots().map((snap) {
      final announcements = snap.docs.map((d) => SystemAnnouncementModel.fromSnapshot(d)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return announcements.where((a) => a.isVisible).toList();
    });
  }

  /// All announcements including inactive/expired ones — for the
  /// admin management screen.
  Stream<List<SystemAnnouncementModel>> watchAllAnnouncements() {
    return _ref.snapshots().map((snap) {
      final announcements = snap.docs.map((d) => SystemAnnouncementModel.fromSnapshot(d)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return announcements;
    });
  }

  Future<String> createAnnouncement({
    required String actingAdminId,
    required String title,
    required String body,
    String severity = SystemAnnouncementSeverity.info,
    DateTime? expiresAt,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    if (title.trim().isEmpty || body.trim().isEmpty) {
      throw Exception('Title and body are both required.');
    }

    final ref = _ref.doc();
    await ref.set(SystemAnnouncementModel.toMapForCreate(
      title: title.trim(),
      body: body.trim(),
      severity: severity,
      createdByAdminId: actingAdminId,
      expiresAt: expiresAt,
    ));
    return ref.id;
  }

  Future<void> setActive({
    required String actingAdminId,
    required String announcementId,
    required bool isActive,
  }) async {
    await _requireSuperAdmin(actingAdminId);
    await _ref.doc(announcementId).update({'isActive': isActive});
  }

  Future<void> deleteAnnouncement({
    required String actingAdminId,
    required String announcementId,
  }) async {
    await _requireSuperAdmin(actingAdminId);
    await _ref.doc(announcementId).delete();
  }
}
