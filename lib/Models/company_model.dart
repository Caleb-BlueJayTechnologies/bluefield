import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// Which customer pricing program a company was signed up under
/// (Section 22). Locked-in pricing must be stored explicitly per
/// company — never re-derived from a customer number, since customer
/// numbering can't reliably reconstruct historical pricing decisions.
class CompanyPricingProgram {
  CompanyPricingProgram._();

  static const founding = 'founding'; // Founding Company #1: free for life
  static const beta = 'beta'; // Beta Companies #2-5: locked discount
  static const earlyAdopter = 'earlyAdopter'; // #6-9: locked pricing
  static const standard = 'standard'; // #10+: public pricing

  /// Grandfathered onto an old rate when the standard tier's pricing
  /// changes — distinct from founding/beta/earlyAdopter, which are
  /// early-customer-number rewards. A company can land here at any
  /// customer number, whenever a pricing change happens and they're
  /// kept on what they originally signed up for instead of moved to
  /// the new standard rate.
  static const legacy = 'legacy';
}

/// Subscription/billing state, separate from [CompanyModel.isActive]
/// (which is the company's ability to use the app at all — e.g. a
/// manually suspended account — vs. this, which is the state of their
/// payment relationship).
class CompanySubscriptionStatus {
  CompanySubscriptionStatus._();

  static const trialing = 'trialing';
  static const active = 'active';
  static const pastDue = 'pastDue';
  static const cancelled = 'cancelled';
  static const internal = 'internal'; // BlueJay's own internal company, promo accounts
}

/// A company/tenant. Stored at `companies/{companyId}`.
///
/// Ownership access control does NOT live here — see MembershipModel,
/// which supports multiple owners per company. [originalOwnerUserId]
/// below is kept purely as historical/display information ("founded
/// by"), never used for permission checks.
class CompanyModel {
  final String companyId;
  final String companyName;

  /// The user who originally registered this company. Display/history
  /// only — query memberships where role == owner for the actual,
  /// current, possibly-multiple owner(s).
  final String originalOwnerUserId;

  // --- Activation ---
  final bool isActive;
  final DateTime? suspendedAt;
  final String? suspendedReason;

  // --- Onboarding ---
  final bool onboardingCompleted;
  final bool onboardingSkipped;

  // --- Legal acceptance ---
  final DateTime? termsAcceptedAt;
  final String? termsAcceptedByUserId;
  final DateTime? privacyPolicyAcceptedAt;

  // --- Billing / subscription (Section 22) ---
  final String pricingProgram; // CompanyPricingProgram.*
  final String subscriptionStatus; // CompanySubscriptionStatus.*
  final String subscriptionTier;

  /// Explicit locked price in cents, if this company's pricing program
  /// guarantees one (founding/beta/early adopter). Null for standard
  /// pricing, which is computed from current employee count instead.
  final int? lockedPriceCents;

  final int employeeLimit;

  /// Sequential customer number, kept for reference only — never used
  /// alone to infer pricing (see CompanyPricingProgram doc above).
  final int? customerNumber;

