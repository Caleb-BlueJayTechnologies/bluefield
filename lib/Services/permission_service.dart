import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/membership.dart';

/// Every granular permission in the app, grouped to match Section 3 of
/// the product plan. Use these constants with [hasPermission] /
/// [currentUserCan] rather than checking role strings directly in
/// screens or other services — that's what keeps enforcement consistent
/// across UI, services, and (eventually) Firestore rules.
class Permission {
  Permission._();

  // Company
  static const companyViewProfile = 'company.viewProfile';
  static const companyEditProfile = 'company.editProfile';
  static const companyEditBranding = 'company.editBranding';
  static const companyEditModules = 'company.editModules';
  static const companyEditBilling = 'company.editBilling';
  static const companyEditSecurity = 'company.editSecurity';
  static const companyManageOwners = 'company.manageOwners';
  static const companyManageManagers = 'company.manageManagers';

  // Employees
  static const employeesView = 'employees.view';
  static const employeesCreate = 'employees.create';
  static const employeesEdit = 'employees.edit';
  static const employeesArchive = 'employees.archive';
  static const employeesRestore = 'employees.restore';
  static const employeesChangeRole = 'employees.changeRole';
  static const employeesChangeTitle = 'employees.changeTitle';
  static const employeesAssignCrew = 'employees.assignCrew';
  static const employeesViewSensitive = 'employees.viewSensitive';
  static const employeesInvite = 'employees.invite';

  // Crews
  static const crewsView = 'crews.view';
  static const crewsCreate = 'crews.create';
  static const crewsEdit = 'crews.edit';
  static const crewsArchive = 'crews.archive';
  static const crewsRestore = 'crews.restore';
  static const crewsAssignMembers = 'crews.assignMembers';
  static const crewsMessage = 'crews.message';

  // Jobs & scheduling
  static const jobsViewAll = 'jobs.viewAll';
  static const jobsViewAssignedOnly = 'jobs.viewAssignedOnly';
  static const jobsCreate = 'jobs.create';
  static const jobsEdit = 'jobs.edit';
  static const jobsCancel = 'jobs.cancel';
  static const jobsComplete = 'jobs.complete';
  static const jobsReopen = 'jobs.reopen';
  static const jobsAssignEmployees = 'jobs.assignEmployees';
  static const jobsAssignCrews = 'jobs.assignCrews';
  static const jobsViewHistory = 'jobs.viewHistory';
  static const jobsDuplicate = 'jobs.duplicate';
  static const jobsManageTemplates = 'jobs.manageTemplates';
  static const scheduleViewAll = 'schedule.viewAll';
  static const scheduleEdit = 'schedule.edit';
  static const schedulePublish = 'schedule.publish';

  // Time tracking
  static const timeClockSelf = 'time.clockSelf';
  static const timeViewOwnHistory = 'time.viewOwnHistory';
  static const timeViewTeamHistory = 'time.viewTeamHistory';
  static const timeEditEntries = 'time.editEntries';
  static const timeApproveCorrections = 'time.approveCorrections';
  static const timeExportPayroll = 'time.exportPayroll';
  static const timeViewPayrollTotals = 'time.viewPayrollTotals';
  static const timeLockPayPeriods = 'time.lockPayPeriods';
  static const timeUnlockPayPeriods = 'time.unlockPayPeriods';

  // Time off
  static const timeOffSubmit = 'timeOff.submit';
  static const timeOffViewOwn = 'timeOff.viewOwn';
  static const timeOffViewTeam = 'timeOff.viewTeam';
  static const timeOffApprove = 'timeOff.approve';
  static const timeOffReject = 'timeOff.reject';
  static const timeOffCancel = 'timeOff.cancel';
  static const timeOffEditBalancesAndPolicies = 'timeOff.editBalancesAndPolicies';

  // Messaging & announcements
  static const messagingSendDirect = 'messaging.sendDirect';
  static const messagingSendCrew = 'messaging.sendCrew';
  static const messagingSendCompanyWide = 'messaging.sendCompanyWide';
  static const messagingModerate = 'messaging.moderate';
  static const announcementsCreate = 'announcements.create';
  static const announcementsEdit = 'announcements.edit';
  static const announcementsArchive = 'announcements.archive';
  static const announcementsPin = 'announcements.pin';

