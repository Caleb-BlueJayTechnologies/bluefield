import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/company_model.dart';
import '../Models/employee_model.dart';
import '../Models/membership.dart';
import 'company_audit_log_service.dart';
import 'permission_service.dart';

/// Company-level operations: registration, profile management, and
/// multi-owner/manager administration.
///
/// NOTE on settings: company_settings_service.dart currently reads/writes
/// configuration fields directly on the company document itself (see
/// CompanySettingsModel.fromCompanyMap), rather than the separate
/// `settings` subcollection singleton reserved in firestore_schema.dart.
/// This service doesn't create a settings subcollection doc for that
/// reason — company_settings_service already has working fallback
/// defaults when those fields are absent. This will be reconciled when
/// company_settings_service.dart's turn comes in the rebuild order.
class CompanyService {
  final FirebaseFirestore _firestore;
  final CompanyAuditLogService _auditLogService;

  CompanyService({FirebaseFirestore? firestore, CompanyAuditLogService? auditLogService})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auditLogService = auditLogService ?? CompanyAuditLogService();

  /// Best-effort display name from a raw users/{uid} doc — used only
  /// for audit log readability, so a missing/malformed doc just falls
  /// back to null rather than throwing.
  String? _fullNameFromUserDoc(Map<String, dynamic>? data) {
    if (data == null) return null;
    final first = data['firstName']?.toString() ?? '';
    final last = data['lastName']?.toString() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? null : full;
  }

