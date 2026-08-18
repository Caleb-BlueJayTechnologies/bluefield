import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/membership.dart';
import 'messaging_service.dart';
import 'permission_service.dart';

class CrewService {
  final FirebaseFirestore _firestore;
  final MessagingService _messagingService;

  CrewService({FirebaseFirestore? firestore, MessagingService? messagingService})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _messagingService = messagingService ?? MessagingService();

  CollectionReference<Map<String, dynamic>> _crewsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.crews);
  }

  CollectionReference<Map<String, dynamic>> _employeesRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.employees);
  }

  CollectionReference<Map<String, dynamic>> _membershipsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships);
  }

  Future<void> _requirePermission({
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

  // --- Read ---

  Future<CrewModel?> getCrew({
    required String companyId,
    required String crewId,
  }) async {
    final doc = await _crewsRef(companyId).doc(crewId).get();
    if (!doc.exists) return null;
    return CrewModel.fromSnapshot(doc);
  }

  Stream<CrewModel?> watchCrew({
    required String companyId,
    required String crewId,
  }) {
    return _crewsRef(companyId)
        .doc(crewId)
        .snapshots()
        .map((doc) => doc.exists ? CrewModel.fromSnapshot(doc) : null);
  }

  Future<List<CrewModel>> getCrewsByCompany({
    required String companyId,
    bool includeArchived = false,
  }) async {
    Query<Map<String, dynamic>> query = _crewsRef(companyId);
    if (!includeArchived) {
      query = query.where(FSFields.isArchived, isEqualTo: false);
    }
    final snapshot = await query.get();
    return snapshot.docs.map((d) => CrewModel.fromSnapshot(d)).toList();
  }

  Stream<List<CrewModel>> watchCrewsByCompany({
    required String companyId,
    bool includeArchived = false,
  }) {
    Query<Map<String, dynamic>> query = _crewsRef(companyId);
    if (!includeArchived) {
      query = query.where(FSFields.isArchived, isEqualTo: false);
    }
    return query.snapshots().map(
        (snap) => snap.docs.map((d) => CrewModel.fromSnapshot(d)).toList());
  }

  // --- Create / update ---

  Future<String> createCrew({
    required String companyId,
    required String actingUserId,
    required String crewName,
    String? description,
    String? leaderId,
    String color = '#2196F3',
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.crewsCreate,
    );

    final trimmedName = crewName.trim();
    if (trimmedName.isEmpty) {
      throw Exception('A crew name is required.');
    }

    final crewRef = _crewsRef(companyId).doc();
    await crewRef.set(CrewModel.toMapForCreate(
      companyId: companyId,
      crewName: trimmedName,
      description: description,
      leaderId: leaderId,
      color: color,
      createdBy: actingUserId,
    ));

    return crewRef.id;
  }

  Future<void> updateCrew({
    required String companyId,
    required String actingUserId,
    required String crewId,
    String? crewName,
    String? description,
    bool clearLeader = false,
    String? leaderId,
    String? color,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.crewsEdit,
    );

    final updates = <String, dynamic>{
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
    if (crewName != null) {
      final trimmed = crewName.trim();
      if (trimmed.isEmpty) throw Exception('A crew name is required.');
      updates['crewName'] = trimmed;
    }
    if (description != null) updates['description'] = description.trim();
    if (clearLeader) {
      updates['leaderId'] = null;
    } else if (leaderId != null) {
      updates['leaderId'] = leaderId;
    }
    if (color != null) updates['color'] = color;

    await _crewsRef(companyId).doc(crewId).update(updates);
  }

  // --- Lifecycle: archive / restore ---

  /// Archives the crew doc only. Per Section 5, employees keep whatever
  /// crewId they had — an archived crew must not silently strip anyone's
  /// assignment. Screens showing an employee's crew need to handle a
  /// crewId that points at an archived crew gracefully (e.g. show it
  /// grayed out with an "archived" label) rather than assuming every
  /// crewId resolves to an active crew.
  Future<void> archiveCrew({
    required String companyId,
    required String actingUserId,
    required String crewId,
    String? reason,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.crewsArchive,
    );

    await _crewsRef(companyId).doc(crewId).update({
      FSFields.isArchived: true,
      FSFields.archivedAt: FieldValue.serverTimestamp(),
      FSFields.archivedBy: actingUserId,
      FSFields.archiveReason: reason,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> restoreCrew({
    required String companyId,
    required String actingUserId,
    required String crewId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.crewsRestore,
    );

    await _crewsRef(companyId).doc(crewId).update({
      FSFields.isArchived: false,
      FSFields.archivedAt: null,
      FSFields.archivedBy: null,
      FSFields.archiveReason: null,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Membership (writes to EmployeeModel.crewIds — the source of truth) ---

  /// Adds [employeeId] to [crewId]. Employees can belong to any number
  /// of crews now — this only adds the new one, it doesn't touch any
  /// existing memberships (unlike the old single-crewId model, where
  /// assigning a new crew implicitly dropped the previous one).
  Future<void> addMemberToCrew({
    required String companyId,
    required String actingUserId,
    required String crewId,
    required String employeeId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.crewsAssignMembers,
    );

    final crewDoc = await _crewsRef(companyId).doc(crewId).get();
    if (!crewDoc.exists) {
      throw Exception('Crew was not found.');
    }
    final crew = CrewModel.fromSnapshot(crewDoc);
    if (crew.isArchived) {
      throw Exception('Cannot assign members to an archived crew.');
    }

    await _employeesRef(companyId).doc(employeeId).update({
      'crewIds': FieldValue.arrayUnion([crewId]),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    final threadId = await _messagingService.findCrewThreadId(companyId: companyId, crewId: crewId);
    if (threadId != null) {
      await _messagingService.syncCrewThreadParticipants(companyId: companyId, threadId: threadId, crewId: crewId);
    }
  }

  /// Removes [employeeId] from [crewId] specifically — not from every
  /// crew they're on. The old single-crew version could just null out
  /// the one field; this needs to know which membership to drop now
  /// that there can be several.
  Future<void> removeMemberFromCrew({
    required String companyId,
    required String actingUserId,
    required String crewId,
    required String employeeId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.crewsAssignMembers,
    );

    await _employeesRef(companyId).doc(employeeId).update({
      'crewIds': FieldValue.arrayRemove([crewId]),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    final threadId = await _messagingService.findCrewThreadId(companyId: companyId, crewId: crewId);
    if (threadId != null) {
      await _messagingService.syncCrewThreadParticipants(companyId: companyId, threadId: threadId, crewId: crewId);
    }
  }

  /// Active (non-archived-membership) employees currently on this crew —
  /// used for "Select Entire Crew" job assignment, crew chat membership,
  /// and the crew details screen's member count.
  Future<List<EmployeeModel>> getActiveMembers({
    required String companyId,
    required String crewId,
  }) async {
    final employeesSnapshot = await _employeesRef(companyId)
        .where('crewIds', arrayContains: crewId)
        .get();

    if (employeesSnapshot.docs.isEmpty) return [];

    final membershipsSnapshot = await _membershipsRef(companyId)
        .where(FSFields.status, isEqualTo: FSMembershipStatus.active)
        .get();
    final activeIds = membershipsSnapshot.docs.map((d) => d.id).toSet();

    return employeesSnapshot.docs
        .map((d) => EmployeeModel.fromSnapshot(d))
        .where((e) => activeIds.contains(e.employeeId))
        .toList();
  }

  Future<int> getActiveMemberCount({
    required String companyId,
    required String crewId,
  }) async {
    final members = await getActiveMembers(companyId: companyId, crewId: crewId);
    return members.length;
  }
}