  // Vehicles
  static const vehiclesView = 'vehicles.view';
  static const vehiclesCreate = 'vehicles.create';
  static const vehiclesEdit = 'vehicles.edit';
  static const vehiclesArchive = 'vehicles.archive';
  static const vehiclesAssign = 'vehicles.assign';

  // Equipment
  static const equipmentView = 'equipment.view';
  static const equipmentCreate = 'equipment.create';
  static const equipmentEdit = 'equipment.edit';
  static const equipmentArchive = 'equipment.archive';
  static const equipmentAssign = 'equipment.assign';

  // Feedback (company-facing; BlueJay's own admin dashboard is a
  // separate, non-company-role permission surface — see Section 17)
  static const feedbackSubmit = 'feedback.submit';
  static const feedbackViewCompanySubmissions = 'feedback.viewCompanySubmissions';

  /// Every permission key that exists, used to build the owner's
  /// unrestricted set and to validate custom roles in the future.
  static const Set<String> all = {
    companyViewProfile, companyEditProfile, companyEditBranding,
    companyEditModules, companyEditBilling, companyEditSecurity,
    companyManageOwners, companyManageManagers,
    employeesView, employeesCreate, employeesEdit, employeesArchive,
    employeesRestore, employeesChangeRole, employeesChangeTitle,
    employeesAssignCrew, employeesViewSensitive, employeesInvite,
    crewsView, crewsCreate, crewsEdit, crewsArchive, crewsRestore, crewsAssignMembers,
    crewsMessage,
    jobsViewAll, jobsViewAssignedOnly, jobsCreate, jobsEdit, jobsCancel,
    jobsComplete, jobsReopen, jobsAssignEmployees, jobsAssignCrews,
    jobsViewHistory, jobsDuplicate, jobsManageTemplates,
    scheduleViewAll, scheduleEdit, schedulePublish,
    timeClockSelf, timeViewOwnHistory, timeViewTeamHistory, timeEditEntries,
    timeApproveCorrections, timeExportPayroll, timeViewPayrollTotals,
    timeLockPayPeriods, timeUnlockPayPeriods,
    timeOffSubmit, timeOffViewOwn, timeOffViewTeam, timeOffApprove,
    timeOffReject, timeOffCancel, timeOffEditBalancesAndPolicies,
    messagingSendDirect, messagingSendCrew, messagingSendCompanyWide,
    messagingModerate, announcementsCreate, announcementsEdit,
    announcementsArchive, announcementsPin,
    vehiclesView, vehiclesCreate, vehiclesEdit, vehiclesArchive,
    vehiclesAssign,
    equipmentView, equipmentCreate, equipmentEdit, equipmentArchive,
    equipmentAssign,
    feedbackSubmit, feedbackViewCompanySubmissions,
  };
}

/// Permissions reserved for owners only — everything else in
/// [Permission.all] is available to managers by default. This is a
/// deliberately short list: company-level financial/security control,
/// role changes (to avoid a manager being able to promote themselves or
/// another manager to owner), and payroll locking/export.
const Set<String> _ownerOnlyPermissions = {
  Permission.companyEditBilling,
  Permission.companyEditSecurity,
  Permission.companyManageOwners,
  Permission.employeesChangeRole,
  Permission.timeExportPayroll,
  Permission.timeLockPayPeriods,
  Permission.timeUnlockPayPeriods,
  Permission.timeOffEditBalancesAndPolicies,
};

/// The default employee permission set — deliberately short and
/// self-scoped. Anything not listed here that an employee needs (e.g.
/// "see my own job") is enforced by filtering queries to their own
/// userId/crewId, not by a broad permission grant.
const Set<String> _employeePermissions = {
  Permission.jobsViewAssignedOnly,
  Permission.jobsComplete, // employees can mark their own assigned job done
  Permission.timeClockSelf,
  Permission.timeViewOwnHistory,
  Permission.timeOffSubmit,
  Permission.timeOffViewOwn,
  Permission.timeOffCancel,
  Permission.messagingSendDirect,
  Permission.messagingSendCrew,
  Permission.feedbackSubmit,
  Permission.crewsView, // scoped to their own crew by the query, not this flag
  Permission.vehiclesView,
  Permission.equipmentView,
};

