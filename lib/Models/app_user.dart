import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// Root-level user account. One document per Firebase Auth UID, stored
/// at `users/{uid}`. Deliberately does NOT carry a company role or
/// permission — those live on the [MembershipModel] for the company the
/// user belongs to, so that:
///   1. Company isolation is enforced by looking at membership docs,
///      not by trusting a flat field on the user's own account.
///   2. A user can (in the future) hold memberships in more than one
///      company/organization without restructuring this model.
///
/// See lib/Models/membership.dart for the per-company role/permission
/// record, and lib/Firebase/firestore_schema.dart for field constants.
class AppUser {
  final String uid;
  final String email;
  final String firstName;
  final String lastName;
  final String? preferredName;
  final String? phone;

  /// The company the app should show by default on login. A user may
  /// hold memberships elsewhere in the future, but v1 shows only this
  /// company's data.
  final String activeCompanyId;

  final bool emailVerified;
  final bool requiresPasswordChange;

  /// True once the user has finished (or explicitly skipped) the
  /// first-run onboarding checklist for their active company.
  final bool onboardingComplete;

  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.preferredName,
    this.phone,
    required this.activeCompanyId,
    required this.emailVerified,
    required this.requiresPasswordChange,
    required this.onboardingComplete,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  /// Name to show in UI — preferred name if set, otherwise first name.
  String get displayName =>
      (preferredName != null && preferredName!.trim().isNotEmpty)
          ? preferredName!.trim()
          : firstName;

  bool get hasActiveCompany => activeCompanyId.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'preferredName': preferredName,
      'phone': phone,
      'activeCompanyId': activeCompanyId,
      'emailVerified': emailVerified,
      'requiresPasswordChange': requiresPasswordChange,
      'onboardingComplete': onboardingComplete,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  /// Fields safe to pass to a new-doc `set()` call where createdAt/updatedAt
  /// should be the server clock, not the client clock.
  static Map<String, dynamic> toMapForCreate({
    required String email,
    required String firstName,
    required String lastName,
    String? preferredName,
    String? phone,
    required String activeCompanyId,
    bool emailVerified = false,
    bool requiresPasswordChange = false,
    bool onboardingComplete = false,
  }) {
    return {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'preferredName': preferredName,
      'phone': phone,
      'activeCompanyId': activeCompanyId,
      'emailVerified': emailVerified,
      'requiresPasswordChange': requiresPasswordChange,
      'onboardingComplete': onboardingComplete,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      email: map['email']?.toString() ?? '',
      firstName: map['firstName']?.toString() ?? '',
      lastName: map['lastName']?.toString() ?? '',
      preferredName: map['preferredName']?.toString(),
      phone: map['phone']?.toString(),
      activeCompanyId: map['activeCompanyId']?.toString() ?? '',
      emailVerified: map['emailVerified'] == true,
      requiresPasswordChange: map['requiresPasswordChange'] == true,
      onboardingComplete: map['onboardingComplete'] == true,
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory AppUser.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('User document ${doc.id} has no data.');
    }
    return AppUser.fromMap(doc.id, data);
  }

  AppUser copyWith({
    String? email,
    String? firstName,
    String? lastName,
    String? preferredName,
    String? phone,
    String? activeCompanyId,
    bool? emailVerified,
    bool? requiresPasswordChange,
    bool? onboardingComplete,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      uid: uid,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      preferredName: preferredName ?? this.preferredName,
      phone: phone ?? this.phone,
      activeCompanyId: activeCompanyId ?? this.activeCompanyId,
      emailVerified: emailVerified ?? this.emailVerified,
      requiresPasswordChange:
          requiresPasswordChange ?? this.requiresPasswordChange,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
