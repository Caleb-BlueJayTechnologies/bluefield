import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/app_user.dart';
import '../Models/company_model.dart';
import '../Models/membership.dart';
import 'company_service.dart';

/// Bundles everything a screen needs to know about the signed-in user
/// in their active company: who they are (AppUser), what they're
/// allowed to do (MembershipModel.role), and whether anything is
/// blocking access (disabled account, archived membership, suspended
/// company, unverified email).
class AuthUserProfile {
  final String uid;
  final String email;
  final String firstName;
  final String lastName;
  final String activeCompanyId;

  final String role; // FSRoles.*
  final String membershipStatus; // FSMembershipStatus.*

  final bool requiresPasswordChange;
  final bool emailVerified;

  final bool isCompanyActive;
  final String companySubscriptionStatus;
  final bool companyNeedsOnboarding;

  const AuthUserProfile({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.activeCompanyId,
    required this.role,
    required this.membershipStatus,
    required this.requiresPasswordChange,
    required this.emailVerified,
    required this.isCompanyActive,
    required this.companySubscriptionStatus,
    required this.companyNeedsOnboarding,
  });

  bool get isOwnerRole => role == FSRoles.owner;
  bool get isManagerRole => role == FSRoles.manager;
  bool get isEmployeeRole => role == FSRoles.employee;

  bool get isMembershipArchived => membershipStatus == FSMembershipStatus.archived;
  bool get isMembershipSuspended => membershipStatus == FSMembershipStatus.suspended;

