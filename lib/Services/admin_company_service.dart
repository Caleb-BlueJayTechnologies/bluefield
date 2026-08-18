import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/audit_log_model.dart';
import '../Models/company_model.dart';
import 'audit_log_service.dart';
import 'platform_admin_service.dart';

class AdminCompanyService {
  final FirebaseFirestore _firestore;
  final PlatformAdminService _adminService;
  final AuditLogService _auditLog;

  AdminCompanyService({FirebaseFirestore? firestore, PlatformAdminService? adminService, AuditLogService? auditLog})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _adminService = adminService ?? PlatformAdminService(),
        _auditLog = auditLog ?? AuditLogService();

  CollectionReference<Map<String, dynamic>> get _companiesRef =>
      _firestore.collection(FSCollections.companies);

  Future<void> _requireCompanyManager(String actingAdminId) async {
    // Uses getCurrentAdmin() rather than a plain lookup-by-ID — that
    // method has the bootstrap-admin fallback (see
    // PlatformAdminService.bootstrapSuperAdminEmail), which a raw
    // getAdmin(actingAdminId) lookup does not. Without this, the
    // bootstrap admin gets incorrectly denied here any time their
    // platformAdmins doc hasn't self-healed yet this session — the
    // exact bug already fixed once for SupportTicketService, missed
    // here when this file was built. actingAdminId is always the
    // caller's own current UID in every real call site, so relying on
    // "whoever is currently signed in" here is equivalent, just safer.
    final admin = await _adminService.getCurrentAdmin();
    if (admin == null || admin.adminId != actingAdminId || !admin.canManageCompanies) {
      throw Exception('Only a super admin can manage company accounts.');
    }
  }

