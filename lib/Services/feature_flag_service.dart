import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/feature_flag_model.dart';
import 'platform_admin_service.dart';

class FeatureFlagService {
  final FirebaseFirestore _firestore;
  final PlatformAdminService _adminService;

  FeatureFlagService({FirebaseFirestore? firestore, PlatformAdminService? adminService})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _adminService = adminService ?? PlatformAdminService();

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(FSCollections.featureFlags);

  Future<void> _requireSuperAdmin(String actingAdminId) async {
    final acting = await _adminService.getCurrentAdmin();
    if (acting == null || acting.adminId != actingAdminId || !acting.canManageOtherAdmins) {
      throw Exception('Only a super admin can manage feature flags.');
    }
  }

  /// The actual check the main app calls — no admin gating, just a
  /// read, and any app code deciding whether to show a flagged feature
  /// should use this rather than reading the collection directly.
  Future<bool> isFeatureEnabledForCompany({required String flagKey, required String companyId}) async {
    final doc = await _ref.doc(flagKey).get();
    if (!doc.exists) return false;
    return FeatureFlagModel.fromSnapshot(doc).isEnabledForCompany(companyId);
  }

  Stream<List<FeatureFlagModel>> watchAllFlags() {
    return _ref.snapshots().map((snap) {
      final flags = snap.docs.map((d) => FeatureFlagModel.fromSnapshot(d)).toList()
        ..sort((a, b) => a.flagKey.compareTo(b.flagKey));
      return flags;
    });
  }

  Future<void> createFlag({
    required String actingAdminId,
    required String flagKey,
    required String description,
    List<String> enabledCompanyIds = const [],
    int rolloutPercentage = 0,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    final trimmedKey = flagKey.trim();
    if (trimmedKey.isEmpty) {
      throw Exception('A flag key is required.');
    }
    if (rolloutPercentage < 0 || rolloutPercentage > 100) {
      throw Exception('Rollout percentage must be between 0 and 100.');
    }

    final existing = await _ref.doc(trimmedKey).get();
    if (existing.exists) {
      throw Exception('A flag with this key already exists.');
    }

    await _ref.doc(trimmedKey).set(FeatureFlagModel.toMapForCreate(
      description: description.trim(),
      enabledCompanyIds: enabledCompanyIds,
      rolloutPercentage: rolloutPercentage,
      createdByAdminId: actingAdminId,
    ));
  }

  Future<void> updateFlag({
    required String actingAdminId,
    required String flagKey,
    String? description,
    List<String>? enabledCompanyIds,
    int? rolloutPercentage,
    bool? isActive,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    if (rolloutPercentage != null && (rolloutPercentage < 0 || rolloutPercentage > 100)) {
      throw Exception('Rollout percentage must be between 0 and 100.');
    }

    final updates = <String, dynamic>{FSFields.updatedAt: FieldValue.serverTimestamp()};
    if (description != null) updates['description'] = description.trim();
    if (enabledCompanyIds != null) updates['enabledCompanyIds'] = enabledCompanyIds;
    if (rolloutPercentage != null) updates['rolloutPercentage'] = rolloutPercentage;
    if (isActive != null) updates['isActive'] = isActive;

    await _ref.doc(flagKey).update(updates);
  }

  Future<void> deleteFlag({
    required String actingAdminId,
    required String flagKey,
  }) async {
    await _requireSuperAdmin(actingAdminId);
    await _ref.doc(flagKey).delete();
  }
}
