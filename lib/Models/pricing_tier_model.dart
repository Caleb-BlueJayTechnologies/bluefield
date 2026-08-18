import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// What a single pricing tier actually includes — stored at
/// `pricingTiers/{tierKey}`, where tierKey matches a
/// CompanyPricingProgram constant ('standard', 'earlyAdopter', 'beta',
/// 'founding', 'legacy'). Purely informational right now: nothing in
/// the app charges money based on this, since there's no billing
/// integration wired up yet. This exists so "what does Beta pricing
/// actually mean" has one real answer instead of living in someone's
/// memory.
class PricingTierModel {
  final String tierKey;
  final String displayName;
  final double monthlyPrice;
  final String description;
  final String? updatedByAdminId;
  final DateTime updatedAt;

  const PricingTierModel({
    required this.tierKey,
    required this.displayName,
    required this.monthlyPrice,
    required this.description,
    this.updatedByAdminId,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'monthlyPrice': monthlyPrice,
      'description': description,
      'updatedByAdminId': updatedByAdminId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory PricingTierModel.fromMap(String tierKey, Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    return PricingTierModel(
      tierKey: tierKey,
      displayName: map['displayName']?.toString() ?? tierKey,
      monthlyPrice: (map['monthlyPrice'] as num?)?.toDouble() ?? 0.0,
      description: map['description']?.toString() ?? '',
      updatedByAdminId: map['updatedByAdminId']?.toString(),
      updatedAt: readDate(map[FSFields.updatedAt]),
    );
  }

  factory PricingTierModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Pricing tier document ${doc.id} has no data.');
    }
    return PricingTierModel.fromMap(doc.id, data);
  }
}
