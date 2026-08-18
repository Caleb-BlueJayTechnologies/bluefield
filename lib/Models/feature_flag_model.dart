import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// A platform-level feature flag. Stored at
/// `featureFlags/{flagKey}` — the flag's own key is the doc ID.
///
/// Two ways a company can get a flag: being explicitly listed in
/// enabledCompanyIds, OR falling into the rolloutPercentage bucket.
/// Both are checked — a company doesn't need to be in both to get the
/// flag, either is sufficient.
class FeatureFlagModel {
  final String flagKey;
  final String description;
  final List<String> enabledCompanyIds;

  /// 0-100. A company falls into this rollout based on a deterministic
  /// hash of its own ID, not randomly on each check — otherwise a
  /// company could flicker in and out of a feature between sessions.
  final int rolloutPercentage;

  final bool isActive;

  final String createdByAdminId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FeatureFlagModel({
    required this.flagKey,
    required this.description,
    this.enabledCompanyIds = const [],
    this.rolloutPercentage = 0,
    this.isActive = true,
    required this.createdByAdminId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Whether this flag is on for a given company — the actual check
  /// apps should call. Returns false immediately if the flag itself is
  /// deactivated, regardless of allowlist/rollout settings.
  bool isEnabledForCompany(String companyId) {
    if (!isActive) return false;
    if (enabledCompanyIds.contains(companyId)) return true;
    if (rolloutPercentage <= 0) return false;
    if (rolloutPercentage >= 100) return true;
    // Deterministic 0-99 bucket from the company's own ID, stable
    // across checks and app restarts.
    final bucket = companyId.hashCode.abs() % 100;
    return bucket < rolloutPercentage;
  }

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'enabledCompanyIds': enabledCompanyIds,
      'rolloutPercentage': rolloutPercentage,
      'isActive': isActive,
      'createdByAdminId': createdByAdminId,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String description,
    List<String> enabledCompanyIds = const [],
    int rolloutPercentage = 0,
    required String createdByAdminId,
  }) {
    return {
      'description': description,
      'enabledCompanyIds': enabledCompanyIds,
      'rolloutPercentage': rolloutPercentage,
      'isActive': true,
      'createdByAdminId': createdByAdminId,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory FeatureFlagModel.fromMap(String flagKey, Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    return FeatureFlagModel(
      flagKey: flagKey,
      description: map['description']?.toString() ?? '',
      enabledCompanyIds: List<String>.from(map['enabledCompanyIds'] ?? const []),
      rolloutPercentage: (map['rolloutPercentage'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] != false,
      createdByAdminId: map['createdByAdminId']?.toString() ?? '',
      createdAt: readDate(map[FSFields.createdAt]),
      updatedAt: readDate(map[FSFields.updatedAt]),
    );
  }

  factory FeatureFlagModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Feature flag document ${doc.id} has no data.');
    }
    return FeatureFlagModel.fromMap(doc.id, data);
  }
}
