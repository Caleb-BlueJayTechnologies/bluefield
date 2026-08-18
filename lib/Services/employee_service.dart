import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/employee_model.dart';
import '../Models/membership.dart';
import 'company_audit_log_service.dart';
import 'messaging_service.dart';
import 'permission_service.dart';

/// Bundles an employee's HR profile with their current membership
/// (role/status), for screens that need both without doing two separate
/// lookups themselves — e.g. the employee list, which needs to show
/// role and filter out archived people, but also show job title/crew.
class EmployeeWithMembership {
  final EmployeeModel employee;
  final MembershipModel membership;

  const EmployeeWithMembership({
    required this.employee,
    required this.membership,
  });

  String get employeeId => employee.employeeId;
  bool get isActive => membership.isActive;
  bool get isArchived => membership.isArchived;
  String get role => membership.role;
}

/// Employee profile management (Section 4). Role/status changes are
/// NOT handled here — see CompanyService.changeMemberRole, since role
/// lives on MembershipModel, the single source of truth for access.
/// This service only manages the HR/profile side (name, title, crew,
/// hire date, overrides) plus the archive/restore lifecycle, which
/// touches both the employee doc AND the membership doc together since
/// archiving must revoke access immediately.
class EmployeeService {
  final FirebaseFirestore _firestore;
  final MessagingService _messagingService;
  final CompanyAuditLogService _auditLogService;

  EmployeeService({FirebaseFirestore? firestore, MessagingService? messagingService, CompanyAuditLogService? auditLogService})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _messagingService = messagingService ?? MessagingService(),
        _auditLogService = auditLogService ?? CompanyAuditLogService();