  // --- Platform admin fields (Section: Admin Panel) ---
  /// True only for BlueJay Technologies' own account — excluded from
  /// customer revenue/count statistics unless explicitly included.
  final bool isInternalAccount;
  /// Demo/test accounts — excluded from analytics, billing, customer
  /// numbering, and founding-slot calculations, same as internal.
  final bool isTestCompany;
  /// Private notes visible only in the Admin Panel — never surfaced
  /// to the company itself.
  final String? adminNotes;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CompanyModel({
    required this.companyId,
    required this.companyName,
    required this.originalOwnerUserId,
    required this.isActive,
    this.suspendedAt,
    this.suspendedReason,
    this.onboardingCompleted = false,
    this.onboardingSkipped = false,
    this.termsAcceptedAt,
    this.termsAcceptedByUserId,
    this.privacyPolicyAcceptedAt,
    this.pricingProgram = CompanyPricingProgram.standard,
    this.subscriptionStatus = CompanySubscriptionStatus.trialing,
    required this.subscriptionTier,
    this.lockedPriceCents,
    required this.employeeLimit,
    this.customerNumber,
    this.isInternalAccount = false,
    this.isTestCompany = false,
    this.adminNotes,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSuspended => !isActive;
  bool get hasAcceptedTerms => termsAcceptedAt != null;
  bool get hasLockedPricing => lockedPriceCents != null;
  bool get needsOnboarding => !onboardingCompleted && !onboardingSkipped;

  Map<String, dynamic> toMap() {
    return {
      'companyName': companyName,
      'originalOwnerUserId': originalOwnerUserId,
      FSFields.isActive: isActive,
      'suspendedAt': suspendedAt != null ? Timestamp.fromDate(suspendedAt!) : null,
      'suspendedReason': suspendedReason,
      'onboardingCompleted': onboardingCompleted,
      'onboardingSkipped': onboardingSkipped,
      'termsAcceptedAt':
          termsAcceptedAt != null ? Timestamp.fromDate(termsAcceptedAt!) : null,
      'termsAcceptedByUserId': termsAcceptedByUserId,
      'privacyPolicyAcceptedAt': privacyPolicyAcceptedAt != null
          ? Timestamp.fromDate(privacyPolicyAcceptedAt!)
          : null,
      'pricingProgram': pricingProgram,
      'subscriptionStatus': subscriptionStatus,
      'subscriptionTier': subscriptionTier,
      'lockedPriceCents': lockedPriceCents,
      'employeeLimit': employeeLimit,
      'customerNumber': customerNumber,
      'isInternalAccount': isInternalAccount,
      'isTestCompany': isTestCompany,
      'adminNotes': adminNotes,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyName,
    required String originalOwnerUserId,
    String pricingProgram = CompanyPricingProgram.standard,
    String subscriptionTier = 'starter',
    int? lockedPriceCents,
    int employeeLimit = 10,
    int? customerNumber,
  }) {
    return {
      'companyName': companyName,
      'originalOwnerUserId': originalOwnerUserId,
      FSFields.isActive: true,
      'suspendedAt': null,
      'suspendedReason': null,
      'onboardingCompleted': false,
      'onboardingSkipped': false,
      'termsAcceptedAt': null,
      'termsAcceptedByUserId': null,
      'privacyPolicyAcceptedAt': null,
      'pricingProgram': pricingProgram,
      'subscriptionStatus': CompanySubscriptionStatus.trialing,
      'subscriptionTier': subscriptionTier,
      'lockedPriceCents': lockedPriceCents,
      'employeeLimit': employeeLimit,
      'customerNumber': customerNumber,
      'isInternalAccount': false,
      'isTestCompany': false,
      'adminNotes': null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory CompanyModel.fromMap(String companyId, Map<String, dynamic> map) {
    return CompanyModel(
      companyId: companyId,
      companyName: map['companyName']?.toString() ?? '',
      originalOwnerUserId: map['originalOwnerUserId']?.toString() ??
          map['ownerUserId']?.toString() ?? // migration-safe: old field name
          '',
      isActive: map[FSFields.isActive] ?? true,
      suspendedAt: FSTimestamp.tryParse(map['suspendedAt']),
      suspendedReason: map['suspendedReason']?.toString(),
      onboardingCompleted: map['onboardingCompleted'] == true,
      onboardingSkipped: map['onboardingSkipped'] == true,
      termsAcceptedAt: FSTimestamp.tryParse(map['termsAcceptedAt']),
      termsAcceptedByUserId: map['termsAcceptedByUserId']?.toString(),
      privacyPolicyAcceptedAt:
          FSTimestamp.tryParse(map['privacyPolicyAcceptedAt']),
      pricingProgram:
          map['pricingProgram']?.toString() ?? CompanyPricingProgram.standard,
      subscriptionStatus: map['subscriptionStatus']?.toString() ??
          CompanySubscriptionStatus.trialing,
      subscriptionTier: map['subscriptionTier']?.toString() ?? 'starter',
      lockedPriceCents: (map['lockedPriceCents'] as num?)?.toInt(),
      employeeLimit: (map['employeeLimit'] as num?)?.toInt() ?? 10,
      customerNumber: (map['customerNumber'] as num?)?.toInt(),
      isInternalAccount: map['isInternalAccount'] == true,
      isTestCompany: map['isTestCompany'] == true,
      adminNotes: map['adminNotes']?.toString(),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory CompanyModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Company document ${doc.id} has no data.');
    }
    return CompanyModel.fromMap(doc.id, data);
  }

  CompanyModel copyWith({
    String? companyName,
    bool? isActive,
    DateTime? suspendedAt,
    String? suspendedReason,
    bool? onboardingCompleted,
    bool? onboardingSkipped,
    DateTime? termsAcceptedAt,
    String? termsAcceptedByUserId,
    DateTime? privacyPolicyAcceptedAt,
    String? pricingProgram,
    String? subscriptionStatus,
    String? subscriptionTier,
    int? lockedPriceCents,
    int? employeeLimit,
    int? customerNumber,
    bool? isInternalAccount,
    bool? isTestCompany,
    String? adminNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompanyModel(
      companyId: companyId,
      companyName: companyName ?? this.companyName,
      originalOwnerUserId: originalOwnerUserId,
      isActive: isActive ?? this.isActive,
      suspendedAt: suspendedAt ?? this.suspendedAt,
      suspendedReason: suspendedReason ?? this.suspendedReason,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      onboardingSkipped: onboardingSkipped ?? this.onboardingSkipped,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      termsAcceptedByUserId: termsAcceptedByUserId ?? this.termsAcceptedByUserId,
      privacyPolicyAcceptedAt:
          privacyPolicyAcceptedAt ?? this.privacyPolicyAcceptedAt,
      pricingProgram: pricingProgram ?? this.pricingProgram,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      lockedPriceCents: lockedPriceCents ?? this.lockedPriceCents,
      employeeLimit: employeeLimit ?? this.employeeLimit,
      customerNumber: customerNumber ?? this.customerNumber,
      isInternalAccount: isInternalAccount ?? this.isInternalAccount,
      isTestCompany: isTestCompany ?? this.isTestCompany,
      adminNotes: adminNotes ?? this.adminNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
