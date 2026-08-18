import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/app_user.dart';

class AdminUserService {
  final FirebaseFirestore _firestore;

  AdminUserService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _usersRef => _firestore.collection(FSCollections.users);

  /// Every user in the system, streamed live — same client-side-filter
  /// pattern already used for companies and support tickets, since at
  /// this app's scale a full collection listen is simpler and more
  /// robust than trying to predict every search-field index combo a
  /// name/email/UID search might need.
  Stream<List<AppUser>> watchAllUsers() {
    return _usersRef.orderBy(FSFields.createdAt, descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList(),
        );
  }

  Future<AppUser?> getUser(String uid) async {
    final doc = await _usersRef.doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.id, doc.data()!);
  }

  /// Live version of [getUser] + [getMembershipInfo] combined — the
  /// user doc itself streams live, and membership/company info is
  /// refetched on each emission. Used by the User Details screen so
  /// a role change, company reassignment, or profile edit shows up
  /// immediately instead of only on manual refresh.
  Stream<({AppUser user, String? companyName, String? role, bool? membershipActive})> watchUserDetail(String uid) async* {
    await for (final userDoc in _usersRef.doc(uid).snapshots()) {
      if (!userDoc.exists) continue;
      final user = AppUser.fromMap(userDoc.id, userDoc.data()!);

      final companyDoc = await _firestore.collection(FSCollections.companies).doc(user.activeCompanyId).get();
      final membershipDoc = await _firestore
          .collection(FSCollections.companies)
          .doc(user.activeCompanyId)
          .collection(FSCompanySub.memberships)
          .doc(user.uid)
          .get();

      yield (
        user: user,
        companyName: companyDoc.data()?['companyName']?.toString(),
        role: membershipDoc.data()?[FSFields.role]?.toString(),
        membershipActive: membershipDoc.data()?[FSFields.status]?.toString() == FSMembershipStatus.active,
      );
    }
  }

  /// Resolves a user's role + company name within their one active
  /// company (v1 is single-company-per-user — see AppUser.activeCompanyId's
  /// own doc comment). Returns null fields if the membership or
  /// company doc can't be found (e.g. an orphaned user record).
  Future<({String? companyName, String? role, bool? membershipActive})> getMembershipInfo(AppUser user) async {
    final companyDoc = await _firestore.collection(FSCollections.companies).doc(user.activeCompanyId).get();
    final membershipDoc = await _firestore
        .collection(FSCollections.companies)
        .doc(user.activeCompanyId)
        .collection(FSCompanySub.memberships)
        .doc(user.uid)
        .get();

    return (
      companyName: companyDoc.data()?['companyName']?.toString(),
      role: membershipDoc.data()?[FSFields.role]?.toString(),
      membershipActive: membershipDoc.data()?[FSFields.status]?.toString() == FSMembershipStatus.active,
    );
  }
}
