/// ============================================================================
/// BlueField — Authoritative Firestore Schema Reference
/// ============================================================================
/// This is the single source of truth for Firestore collection paths,
/// standardized field names, and canonical string values used across the app.
///
/// Rules:
/// - Every service MUST use these constants instead of hardcoded strings.
/// - Every model MUST read/write field names from here, not ad-hoc keys.
/// - Do NOT add new collections or fields elsewhere; add them here first.
///
/// Replaces (delete after this file is in place):
///   lib/Firebase/firebase_collections.dart
///   lib/Firebase/firestore_paths.dart
/// ============================================================================

/// Top-level Firestore collections.
class FSCollections {
  FSCollections._();

  /// Root user account documents. One per Firebase Auth UID.
  /// A user can hold memberships in one or more companies (future
  /// multi-location support), but v1 assumes a single active company.
  static const users = 'users';

  /// Company documents. Root of company-scoped data.
  static const companies = 'companies';

  /// Root-level platform administrator accounts — grants access to the
  /// BlueJay Admin Panel. Deliberately separate from `users` and from
  /// any company's ownership/role: being an Owner of a customer company
  /// grants zero platform-admin access on its own. See
  /// PlatformAdminModel for the role tiers (superAdmin, supportAdmin,
  /// billingAdmin, productAdmin).
  static const platformAdmins = 'platformAdmins';

  /// Cross-company support tickets, visible only to BlueJay admins
  /// plus the submitting company's authorized users.
  static const supportTickets = 'supportTickets';

  /// Immutable record of every sensitive platform-admin action —
  /// company suspension, internal/test marking, admin role changes,
  /// etc. Admin-only, never visible to any company. Append-only by
  /// design: nothing should ever update or delete an audit entry.
  static const platformAuditLog = 'platformAuditLog';

  /// Single-purpose counters that need atomic get-and-increment
  /// semantics — currently just the customer sequence number used for
  /// the Founding Program (see CompanyService._getNextCustomerNumber).
  /// A dedicated tiny collection rather than a field on some other
  /// doc, so the transaction touching it never has to compete with
  /// unrelated writes to a busier document.
  static const systemCounters = 'systemCounters';
}

/// Subcollections nested under a company document:
/// companies/{companyId}/{subcollection}/{docId}
class FSCompanySub {
  FSCompanySub._();

  static const memberships = 'memberships';
  static const employees = 'employees';
  static const crews = 'crews';
  static const jobs = 'jobs';
  static const jobTemplates = 'jobTemplates';
  static const schedules = 'schedules';
  static const timeEntries = 'timeEntries';
  static const correctionRequests = 'correctionRequests';
  static const payPeriods = 'payPeriods';
  static const timeOffRequests = 'timeOffRequests';
  static const leaveTypes = 'leaveTypes';
  static const paidHolidays = 'paidHolidays';
  static const messageThreads = 'messageThreads';
  static const announcements = 'announcements';
  static const notifications = 'notifications';
  static const vehicles = 'vehicles';
  static const invitations = 'invitations';
  static const devices = 'devices';
  static const auditLogs = 'auditLogs';
  static const feedback = 'feedback';
  static const settings = 'settings'; // single doc: settings/company
}

/// Subcollections nested under a message thread document:
/// companies/{companyId}/messageThreads/{threadId}/{subcollection}/{docId}
class FSThreadSub {
  FSThreadSub._();

  static const messages = 'messages';
}

/// Well-known singleton document IDs within a subcollection of size 1.
class FSSingletonDocs {
  FSSingletonDocs._();

  static const companySettings = 'company';
}

/// Path builders. Use these instead of concatenating strings by hand.
class FSPaths {
  FSPaths._();

  static String company(String companyId) =>
      '${FSCollections.companies}/$companyId';

  static String companySub(String companyId, String subcollection) =>
      '${company(companyId)}/$subcollection';

  static String companyDoc(
    String companyId,
    String subcollection,
    String docId,
  ) =>
      '${companySub(companyId, subcollection)}/$docId';

  static String threadMessages(String companyId, String threadId) =>
      '${companyDoc(companyId, FSCompanySub.messageThreads, threadId)}/${FSThreadSub.messages}';

  static String settingsDoc(String companyId) => companyDoc(
        companyId,
        FSCompanySub.settings,
        FSSingletonDocs.companySettings,
      );
}

/// ----------------------------------------------------------------------
/// Standardized field names shared across multiple models/collections.
/// If a field means the same thing in two places, it must use the same
/// key in both. Field names are grouped by concern, not by collection,
/// since several collections reuse the same concepts.
/// ----------------------------------------------------------------------
class FSFields {
  FSFields._();

  // Identity / ownership
  static const companyId = 'companyId';
  static const userId = 'userId';
  static const employeeId = 'employeeId';
  static const timeEntryId = 'timeEntryId';
  static const membershipId = 'membershipId';
  static const crewId = 'crewId';
  static const crewIds = 'crewIds'; // for future multi-crew membership
  static const jobId = 'jobId';
  static const vehicleId = 'vehicleId';
  static const createdBy = 'createdBy';
  static const updatedBy = 'updatedBy';

  // Timestamps (always Firestore server Timestamp, never ISO strings)
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';
  static const clockInAt = 'clockInAt';
  static const clockOutAt = 'clockOutAt';
  static const archivedAt = 'archivedAt';
  static const startAt = 'startAt';
  static const endAt = 'endAt';
  static const startDate = 'startDate'; // date-only, for multi-day jobs
  static const endDate = 'endDate'; // date-only, for multi-day jobs

  // Lifecycle / soft delete
  static const isActive = 'isActive';
  static const isArchived = 'isArchived';
  static const archivedBy = 'archivedBy';
  static const archiveReason = 'archiveReason';