  /// True only when every gate passes: membership active, company
  /// active, subscription not cancelled/past-due enough to block access.
  /// Screens should check this before showing normal app content.
  bool get isActive =>
      membershipStatus == FSMembershipStatus.active &&
      isCompanyActive &&
      companySubscriptionStatus != CompanySubscriptionStatus.cancelled;
}

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final CompanyService _companyService;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    CompanyService? companyService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _companyService = companyService ?? CompanyService();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Maps Firebase's error codes to messages a person can actually
  /// understand, instead of surfacing raw exception text (Section 2:
  /// "Friendly Firebase error messages").
  String friendlyAuthErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'An account with that email already exists.';
        case 'invalid-email':
          return 'That email address doesn\'t look right.';
        case 'user-disabled':
          return 'This account has been disabled. Contact your company owner.';
        case 'user-not-found':
          return 'We couldn\'t find an account with that email.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'weak-password':
          return 'Please choose a stronger password (at least 6 characters).';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'network-request-failed':
          return 'Network error — please check your connection and try again.';
        case 'requires-recent-login':
          return 'Please sign in again to complete this action.';
        default:
          return error.message ?? 'Something went wrong. Please try again.';
      }
    }
    return error.toString();
  }

  // --- Registration ---

  /// Full company + owner registration: creates the Firebase Auth
  /// account, the AppUser doc, then delegates the company/membership/
  /// employee creation to CompanyService.registerNewCompany (which does
  /// that part atomically in one batch). If the company-side creation
  /// fails, this rolls back by deleting the Firebase Auth account and
  /// the AppUser doc it just created, rather than leaving an orphaned
  /// login with no company — Section 2's "roll back partial
  /// registration failures," worked around across two separate systems
  /// (Firebase Auth and Firestore aren't jointly transactional).
  Future<UserCredential> registerCompanyOwner({
    required String companyName,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    final credential = await _auth.createUserWithEmailAndPassword(
      email: cleanEmail,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw Exception('User account was not created.');
    }

    try {
      await _firestore.collection(FSCollections.users).doc(user.uid).set(
            AppUser.toMapForCreate(
              email: cleanEmail,
              firstName: firstName.trim(),
              lastName: lastName.trim(),
              activeCompanyId: '', // filled in by registerNewCompany below
            ),
          );

      final companyId = await _companyService.registerNewCompany(
        ownerUserId: user.uid,
        companyName: companyName,
        ownerFirstName: firstName,
        ownerLastName: lastName,
        ownerEmail: cleanEmail,
      );

      await user.updateDisplayName('${firstName.trim()} ${lastName.trim()}');
      await user.sendEmailVerification();

      // registerNewCompany already set activeCompanyId via merge, but
      // confirm it's non-empty as a sanity check.
      if (companyId.trim().isEmpty) {
        throw Exception('Company registration did not return a company ID.');
      }
    } catch (e) {
      // Roll back: remove the orphaned auth account and user doc so a
      // failed registration doesn't leave a dead login behind.
      try {
        await _firestore.collection(FSCollections.users).doc(user.uid).delete();
      } catch (_) {
        // best-effort cleanup
      }
      try {
        await user.delete();
      } catch (_) {
        // best-effort cleanup
      }
      throw Exception(
          'Company registration failed and was rolled back: ${friendlyAuthErrorMessage(e)}');
    }

    return credential;
  }

  Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  // --- Login / logout / password reset ---

  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  Future<void> changePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user is currently signed in.');

    await user.updatePassword(newPassword);

    // activeCompanyId is needed to update the mirrored copy on the
    // employee doc below — fetched from the same users/{uid} doc
    // being updated right after, rather than a separate profile call.
    final userDoc = await _firestore.collection(FSCollections.users).doc(user.uid).get();
    final activeCompanyId = userDoc.data()?['activeCompanyId']?.toString();

    await _firestore.collection(FSCollections.users).doc(user.uid).update({
      'requiresPasswordChange': false,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    // Mirrored field on the employee doc — see EmployeeModel's doc
    // comment on requiresPasswordChange for why this exists at all
    // (lets a manager/owner check setup status without needing
    // users/{uid} read access widened to non-self accounts). Kept
    // best-effort: a failure here shouldn't block the password change
    // that already genuinely succeeded above.
    if (activeCompanyId != null && activeCompanyId.isNotEmpty) {
      try {
        await _firestore
            .collection(FSCollections.companies)
            .doc(activeCompanyId)
            .collection(FSCompanySub.employees)
            .doc(user.uid)
            .update({
          'requiresPasswordChange': false,
          FSFields.updatedAt: FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Non-fatal — see comment above.
      }
    }
  }

  /// Lets a manager/owner get a stuck teammate unblocked if the
  /// original temp password was lost before they ever signed in —
  /// uses Firebase's own built-in reset-email flow rather than
  /// storing or retrieving the actual temp password anywhere, which
  /// would mean keeping a plaintext password sitting in Firestore.
  /// Works for any account regardless of whether the caller knows
  /// their current password, since it's the same flow Firebase itself
  /// uses for "forgot password."
  Future<void> sendPasswordSetupEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // --- Email verification ---

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user is currently signed in.');
    await user.sendEmailVerification();
  }

  /// Firebase's emailVerified flag is only refreshed locally after a
  /// reload — call this before checking [isEmailVerified] if the user
  /// might have just clicked the verification link in another tab.
  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  // --- Profile ---

  Future<AppUser> getCurrentAppUser() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user is currently signed in.');

    final doc = await _firestore.collection(FSCollections.users).doc(user.uid).get();
    if (!doc.exists) throw Exception('User document was not found.');
    return AppUser.fromSnapshot(doc);
  }

  Future<AuthUserProfile> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user is currently signed in.');

    final appUser = await getCurrentAppUser();

    if (!appUser.hasActiveCompany) {
      throw Exception('User is not linked to a company.');
    }

    final membershipDoc = await _firestore
        .collection(FSCollections.companies)
        .doc(appUser.activeCompanyId)
        .collection(FSCompanySub.memberships)
        .doc(user.uid)
        .get();

    if (!membershipDoc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(membershipDoc);

    final companyDoc = await _firestore
        .collection(FSCollections.companies)
        .doc(appUser.activeCompanyId)
        .get();
    if (!companyDoc.exists) {
      throw Exception('Company was not found.');
    }
    final company = CompanyModel.fromSnapshot(companyDoc);

    return AuthUserProfile(
      uid: user.uid,
      email: appUser.email,
      firstName: appUser.firstName,
      lastName: appUser.lastName,
      activeCompanyId: appUser.activeCompanyId,
      role: membership.role,
      membershipStatus: membership.status,
      requiresPasswordChange: appUser.requiresPasswordChange,
      emailVerified: user.emailVerified,
      isCompanyActive: company.isActive,
      companySubscriptionStatus: company.subscriptionStatus,
      companyNeedsOnboarding: company.needsOnboarding,
    );
  }

  /// Live version of [getCurrentUserProfile] — AuthGate previously did a
  /// one-time fetch, so a company suspension, membership archival/
  /// suspension, role change, or subscription cancellation that
  /// happened while someone was already using the app only took effect
  /// after a full sign-out/sign-in or app restart. This listens to the
  /// user doc, membership doc, and company doc together and re-emits a
  /// fresh AuthUserProfile whenever any of them change, so those
  /// blocking conditions are enforced live instead.
  ///
  /// activeCompanyId is resolved once up front (there is currently no
  /// multi-company/company-switching feature in this app — it's only
  /// ever set at registration) and used to pin which membership/company
  /// docs are listened to for the lifetime of the subscription.
  Stream<AuthUserProfile> watchCurrentUserProfile() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.error(Exception('No user is currently signed in.'));
    }

    late final StreamController<AuthUserProfile> controller;
    final subscriptions = <StreamSubscription>[];

    AppUser? latestAppUser;
    MembershipModel? latestMembership;
    CompanyModel? latestCompany;

    void emitIfReady() {
      final appUser = latestAppUser;
      final membership = latestMembership;
      final company = latestCompany;
      if (appUser == null || membership == null || company == null) return;

      controller.add(AuthUserProfile(
        uid: user.uid,
        email: appUser.email,
        firstName: appUser.firstName,
        lastName: appUser.lastName,
        activeCompanyId: appUser.activeCompanyId,
        role: membership.role,
        membershipStatus: membership.status,
        requiresPasswordChange: appUser.requiresPasswordChange,
        emailVerified: user.emailVerified,
        isCompanyActive: company.isActive,
        companySubscriptionStatus: company.subscriptionStatus,
        companyNeedsOnboarding: company.needsOnboarding,
      ));
    }

    Future<void> start() async {
      final appUser = await getCurrentAppUser();
      if (!appUser.hasActiveCompany) {
        controller.addError(Exception('User is not linked to a company.'));
        return;
      }
      latestAppUser = appUser;
      final companyId = appUser.activeCompanyId;

      subscriptions.add(
        _firestore.collection(FSCollections.users).doc(user.uid).snapshots().listen(
          (doc) {
            if (!doc.exists) return;
            latestAppUser = AppUser.fromSnapshot(doc);
            emitIfReady();
          },
          onError: controller.addError,
        ),
      );

      subscriptions.add(
        _firestore
            .collection(FSCollections.companies)
            .doc(companyId)
            .collection(FSCompanySub.memberships)
            .doc(user.uid)
            .snapshots()
            .listen(
          (doc) {
            if (!doc.exists) {
              controller.addError(Exception('You do not have access to this company.'));
              return;
            }
            latestMembership = MembershipModel.fromSnapshot(doc);
            emitIfReady();
          },
          onError: controller.addError,
        ),
      );

      subscriptions.add(
        _firestore.collection(FSCollections.companies).doc(companyId).snapshots().listen(
          (doc) {
            if (!doc.exists) {
              controller.addError(Exception('Company was not found.'));
              return;
            }
            latestCompany = CompanyModel.fromSnapshot(doc);
            emitIfReady();
          },
          onError: controller.addError,
        ),
      );
    }

    controller = StreamController<AuthUserProfile>(
      onListen: () {
        start().catchError((Object error) {
          controller.addError(error);
        });
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }

  // --- Account deletion ---

  /// Deletes the current user's own account. If they're the sole active
  /// owner of their active company, this refuses and asks them to
  /// transfer ownership first (Section 2: "Owner transfer process
  /// before deleting an owner account"). Company-side records
  /// (membership, employee profile, historical time/job data) are
  /// archived rather than deleted, matching the plan's archive-not-
  /// delete philosophy — only the Firebase Auth account and the
  /// personal users/{uid} doc are actually removed.
  Future<void> deleteMyAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user is currently signed in.');

    final appUser = await getCurrentAppUser();

    if (appUser.hasActiveCompany) {
      final membershipRef = _firestore
          .collection(FSCollections.companies)
          .doc(appUser.activeCompanyId)
          .collection(FSCompanySub.memberships)
          .doc(user.uid);

      final membershipDoc = await membershipRef.get();
      if (membershipDoc.exists) {
        final membership = MembershipModel.fromSnapshot(membershipDoc);

        if (membership.isOwner) {
          final ownerCount =
              await _companyService.getActiveOwnerCount(appUser.activeCompanyId);
          if (ownerCount <= 1) {
            throw Exception(
                'You are the only owner of this company. Promote another owner before deleting your account.');
          }
        }

        await membershipRef.update({
          FSFields.status: FSMembershipStatus.archived,
          FSFields.archivedAt: FieldValue.serverTimestamp(),
          FSFields.archiveReason: 'Account deleted by user',
          FSFields.updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }

    await _firestore.collection(FSCollections.users).doc(user.uid).delete();
    await user.delete();
  }
}
