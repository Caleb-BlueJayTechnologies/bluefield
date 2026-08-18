import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/pricing_tier_model.dart';
import 'platform_admin_service.dart';

class PricingTierService {
  final FirebaseFirestore _firestore;
  final PlatformAdminService _adminService;

  PricingTierService({FirebaseFirestore? firestore, PlatformAdminService? adminService})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _adminService = adminService ?? PlatformAdminService();

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(FSCollections.pricingTiers);

  Future<void> _requireSuperAdmin(String actingAdminId) async {
    final acting = await _adminService.getCurrentAdmin();
    if (acting == null || acting.adminId != actingAdminId || !acting.canManageOtherAdmins) {
      throw Exception('Only a super admin can manage pricing tier configuration.');
    }
  }

  Stream<List<PricingTierModel>> watchAllTiers() {
    return _ref.snapshots().map((snap) {
      final tiers = snap.docs.map((d) => PricingTierModel.fromSnapshot(d)).toList()
        ..sort((a, b) => a.monthlyPrice.compareTo(b.monthlyPrice));
      return tiers;
    });
  }

  Future<PricingTierModel?> getTier(String tierKey) async {
    final doc = await _ref.doc(tierKey).get();
    if (!doc.exists) return null;
    return PricingTierModel.fromSnapshot(doc);
  }

  /// Creates or fully overwrites a tier's configuration — set() rather
  /// than a separate create/update split, since a tier's existence is
  /// really just "does this doc have data," not something with its
  /// own create-vs-edit lifecycle the way a company or employee has.
  Future<void> saveTier({
    required String actingAdminId,
    required String tierKey,
    required String displayName,
    required double monthlyPrice,
    required String description,
  }) async {
    await _requireSuperAdmin(actingAdminId);

    if (tierKey.trim().isEmpty) {
      throw Exception('A tier key is required.');
    }
    if (monthlyPrice < 0) {
      throw Exception('Monthly price cannot be negative.');
    }

    await _ref.doc(tierKey.trim()).set(PricingTierModel(
          tierKey: tierKey.trim(),
          displayName: displayName.trim(),
          monthlyPrice: monthlyPrice,
          description: description.trim(),
          updatedByAdminId: actingAdminId,
          updatedAt: DateTime.now(),
        ).toMap());
  }

  Future<void> deleteTier({
    required String actingAdminId,
    required String tierKey,
  }) async {
    await _requireSuperAdmin(actingAdminId);
    await _ref.doc(tierKey).delete();
  }
}