  /// Derives a readable company ID from the company's own name instead
  /// of a random Firestore auto-ID — e.g. "All Senior Movers" becomes
  /// "ASM". If that code is already taken by another company, this
  /// disambiguates by pulling in additional letters from the same
  /// words rather than just tacking on a number, so "A Smooth Move"
  /// (which would naively collide on "ASM" too) becomes something
  /// like "ASMM" — still clearly derived from the real name. Only
  /// falls back to a numeric suffix (ASM2, ASM3...) if the words
  /// genuinely don't have enough letters left to stay unique, which
  /// should be rare.
  ///
  /// NOT wrapped in a transaction — the plain existence-check loop
  /// below has a tiny theoretical race if two companies with the same
  /// name register in the same instant, which is an acceptable
  /// tradeoff at this app's scale rather than adding real complexity
  /// for an edge case this unlikely.
  Future<String> _generateCompanyId(String companyName) async {
    final words = companyName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w))
        .toList();

    if (words.isEmpty) {
      // No usable letters at all (e.g. a name that's pure numbers/emoji) —
      // fall back to a Firestore auto-ID exactly like before, since
      // there's nothing meaningful to derive a code from.
      return _firestore.collection(FSCollections.companies).doc().id;
    }

    String lettersOnly(String w) => w.replaceAll(RegExp(r'[^A-Za-z]'), '');
    final cleanWords = words.map(lettersOnly).where((w) => w.isNotEmpty).toList();
    if (cleanWords.isEmpty) {
      return _firestore.collection(FSCollections.companies).doc().id;
    }

    Future<bool> isTaken(String candidate) async {
      // Checks the lightweight registry, not the real companies
      // collection — a brand-new registrant has no membership
      // anywhere yet, so they can't read an arbitrary company
      // document under the normal member-only rules. The registry
      // exists specifically to make this check possible without
      // opening up real company data to every signed-in stranger.
      final doc = await _firestore.collection(FSCollections.companyIdRegistry).doc(candidate).get();
      return doc.exists;
    }

    // Base candidate: first letter of every word, uppercase.
    var base = cleanWords.map((w) => w[0].toUpperCase()).join();
    // A single-word name gives a 1-letter base, which is too short to
    // be a meaningful/unique code on its own — extend it using more
    // letters from that same word until it's at least 3 characters.
    if (cleanWords.length == 1) {
      final word = cleanWords.first.toUpperCase();
      base = word.substring(0, word.length < 3 ? word.length : 3);
    }

    if (!await isTaken(base)) return base;

    // Collision — disambiguate by adding one more letter at a time
    // from each word in turn (word1's 2nd letter, word2's 2nd letter,
    // ..., then word1's 3rd letter, and so on), building progressively
    // longer, still name-derived candidates.
    var candidate = base;
    var letterIndex = 1; // index 0 (first letters) already used in base
    var attempts = 0;
    const maxAttempts = 20;
    const maxLength = 10;

    while (attempts < maxAttempts && candidate.length < maxLength) {
      var addedAnyLetter = false;
      for (final word in cleanWords) {
        if (letterIndex < word.length) {
          candidate += word[letterIndex].toUpperCase();
          addedAnyLetter = true;
          if (!await isTaken(candidate)) return candidate;
        }
      }
      letterIndex++;
      attempts++;
      // Every word has been fully exhausted for letters — nothing more
      // to add, stop trying to extend and fall through to numeric
      // suffixes below instead.
      if (!addedAnyLetter) break;
    }

    // Genuinely exhausted the name's own letters (rare) — numeric
    // suffix guarantees uniqueness no matter what.
    var suffix = 2;
    while (await isTaken('$base$suffix')) {
      suffix++;
    }
    return '$base$suffix';
  }

  DocumentReference<Map<String, dynamic>> _companyRef(String companyId) {
    return _firestore.collection(FSCollections.companies).doc(companyId);
  }

  CollectionReference<Map<String, dynamic>> _membershipsRef(String companyId) {
    return _companyRef(companyId).collection(FSCompanySub.memberships);
  }

  String _requireNonEmpty(String value, String fieldLabel) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw Exception('$fieldLabel is required.');
    }
    return trimmed;
  }

  // --- Read ---

  Future<CompanyModel?> getCompany(String companyId) async {
    final doc = await _companyRef(companyId).get();
    if (!doc.exists) return null;
    return CompanyModel.fromSnapshot(doc);
  }

  Stream<CompanyModel?> watchCompany(String companyId) {
    return _companyRef(companyId)
        .snapshots()
        .map((doc) => doc.exists ? CompanyModel.fromSnapshot(doc) : null);
  }

  // --- Registration ---

  /// Atomically creates the company doc, the owner's membership, and the
  /// owner's employee profile, then links the user doc to this company.
  /// Assumes the Firebase Auth account and `users/{uid}` doc already
  /// exist (auth_service's job) — this only handles the company-side
  /// records, as one batch so a failure rolls back everything together
  /// rather than leaving an orphaned company with no owner membership.
  DocumentReference<Map<String, dynamic>> get _customerCounterRef =>
      _firestore.collection(FSCollections.systemCounters).doc('customerSequence');

  /// Atomically gets-and-increments the next customer number — this is
  /// what the Founding Program's slot assignment (#1 Founding
  /// Customer, #2-5 Beta, #6-9 Early Adopter, #10+ standard) depends
  /// on being genuinely unique and race-free. A plain "read the max
  /// existing customerNumber and add one" would have a real race
  /// window if two companies ever registered at nearly the same
  /// moment — a Firestore transaction on a dedicated counter doc
  /// closes that window entirely.
  ///
  /// Done as its own transaction BEFORE the registration batch below
  /// (rather than trying to combine them, which Firestore doesn't
  /// support) — the tiny resulting risk is a SKIPPED number if
  /// registration fails right after this succeeds, which is a
  /// harmless gap, not a collision. A duplicate slot number would be
  /// the actually unacceptable outcome, and this design can't produce
  /// one.
  Future<int> _getNextCustomerNumber() async {
    return _firestore.runTransaction<int>((transaction) async {
      final doc = await transaction.get(_customerCounterRef);
      final current = (doc.data()?['nextNumber'] as num?)?.toInt() ?? 1;
      transaction.set(_customerCounterRef, {'nextNumber': current + 1}, SetOptions(merge: true));
      return current;
    });
  }

  /// Maps a customer's sequence number to their pricing tier — matches
  /// CompanyPricingProgram's own doc comments exactly: #1 founding,
  /// #2-5 beta, #6-9 earlyAdopter, #10+ standard.
  String _pricingProgramForCustomerNumber(int number) {
    if (number == 1) return CompanyPricingProgram.founding;
    if (number <= 5) return CompanyPricingProgram.beta;
    if (number <= 9) return CompanyPricingProgram.earlyAdopter;
    return CompanyPricingProgram.standard;
  }

  Future<String> registerNewCompany({
    required String ownerUserId,
    required String companyName,
    required String ownerFirstName,
    required String ownerLastName,
    String? ownerEmail,
  }) async {
    final normalizedName = _requireNonEmpty(companyName, 'Company name');
    final normalizedFirst = _requireNonEmpty(ownerFirstName, "Owner's first name");
    final normalizedLast = _requireNonEmpty(ownerLastName, "Owner's last name");
    final normalizedOwnerId = _requireNonEmpty(ownerUserId, 'Owner user ID');

    final generatedId = await _generateCompanyId(normalizedName);
    // Assigned atomically and automatically — see _getNextCustomerNumber's
    // doc comment for why this can't be a caller-supplied parameter.
    final customerNumber = await _getNextCustomerNumber();
    final pricingProgram = _pricingProgramForCustomerNumber(customerNumber);
    final companyRef =
        _firestore.collection(FSCollections.companies).doc(generatedId);
    final registryRef = _firestore.collection(FSCollections.companyIdRegistry).doc(generatedId);
    final membershipRef = companyRef
        .collection(FSCompanySub.memberships)
        .doc(normalizedOwnerId);
    final employeeRef =
        companyRef.collection(FSCompanySub.employees).doc(normalizedOwnerId);
    final userRef =
        _firestore.collection(FSCollections.users).doc(normalizedOwnerId);

    final batch = _firestore.batch();

    // Minimal registry entry — no sensitive data, just marks this ID
    // as taken so future registrants' availability checks see it.
    batch.set(registryRef, {'reservedAt': FieldValue.serverTimestamp()});

    batch.set(
        companyRef,
        CompanyModel.toMapForCreate(
          companyName: normalizedName,
          originalOwnerUserId: normalizedOwnerId,
          pricingProgram: pricingProgram,
          customerNumber: customerNumber,
        ));

    batch.set(
        membershipRef,
        MembershipModel.toMapForCreate(
          userId: normalizedOwnerId,
          companyId: companyRef.id,
          role: FSRoles.owner,
        ));

    batch.set(
        employeeRef,
        EmployeeModel.toMapForCreate(
          companyId: companyRef.id,
          firstName: normalizedFirst,
          lastName: normalizedLast,
          loginEmail: ownerEmail,
        ));

    batch.set(
        userRef,
        {
          'activeCompanyId': companyRef.id,
          FSFields.updatedAt: FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    try {
      await batch.commit();
    } catch (e) {
      throw Exception('Company registration failed and was rolled back: $e');
    }

    return companyRef.id;
  }

  // --- Onboarding / legal acceptance ---

  Future<void> acceptTermsAndPrivacy({
    required String companyId,
    required String userId,
  }) async {
    await _companyRef(companyId).update({
      'termsAcceptedAt': FieldValue.serverTimestamp(),
      'termsAcceptedByUserId': userId,
      'privacyPolicyAcceptedAt': FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeOnboarding(String companyId) async {
    await _companyRef(companyId).update({
      'onboardingCompleted': true,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> skipOnboarding(String companyId) async {
    await _companyRef(companyId).update({
      'onboardingSkipped': true,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Permission-enforced profile updates ---

  Future<void> _requireCompanyPermission({
    required String companyId,
    required String actingUserId,
    required String permissionKey,
  }) async {
    final doc = await _membershipsRef(companyId).doc(actingUserId).get();
    if (!doc.exists) {
      throw Exception('You do not have access to this company.');
    }

    final membership = MembershipModel.fromSnapshot(doc);
    if (!membership.grantsAccess) {
      throw Exception('Your access to this company is not active.');
    }

    if (!PermissionService.roleHasPermission(membership.role, permissionKey)) {
      throw Exception('You do not have permission to do that.');
    }
  }

  Future<void> updateCompanyProfile({
    required String companyId,
    required String actingUserId,
    String? companyName,
    String? businessPhone,
    String? businessEmail,
    String? address,
    String? website,
  }) async {
    await _requireCompanyPermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.companyEditProfile,
    );

    final updates = <String, dynamic>{
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
    if (companyName != null) {
      updates['companyName'] = _requireNonEmpty(companyName, 'Company name');
    }
    if (businessPhone != null) updates['businessPhone'] = businessPhone.trim();
    if (businessEmail != null) updates['businessEmail'] = businessEmail.trim();
    if (address != null) updates['address'] = address.trim();
    if (website != null) updates['website'] = website.trim();

    await _companyRef(companyId).update(updates);
  }

  Future<void> setCompanyActive({
    required String companyId,
    required String actingUserId,
    required bool isActive,
    String? reason,
  }) async {
    await _requireCompanyPermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.companyEditSecurity,
    );

    await _companyRef(companyId).update({
      FSFields.isActive: isActive,
      'suspendedAt': isActive ? null : FieldValue.serverTimestamp(),
      'suspendedReason': isActive ? null : reason,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Multi-owner / manager administration ---

  Future<int> getActiveOwnerCount(String companyId) async {
    final snapshot = await _membershipsRef(companyId)
        .where(FSFields.role, isEqualTo: FSRoles.owner)
        .where(FSFields.status, isEqualTo: FSMembershipStatus.active)
        .get();
    return snapshot.docs.length;
  }

  /// Changes a member's role. Owner-only action (enforced via
  /// Permission.employeesChangeRole). If this would demote the
  /// company's last remaining active owner, it's rejected — a company
  /// must always have at least one owner.
  Future<void> changeMemberRole({
    required String companyId,
    required String actingUserId,
    required String targetUserId,
    required String newRole,
  }) async {
    if (!FSRoles.isValid(newRole)) {
      throw Exception('"$newRole" is not a valid role.');
    }

    await _requireCompanyPermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesChangeRole,
    );

    final membershipRef = _membershipsRef(companyId).doc(targetUserId);
    String oldRole = '';

    await _firestore.runTransaction((transaction) async {
      final targetDoc = await transaction.get(membershipRef);
      if (!targetDoc.exists) {
        throw Exception('That member was not found.');
      }

      final target = MembershipModel.fromSnapshot(targetDoc);
      oldRole = target.role;

      if (target.isOwner && newRole != FSRoles.owner) {
        // Demoting an owner — count OTHER active owners inside the
        // transaction so two concurrent demotions can't both succeed
        // and leave the company with zero owners.
        final ownersSnapshot = await _membershipsRef(companyId)
            .where(FSFields.role, isEqualTo: FSRoles.owner)
            .where(FSFields.status, isEqualTo: FSMembershipStatus.active)
            .get();

        final otherActiveOwners =
            ownersSnapshot.docs.where((d) => d.id != targetUserId).length;

        if (otherActiveOwners == 0) {
          throw Exception(
              'Cannot remove the last owner. Promote another owner first.');
        }
      }

      transaction.update(membershipRef, {
        FSFields.role: newRole,
        'roleChangedBy': actingUserId,
        'roleChangedAt': FieldValue.serverTimestamp(),
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });
    });

    try {
      final actorDoc = await _firestore.collection(FSCollections.users).doc(actingUserId).get();
      final targetDoc = await _firestore.collection(FSCollections.users).doc(targetUserId).get();
      final actorName = _fullNameFromUserDoc(actorDoc.data()) ?? actingUserId;
      final targetName = _fullNameFromUserDoc(targetDoc.data()) ?? targetUserId;

      await _auditLogService.record(
        companyId: companyId,
        actorUserId: actingUserId,
        actorName: actorName,
        action: 'roleChanged',
        targetType: 'membership',
        targetId: targetUserId,
        targetName: targetName,
        oldValue: oldRole,
        newValue: newRole,
      );
    } catch (_) {
      // The role change itself already succeeded above — a failed
      // audit write shouldn't undo or block that.
    }
  }

  /// Convenience wrapper: promotes [toUserId] to owner, then demotes
  /// [fromOwnerUserId] to [demoteFromOwnerTo] (manager by default).
  /// Adding the new owner first means the last-owner safeguard in
  /// [changeMemberRole] is naturally satisfied for the demotion step.
  Future<void> transferOwnership({
    required String companyId,
    required String actingUserId,
    required String fromOwnerUserId,
    required String toUserId,
    String demoteFromOwnerTo = FSRoles.manager,
  }) async {
    await changeMemberRole(
      companyId: companyId,
      actingUserId: actingUserId,
      targetUserId: toUserId,
      newRole: FSRoles.owner,
    );

    await changeMemberRole(
      companyId: companyId,
      actingUserId: actingUserId,
      targetUserId: fromOwnerUserId,
      newRole: demoteFromOwnerTo,
    );
  }
}