  // Roles & permissions (see FSRoles below for valid values)
  static const role = 'role'; // security role: owner/manager/employee
  static const jobTitle = 'jobTitle'; // informational only, never gates access
  static const permissionsOverride = 'permissionsOverride';

  // Company isolation guard — every company-scoped doc must carry this
  // even inside a company subcollection, so Firestore rules can validate
  // it against the path without a second read.
  static const ownerCompanyId = 'companyId';

  // Status fields (generic; each domain defines its own valid value set)
  static const status = 'status';
  static const statusChangedAt = 'statusChangedAt';
  static const statusChangedBy = 'statusChangedBy';

  // Audit trail
  static const reviewedBy = 'reviewedBy';
  static const reviewedAt = 'reviewedAt';
  static const originalValue = 'originalValue';
  static const correctedValue = 'correctedValue';
}

/// Canonical security role values. These control access.
/// (Job titles are separate — see FSFields.jobTitle — and never gate access.)
class FSRoles {
  FSRoles._();

  static const owner = 'owner';
  static const manager = 'manager';
  static const employee = 'employee';

  static const all = [owner, manager, employee];

  static bool isValid(String value) => all.contains(value);
}

/// Canonical membership status values (per-user, per-company).
class FSMembershipStatus {
  FSMembershipStatus._();

  static const active = 'active';
  static const archived = 'archived';
  static const suspended = 'suspended';
}

/// Canonical job status values.
class FSJobStatus {
  FSJobStatus._();

  static const draft = 'draft';
  static const scheduled = 'scheduled';
  static const inProgress = 'inProgress';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const archived = 'archived';

  static const all = [draft, scheduled, inProgress, completed, cancelled, archived];
}

/// Canonical time-off request status values.
class FSTimeOffStatus {
  FSTimeOffStatus._();

  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';
}

/// Canonical correction-request status values.
class FSCorrectionStatus {
  FSCorrectionStatus._();

  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
}

/// Canonical vehicle status values.
class FSVehicleStatus {
  FSVehicleStatus._();

  static const available = 'available';
  static const assigned = 'assigned';
  static const maintenance = 'maintenance';
  static const inactive = 'inactive';
}

/// Canonical pay period status values.
class FSPayPeriodStatus {
  FSPayPeriodStatus._();

  static const open = 'open';
  static const locked = 'locked';
}

/// Canonical invitation status values.
class FSInvitationStatus {
  FSInvitationStatus._();

  static const pending = 'pending';
  static const accepted = 'accepted';
  static const revoked = 'revoked';
  static const expired = 'expired';
}

/// Canonical support ticket status values (Section 17).
class FSTicketStatus {
  FSTicketStatus._();

  static const newTicket = 'new';
  static const reviewing = 'reviewing';
  static const planned = 'planned';
  static const inProgress = 'inProgress';
  static const waitingOnCustomer = 'waitingOnCustomer';
  static const resolved = 'resolved';
  static const closed = 'closed';
  static const rejected = 'rejected';
}

/// Feedback ticket category values.
class FSTicketCategory {
  FSTicketCategory._();

  static const bugReport = 'bugReport';
  static const featureRequest = 'featureRequest';
  static const question = 'question';
  static const generalFeedback = 'generalFeedback';
}

/// Feedback ticket priority values.
class FSTicketPriority {
  FSTicketPriority._();

  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';
  static const critical = 'critical';
}

/// Platform-level admin roles (companies/{id} ownership grants none of
/// these — this is a completely separate permission surface, see
/// PlatformAdminModel).
class FSPlatformAdminRole {
  FSPlatformAdminRole._();

  static const superAdmin = 'superAdmin';
  static const supportAdmin = 'supportAdmin';
  static const billingAdmin = 'billingAdmin';
  static const productAdmin = 'productAdmin';
}

/// Clock rounding policy values (Section 8).
class FSClockRounding {
  FSClockRounding._();

  static const none = 'none';
  static const nearest5 = 'nearest5';
  static const nearest6 = 'nearest6';
  static const nearest10 = 'nearest10';
  static const nearest15 = 'nearest15';
}

/// Time display format values (Section 8).
class FSTimeDisplayFormat {
  FSTimeDisplayFormat._();

  static const decimal = 'decimal';
  static const hhmm = 'hhmm';
}

/// ----------------------------------------------------------------------
/// Migration-safe timestamp handling.
/// Older/test documents may store dates as ISO-8601 strings; going
/// forward everything must be written as a Firestore Timestamp. Every
/// model's fromMap must read through here instead of calling
/// DateTime.parse or casting directly, so old documents don't crash
/// the app while they're gradually re-saved in the new format.
/// ----------------------------------------------------------------------
class FSTimestamp {
  FSTimestamp._();

  /// Parses a Firestore Timestamp, an ISO-8601 String, or a DateTime.
  /// Returns null if the value is null/missing/unparsable instead of
  /// throwing, so callers decide the appropriate fallback.
  static DateTime? tryParse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    // Firestore's Timestamp type (avoids importing cloud_firestore here
    // to keep this file dependency-free; duck-typed via toDate()).
    try {
      final dynamic maybeTimestamp = value;
      if (maybeTimestamp.runtimeType.toString() == 'Timestamp') {
        return maybeTimestamp.toDate() as DateTime;
      }
    } catch (_) {
      // fall through to string parsing
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Same as [tryParse] but falls back to the given default (or now)
  /// when the value can't be read. Use for required, non-nullable fields.
  static DateTime parseOr(dynamic value, {DateTime? fallback}) {
    return tryParse(value) ?? fallback ?? DateTime.now();
  }
}