/// Central authority for what a role is allowed to do. Company
/// isolation and access itself is still enforced by MembershipModel —
/// this only answers "given an active membership with this role, is
/// this specific action allowed."
///
/// Custom per-company roles aren't implemented yet (Section 3 lists it
/// as a future capability), but MembershipModel already has a spare
/// `permissionsOverride` field reserved for it — when that's built, it
/// should layer on top of [permissionsForRole] rather than replacing
/// this matrix, so upgrading doesn't require restructuring every screen
/// that calls [currentUserCan].
class PermissionService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  PermissionService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  // --- Role -> permission set ---

  static Set<String> permissionsForRole(String role) {
    switch (role) {
      case FSRoles.owner:
        return Permission.all;
      case FSRoles.manager:
        return Permission.all.difference(_ownerOnlyPermissions);
      case FSRoles.employee:
      default:
        return _employeePermissions;
    }
  }

  static bool roleHasPermission(String role, String permissionKey) {
    return permissionsForRole(role).contains(permissionKey);
  }

  // --- Role helpers (kept for readability at call sites) ---

  static bool isOwnerRole(String role) => role == FSRoles.owner;
  static bool isManagerRole(String role) => role == FSRoles.manager;
  static bool isEmployeeRole(String role) => role == FSRoles.employee;
  static bool isManagementRole(String role) =>
      isOwnerRole(role) || isManagerRole(role);

  // --- Current-user resolution ---

  Future<String> _getCurrentCompanyId() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in.');
    }

    final userDoc =
        await _firestore.collection(FSCollections.users).doc(user.uid).get();
    final data = userDoc.data();
    if (data == null) {
      throw Exception('User document was not found.');
    }

    final companyId = data['activeCompanyId']?.toString().trim() ?? '';
    if (companyId.isEmpty) {
      throw Exception('User is not linked to a company.');
    }
    return companyId;
  }

  /// Fetches the current user's membership for their active company.
  /// Throws if there's no signed-in user, no active company, no
  /// membership document, or the membership isn't active.
  Future<MembershipModel> getCurrentMembership() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in.');
    }

    final companyId = await _getCurrentCompanyId();

    final doc = await _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships)
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      throw Exception('You do not have access to this company.');
    }

    final membership = MembershipModel.fromSnapshot(doc);
    if (!membership.grantsAccess) {
      throw Exception('Your access to this company is not active.');
    }
    return membership;
  }

  /// Convenience for call sites that only need the role string.
  /// Prefer [getCurrentMembership] when you also need status/timestamps.
  Future<String> getCurrentUserRole() async {
    final membership = await getCurrentMembership();
    return membership.role;
  }

  /// Reads a role out of a raw Firestore map — kept for any legacy call
  /// site still passing around loose maps instead of a MembershipModel.
  /// New code should read MembershipModel.role directly instead.
  String readRole(Map<String, dynamic> data) {
    final value = data[FSFields.role]?.toString().toLowerCase().trim();
    return FSRoles.isValid(value ?? '') ? value! : FSRoles.employee;
  }

  /// Checks whether the current signed-in user's role grants
  /// [permissionKey]. This is the main entry point most screens/services
  /// should call.
  Future<bool> currentUserCan(String permissionKey) async {
    final role = await getCurrentUserRole();
    return roleHasPermission(role, permissionKey);
  }

  /// Same as [currentUserCan] but throws instead of returning false,
  /// for guarding an action outright rather than hiding a button.
  Future<void> requirePermission(String permissionKey) async {
    final allowed = await currentUserCan(permissionKey);
    if (!allowed) {
      throw Exception('You do not have permission to do that.');
    }
  }

  // --- Backward-compatible convenience methods used by existing screens ---
  // Kept with their original names/signatures so correction_requests_screen.dart
  // and pay_periods_screen.dart don't break; each now delegates to the
  // permission matrix instead of hardcoded role checks.

  bool canApproveCorrection(String role) =>
      roleHasPermission(role, Permission.timeApproveCorrections);

  bool canEditTimeEntry({
    required String viewerRole,
    required String viewerUserId,
    required String entryUserId,
  }) {
    final isOwnEntry = viewerUserId.trim().isNotEmpty &&
        viewerUserId.trim() == entryUserId.trim();

    if (isOwnerRole(viewerRole)) return true;
    if (isManagerRole(viewerRole)) return !isOwnEntry;
    return false;
  }

  bool canLockPayPeriods(String role) =>
      roleHasPermission(role, Permission.timeLockPayPeriods);

  bool canUnlockPayPeriods(String role) =>
      roleHasPermission(role, Permission.timeUnlockPayPeriods);
}