  /// Best-effort display name lookup for audit log readability — a
  /// missing/malformed doc just falls back to null rather than
  /// throwing, since this should never block the actual action.
  Future<String?> _fullNameForUser(String userId) async {
    final doc = await _firestore.collection(FSCollections.users).doc(userId).get();
    final data = doc.data();
    if (data == null) return null;
    final first = data['firstName']?.toString() ?? '';
    final last = data['lastName']?.toString() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? null : full;
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

  Future<EmployeeModel?> getEmployee({
    required String companyId,
    required String employeeId,
  }) async {
    final doc = await _employeesRef(companyId).doc(employeeId).get();
    if (!doc.exists) return null;
    return EmployeeModel.fromSnapshot(doc);
  }

  /// Self-heal for an account whose employees/{uid} doc has gone
  /// missing — whether from an accidental Console deletion, a
  /// partially-applied batch write, or anything else. Rebuilds it from
  /// their users/{uid} doc (which every real account has) rather than
  /// requiring a manual Firestore edit. Returns the existing record
  /// unchanged if one's already there — safe to call unconditionally
  /// any time an employee record is expected but might not be found.
  Future<EmployeeModel> ensureEmployeeRecordExists({
    required String companyId,
    required String userId,
  }) async {
    final existing = await getEmployee(companyId: companyId, employeeId: userId);
    if (existing != null) return existing;

    final userDoc = await _firestore.collection(FSCollections.users).doc(userId).get();
    final userData = userDoc.data();
    if (userData == null) {
      throw Exception('Cannot rebuild this employee record — no user account was found either.');
    }

    final firstName = userData['firstName']?.toString().trim();
    final lastName = userData['lastName']?.toString().trim();

    await _employeesRef(companyId).doc(userId).set(EmployeeModel.toMapForCreate(
          companyId: companyId,
          firstName: (firstName?.isNotEmpty ?? false) ? firstName! : 'Unknown',
          lastName: (lastName?.isNotEmpty ?? false) ? lastName! : 'Employee',
          phone: userData['phone']?.toString(),
          loginEmail: userData['email']?.toString(),
        ));

    final rebuilt = await getEmployee(companyId: companyId, employeeId: userId);
    if (rebuilt == null) {
      throw Exception('Employee record could not be rebuilt.');
    }
    return rebuilt;
  }

  Stream<EmployeeModel?> watchEmployee({
    required String companyId,
    required String employeeId,
  }) {
    return _employeesRef(companyId)
        .doc(employeeId)
        .snapshots()
        .map((doc) => doc.exists ? EmployeeModel.fromSnapshot(doc) : null);
  }

  /// All employee profiles paired with their membership, optionally
  /// including archived ones. Firestore has no server-side join, so
  /// this fetches employees then cross-references memberships client
  /// side — fine for the 5-100 employee target market this app is
  /// built for; would need restructuring at much larger scale.
  ///
  /// Driven off MEMBERSHIPS, not employees — memberships is the actual
  /// source of truth for "who belongs to this company and are they
  /// active/archived" (see archiveEmployee/restoreEmployee above, which
  /// only ever touch the membership doc, never the employee doc). An
  /// earlier version of this method iterated the employees collection
  /// instead and looked up a matching membership, silently DROPPING any
  /// active membership whose employees/{uid} doc was missing — that's
  /// exactly what caused the employer dashboard's employee count to
  /// disagree with the admin panel's (8 vs 10) for a company with
  /// orphaned membership docs. Rather than dropping those, self-heal
  /// them on read via ensureEmployeeRecordExists, same as
  /// settings_screen.dart already does for the signed-in user's own
  /// record.
  Future<List<EmployeeWithMembership>> getEmployeesByCompany({
    required String companyId,
    bool includeArchived = false,
  }) async {
    final employeesSnapshot = await _employeesRef(companyId).get();
    final membershipsSnapshot = await _membershipsRef(companyId).get();

    final employeesById = {
      for (final doc in employeesSnapshot.docs)
        doc.id: EmployeeModel.fromSnapshot(doc),
    };

    final combined = <EmployeeWithMembership>[];
    for (final doc in membershipsSnapshot.docs) {
      final membership = MembershipModel.fromSnapshot(doc);
      if (!includeArchived && membership.isArchived) continue;

      var employee = employeesById[membership.membershipId];
      if (employee == null) {
        try {
          employee = await ensureEmployeeRecordExists(
            companyId: companyId,
            userId: membership.membershipId,
          );
        } catch (_) {
          continue; // no users/{uid} doc to rebuild from either — truly orphaned, skip
        }
      }
      combined.add(EmployeeWithMembership(employee: employee, membership: membership));
    }
    return combined;
  }

  /// Live version of getEmployeesByCompany — see that method's doc
  /// comment for why this is driven off the memberships collection
  /// rather than employees. Listening on memberships also fixes a
  /// second, related staleness bug: archiveEmployee/restoreEmployee
  /// only ever write to the membership doc, so a stream that only
  /// listened for employees-collection changes (the old behavior)
  /// would never fire when an employee was archived or restored —
  /// screens watching this stream would keep showing the pre-archive
  /// state until something unrelated happened to refresh them.
  Stream<List<EmployeeWithMembership>> watchEmployeesByCompany({
    required String companyId,
    bool includeArchived = false,
  }) {
    return _membershipsRef(companyId).snapshots().asyncMap((membershipsSnapshot) async {
      final employeesSnapshot = await _employeesRef(companyId).get();
      final employeesById = {
        for (final doc in employeesSnapshot.docs)
          doc.id: EmployeeModel.fromSnapshot(doc),
      };

      final combined = <EmployeeWithMembership>[];
      for (final doc in membershipsSnapshot.docs) {
        final membership = MembershipModel.fromSnapshot(doc);
        if (!includeArchived && membership.isArchived) continue;

        var employee = employeesById[membership.membershipId];
        if (employee == null) {
          try {
            employee = await ensureEmployeeRecordExists(
              companyId: companyId,
              userId: membership.membershipId,
            );
          } catch (_) {
            continue;
          }
        }
        combined.add(EmployeeWithMembership(employee: employee, membership: membership));
      }
      return combined;
    });
  }

  /// Employees on a given crew — crewIds on the employee doc is the
  /// single source of truth for crew rostering (see crew_model.dart).
  Future<List<EmployeeModel>> getEmployeesByCrew({
    required String companyId,
    required String crewId,
  }) async {
    final snapshot = await _employeesRef(companyId)
        .where('crewIds', arrayContains: crewId)
        .get();
    return snapshot.docs.map((d) => EmployeeModel.fromSnapshot(d)).toList();
  }

  // --- Create ---

  /// Creates the HR profile for a user who already has a membership
  /// (e.g. from an accepted invitation or CompanyService.registerNewCompany).
  /// This does not create the membership itself.
  Future<void> createEmployeeProfile({
    required String companyId,
    required String actingUserId,
    required String employeeId,
    required String firstName,
    required String lastName,
    String? preferredName,
    String? jobTitle,
    List<String> crewIds = const [],
    String? phone,
    String? loginEmail,
    DateTime? hireDate,
    String employmentType = EmploymentType.fullTime,
    String? employeeNumber,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesCreate,
    );

    final trimmedFirst = firstName.trim();
    final trimmedLast = lastName.trim();
    if (trimmedFirst.isEmpty || trimmedLast.isEmpty) {
      throw Exception('First and last name are required.');
    }

    await _employeesRef(companyId).doc(employeeId).set(
          EmployeeModel.toMapForCreate(
            companyId: companyId,
            firstName: trimmedFirst,
            lastName: trimmedLast,
            preferredName: preferredName,
            jobTitle: jobTitle,
            crewIds: crewIds,
            phone: phone,
            loginEmail: loginEmail,
            hireDate: hireDate,
            employmentType: employmentType,
            employeeNumber: employeeNumber,
          ),
        );
  }

  // --- Update ---

  Future<void> updateEmployeeProfile({
    required String companyId,
    required String actingUserId,
    required String employeeId,
    String? firstName,
    String? lastName,
    String? preferredName,
    String? jobTitle,
    String? phone,
    DateTime? hireDate,
    String? employmentType,
    String? employeeNumber,
    String? notes,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesEdit,
    );

    final updates = <String, dynamic>{
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
    if (firstName != null) updates['firstName'] = firstName.trim();
    if (lastName != null) updates['lastName'] = lastName.trim();
    if (preferredName != null) updates['preferredName'] = preferredName.trim();
    if (jobTitle != null) updates[FSFields.jobTitle] = jobTitle.trim();
    if (phone != null) updates['phone'] = phone.trim();
    if (hireDate != null) updates['hireDate'] = Timestamp.fromDate(hireDate);
    if (employmentType != null) updates['employmentType'] = employmentType;
    if (employeeNumber != null) updates['employeeNumber'] = employeeNumber.trim();
    if (notes != null) updates['notes'] = notes.trim();

    await _employeesRef(companyId).doc(employeeId).update(updates);
  }

  /// Adds this employee to a crew — one of any number they can belong
  /// to now, not an exclusive "the one crew" assignment. Safe to call
  /// even if they're already in it (arrayUnion is a no-op then).
  Future<void> addToCrew({
    required String companyId,
    required String actingUserId,
    required String employeeId,
    required String crewId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesAssignCrew,
    );

    await _employeesRef(companyId).doc(employeeId).update({
      'crewIds': FieldValue.arrayUnion([crewId]),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    final threadId = await _messagingService.findCrewThreadId(companyId: companyId, crewId: crewId);
    if (threadId != null) {
      await _messagingService.syncCrewThreadParticipants(companyId: companyId, threadId: threadId, crewId: crewId);
    }
  }

  Future<void> removeFromCrew({
    required String companyId,
    required String actingUserId,
    required String employeeId,
    required String crewId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesAssignCrew,
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

  Future<void> setClockInRequirementOverride({
    required String companyId,
    required String actingUserId,
    required String employeeId,
    required CompanyDefaultOverride override,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesEdit,
    );

    await _employeesRef(companyId).doc(employeeId).update({
      'clockInRequirementOverride': override.name,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> setManagerApprovalOverride({
    required String companyId,
    required String actingUserId,
    required String employeeId,
    required CompanyDefaultOverride override,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesEdit,
    );

    await _employeesRef(companyId).doc(employeeId).update({
      'managerApprovalOverride': override.name,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Lifecycle: archive / restore ---

  /// Archives an employee: sets their membership to archived (revoking
  /// access immediately) and records who/when/why. Refuses to archive a
  /// company's last active owner — promote someone else first.
  /// Historical time/payroll/messages/jobs/requests are untouched, since
  /// they reference employeeId, not membership status.
  Future<void> archiveEmployee({
    required String companyId,
    required String actingUserId,
    required String employeeId,
    required String reason,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesArchive,
    );

    if (reason.trim().isEmpty) {
      throw Exception('An archive reason is required.');
    }

    final membershipRef = _membershipsRef(companyId).doc(employeeId);

    await _firestore.runTransaction((transaction) async {
      final membershipDoc = await transaction.get(membershipRef);
      if (!membershipDoc.exists) {
        throw Exception('That member was not found.');
      }

      final membership = MembershipModel.fromSnapshot(membershipDoc);

      if (membership.isOwner) {
        final ownersSnapshot = await _membershipsRef(companyId)
            .where(FSFields.role, isEqualTo: FSRoles.owner)
            .where(FSFields.status, isEqualTo: FSMembershipStatus.active)
            .get();
        final otherActiveOwners =
            ownersSnapshot.docs.where((d) => d.id != employeeId).length;

        if (otherActiveOwners == 0) {
          throw Exception(
              'Cannot archive the last owner. Promote another owner first.');
        }
      }

      transaction.update(membershipRef, {
        FSFields.status: FSMembershipStatus.archived,
        FSFields.archivedAt: FieldValue.serverTimestamp(),
        FSFields.archivedBy: actingUserId,
        FSFields.archiveReason: reason.trim(),
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });
    });

    try {
      final actorName = await _fullNameForUser(actingUserId) ?? actingUserId;
      final targetName = await _fullNameForUser(employeeId) ?? employeeId;
      await _auditLogService.record(
        companyId: companyId,
        actorUserId: actingUserId,
        actorName: actorName,
        action: 'employeeArchived',
        targetType: 'employee',
        targetId: employeeId,
        targetName: targetName,
        newValue: reason.trim(),
      );
    } catch (_) {
      // The archive itself already succeeded above.
    }
  }

  Future<void> restoreEmployee({
    required String companyId,
    required String actingUserId,
    required String employeeId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      actingUserId: actingUserId,
      permissionKey: Permission.employeesRestore,
    );

    await _membershipsRef(companyId).doc(employeeId).update({
      FSFields.status: FSMembershipStatus.active,
      FSFields.archivedAt: null,
      FSFields.archivedBy: null,
      FSFields.archiveReason: null,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    try {
      final actorName = await _fullNameForUser(actingUserId) ?? actingUserId;
      final targetName = await _fullNameForUser(employeeId) ?? employeeId;
      await _auditLogService.record(
        companyId: companyId,
        actorUserId: actingUserId,
        actorName: actorName,
        action: 'employeeRestored',
        targetType: 'employee',
        targetId: employeeId,
        targetName: targetName,
      );
    } catch (_) {
      // The restore itself already succeeded above.
    }
  }
}