  /// Every company in the system — the entire point of this being a
  /// flat root-level collection query is that it's one listen, not a
  /// fan-out across tenants. Client-side search/filter is intentional
  /// here too, same reasoning as the ticket list: avoids needing a
  /// dedicated Firestore index for every possible search combination.
  Stream<List<CompanyModel>> watchAllCompanies() {
    return _companiesRef.orderBy(FSFields.createdAt, descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => CompanyModel.fromSnapshot(d)).toList(),
        );
  }

  Future<CompanyModel?> getCompany(String companyId) async {
    final doc = await _companiesRef.doc(companyId).get();
    if (!doc.exists) return null;
    return CompanyModel.fromSnapshot(doc);
  }

  /// Live employee count for a company — used on both the list (each
  /// row) and detail screen, right next to employeeLimit, so this is
  /// the number that matters for seat/billing purposes.
  ///
  /// Counts active MEMBERSHIPS, not the employees collection's raw
  /// doc count — employees are never hard-deleted (archive-only, per
  /// this app's design), so a straight count of the employees
  /// subcollection included former staff (fired/quit/laid off)
  /// forever, permanently inflating this number relative to who
  /// actually still works there. Archive status lives on the
  /// membership doc (EmployeeModel deliberately carries none), so
  /// filtering there is the correct join — same interpretation
  /// EmployeeService.watchEmployeesByCompany(includeArchived: false)
  /// already uses for the employer's own "Employees" dashboard card.
  Stream<int> watchEmployeeCount(String companyId) {
    return _companiesRef
        .doc(companyId)
        .collection(FSCompanySub.memberships)
        .where(FSFields.status, isEqualTo: FSMembershipStatus.active)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Resolves the display names of every current owner (a company can
  /// have more than one) — reads memberships filtered to role==owner.
  Future<List<String>> getOwnerNames(String companyId) async {
    final membershipsSnap = await _companiesRef
        .doc(companyId)
        .collection(FSCompanySub.memberships)
        .where(FSFields.role, isEqualTo: FSRoles.owner)
        .get();

    final names = <String>[];
    for (final doc in membershipsSnap.docs) {
      final employeeDoc =
          await _companiesRef.doc(companyId).collection(FSCompanySub.employees).doc(doc.id).get();
      final data = employeeDoc.data();
      if (data != null) {
        final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        names.add(name.isEmpty ? 'Unnamed Owner' : name);
      }
    }
    return names;
  }

  Future<void> suspendCompany({
    required String actingAdminId,
    required String companyId,
    required String reason,
  }) async {
    await _requireCompanyManager(actingAdminId);
    if (reason.trim().isEmpty) {
      throw Exception('A suspension reason is required.');
    }

    final company = await getCompany(companyId);

    await _companiesRef.doc(companyId).update({
      FSFields.isActive: false,
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspendedReason': reason.trim(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'company.suspend',
      targetType: AuditTargetType.company,
      targetId: companyId,
      targetName: company?.companyName ?? companyId,
      newValue: reason.trim(),
    );
  }

  Future<void> reactivateCompany({
    required String actingAdminId,
    required String companyId,
  }) async {
    await _requireCompanyManager(actingAdminId);

    final company = await getCompany(companyId);

    await _companiesRef.doc(companyId).update({
      FSFields.isActive: true,
      'suspendedAt': null,
      'suspendedReason': null,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'company.reactivate',
      targetType: AuditTargetType.company,
      targetId: companyId,
      targetName: company?.companyName ?? companyId,
    );
  }

  Future<void> setInternalAccount({
    required String actingAdminId,
    required String companyId,
    required bool isInternal,
  }) async {
    await _requireCompanyManager(actingAdminId);

    final company = await getCompany(companyId);

    await _companiesRef.doc(companyId).update({
      'isInternalAccount': isInternal,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'company.setInternal',
      targetType: AuditTargetType.company,
      targetId: companyId,
      targetName: company?.companyName ?? companyId,
      oldValue: '${company?.isInternalAccount ?? false}',
      newValue: '$isInternal',
    );
  }

  Future<void> setTestCompany({
    required String actingAdminId,
    required String companyId,
    required bool isTest,
  }) async {
    await _requireCompanyManager(actingAdminId);

    final company = await getCompany(companyId);

    await _companiesRef.doc(companyId).update({
      'isTestCompany': isTest,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'company.setTest',
      targetType: AuditTargetType.company,
      targetId: companyId,
      targetName: company?.companyName ?? companyId,
      oldValue: '${company?.isTestCompany ?? false}',
      newValue: '$isTest',
    );
  }

  Future<void> updateAdminNotes({
    required String actingAdminId,
    required String companyId,
    required String notes,
  }) async {
    await _requireCompanyManager(actingAdminId);

    final company = await getCompany(companyId);

    await _companiesRef.doc(companyId).update({
      'adminNotes': notes.trim().isEmpty ? null : notes.trim(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'company.updateNotes',
      targetType: AuditTargetType.company,
      targetId: companyId,
      targetName: company?.companyName ?? companyId,
    );
  }

  Future<void> changePricingProgram({
    required String actingAdminId,
    required String companyId,
    required String newProgram,
  }) async {
    await _requireCompanyManager(actingAdminId);

    final company = await getCompany(companyId);

    await _companiesRef.doc(companyId).update({
      'pricingProgram': newProgram,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await _auditLog.log(
      adminId: actingAdminId,
      action: 'company.changePricingProgram',
      targetType: AuditTargetType.company,
      targetId: companyId,
      targetName: company?.companyName ?? companyId,
      oldValue: company?.pricingProgram,
      newValue: newProgram,
    );
  }

  /// Overview Dashboard stats — total/active companies, excluding
  /// internal + test accounts from the counts that matter for real
  /// business metrics, same principle the roadmap doc calls for.
  Future<AdminCompanyStats> getCompanyStats() async {
    final snapshot = await _companiesRef.get();
    final companies = snapshot.docs.map((d) => CompanyModel.fromSnapshot(d)).toList();

    final realCompanies = companies.where((c) => !c.isInternalAccount && !c.isTestCompany).toList();
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    final hasFoundingCustomer =
        realCompanies.any((c) => c.pricingProgram == CompanyPricingProgram.founding);
    final betaCount = realCompanies.where((c) => c.pricingProgram == CompanyPricingProgram.beta).length;
    final earlyAdopterCount =
        realCompanies.where((c) => c.pricingProgram == CompanyPricingProgram.earlyAdopter).length;

    return AdminCompanyStats(
      totalCompanies: realCompanies.length,
      activeCompanies: realCompanies.where((c) => c.isActive).length,
      suspendedCompanies: realCompanies.where((c) => !c.isActive).length,
      newThisMonth: realCompanies.where((c) => c.createdAt.isAfter(startOfMonth)).length,
      trialingCompanies:
          realCompanies.where((c) => c.subscriptionStatus == CompanySubscriptionStatus.trialing).length,
      internalAccounts: companies.where((c) => c.isInternalAccount).length,
      testAccounts: companies.where((c) => c.isTestCompany).length,
      foundingSlotTaken: hasFoundingCustomer,
      betaSlotsRemaining: (4 - betaCount).clamp(0, 4),
      earlyAdopterSlotsRemaining: (4 - earlyAdopterCount).clamp(0, 4),
    );
  }

  /// Live version of [getCompanyStats] — same computation, recalculated
  /// on every snapshot instead of once. Used by the Admin Dashboard so
  /// active/suspended/founding-slot counts reflect a change (a company
  /// suspended, marked internal, etc.) immediately instead of only on
  /// manual refresh.
  Stream<AdminCompanyStats> watchCompanyStats() {
    return _companiesRef.snapshots().map((snapshot) {
      final companies = snapshot.docs.map((d) => CompanyModel.fromSnapshot(d)).toList();

      final realCompanies = companies.where((c) => !c.isInternalAccount && !c.isTestCompany).toList();
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      final hasFoundingCustomer =
          realCompanies.any((c) => c.pricingProgram == CompanyPricingProgram.founding);
      final betaCount = realCompanies.where((c) => c.pricingProgram == CompanyPricingProgram.beta).length;
      final earlyAdopterCount =
          realCompanies.where((c) => c.pricingProgram == CompanyPricingProgram.earlyAdopter).length;

      return AdminCompanyStats(
        totalCompanies: realCompanies.length,
        activeCompanies: realCompanies.where((c) => c.isActive).length,
        suspendedCompanies: realCompanies.where((c) => !c.isActive).length,
        newThisMonth: realCompanies.where((c) => c.createdAt.isAfter(startOfMonth)).length,
        trialingCompanies:
            realCompanies.where((c) => c.subscriptionStatus == CompanySubscriptionStatus.trialing).length,
        internalAccounts: companies.where((c) => c.isInternalAccount).length,
        testAccounts: companies.where((c) => c.isTestCompany).length,
        foundingSlotTaken: hasFoundingCustomer,
        betaSlotsRemaining: (4 - betaCount).clamp(0, 4),
        earlyAdopterSlotsRemaining: (4 - earlyAdopterCount).clamp(0, 4),
      );
    });
  }
}

class AdminCompanyStats {
  final int totalCompanies;
  final int activeCompanies;
  final int suspendedCompanies;
  final int newThisMonth;
  final int trialingCompanies;
  final int internalAccounts;
  final int testAccounts;
  final bool foundingSlotTaken;
  final int betaSlotsRemaining;
  final int earlyAdopterSlotsRemaining;

  const AdminCompanyStats({
    required this.totalCompanies,
    required this.activeCompanies,
    required this.suspendedCompanies,
    required this.newThisMonth,
    required this.trialingCompanies,
    required this.internalAccounts,
    required this.testAccounts,
    required this.foundingSlotTaken,
    required this.betaSlotsRemaining,
    required this.earlyAdopterSlotsRemaining,
  });
}
