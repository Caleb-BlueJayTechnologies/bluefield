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

  /// A deliberately minimal, non-sensitive companion to `companies` —
  /// holds nothing but a company's ID existing as a doc, written
  /// alongside the real company doc at registration. Exists purely so
  /// CompanyService._generateCompanyId can check "is ASM already
  /// taken?" for a candidate ID before the registrant has any real
  /// relationship to that company (they're not a member yet, might
  /// never be). The real `companies/{id}` doc stays properly
  /// member-only readable; this registry is what's safe to open up
  /// broadly instead.
  static const companyIdRegistry = 'companyIdRegistry';

  /// BlueJay-to-everyone broadcasts: maintenance windows, outages,
  /// platform-wide notices. Distinct from a company's own internal
  /// `announcements` subcollection — this is root-level and shown to
  /// every company regardless of which one they're in.
  static const systemAnnouncements = 'systemAnnouncements';

  /// Platform-level control over which features are AVAILABLE to a
  /// company at all — distinct from company settings' dashboardFeatures
  /// map, which controls whether an owner has CHOSEN to turn on
  /// something already available to them. Root-level, one doc per flag.
  static const featureFlags = 'featureFlags';

  /// Emergency platform-wide "stop" for a critical system — distinct
  /// from featureFlags (gradual per-company rollout of something NEW)
  /// and dashboardFeatures (an owner's own choice for their company).
  /// A kill switch forcibly disables something for EVERY company at
  /// once, meant for incident response, not staged rollout.
  static const killSwitches = 'killSwitches';

  /// What each CompanyPricingProgram tier actually includes — price,
  /// description. Informational/reference only right now: nothing
  /// charges money based on this yet, since there's no billing
  /// integration wired up. One doc per tier, keyed by the tier
  /// constant (e.g. 'standard', 'legacy').
  static const pricingTiers = 'pricingTiers';

  /// Immutable, append-only record of every legal-document acceptance
  /// (company terms, privacy policy, user terms, etc.) — one doc per
  /// acceptance event, never a single boolean/timestamp on the company
  /// or user doc. Root-level rather than a company subcollection
  /// because an individual end-user's acceptance (User Terms/AUP,
  /// location disclosure) isn't necessarily scoped to one company
  /// membership, and because platform admins/legal need to be able to
  /// pull acceptance evidence without company-scoped access. See
  /// LegalAcceptanceService and Section 11.7 of the legal package this
  /// was built from for the full field-by-field rationale.
  static const legalAcceptanceEvents = 'legalAcceptanceEvents';
}

/// Subcollections nested under a company document:
/// companies/{companyId}/{subcollection}/{docId}
class FSCompanySub {
  FSCompanySub._();

  static const memberships = 'memberships';
  static const employees = 'employees';
  static const crews = 'crews';
  static const auditLog = 'auditLog';
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
  static const equipment = 'equipment';
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
  static const crewId = 'crewId'; // legacy single-crew field, kept for backward-compat reads only
  static const crewIds = 'crewIds';
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

/// Legal-document type keys. Deliberately only the documents that are
/// actually implemented and shown to users today — NOT every document
/// named in the legal package this was built from. Founding-tier
/// agreements, the DPA, billing terms, and beta addendum are left out
/// until their content and the business decisions behind them
/// (pricing, discount stacking, payment processor, etc.) are settled;
/// adding a type here without real content behind it would let the
/// clickwrap flow silently "accept" something that doesn't exist yet.
class FSLegalDocumentType {
  FSLegalDocumentType._();

  static const companyTerms = 'companyTerms';
  static const privacyPolicy = 'privacyPolicy';
  static const userTerms = 'userTerms';
}

/// Whether a legal acceptance was given by someone binding their
/// organization (a company owner accepting the Company Terms) versus
/// an individual accepting only for themselves (an invited employee
/// accepting the User Terms). Mirrors Section 11.7's "capacity" field.
class FSLegalCapacity {
  FSLegalCapacity._();

  static const organizationRepresentative = 'organization_representative';
  static const individual = 'individual';
}

/// Field names for a single doc in FSCollections.legalAcceptanceEvents.
/// See LegalAcceptanceEvent for the full model these back.
class FSLegalFields {
  FSLegalFields._();

  static const acceptanceId = 'acceptanceId';
  static const userId = 'userId';
  static const verifiedIdentifier = 'verifiedIdentifier';
  static const organizationId = 'organizationId';
  static const organizationDisplayedName = 'organizationDisplayedName';
  static const role = 'role';
  static const capacity = 'capacity';
  static const authorityText = 'authorityText';
  static const documentType = 'documentType';
  static const documentVersion = 'documentVersion';
  static const documentEffectiveDate = 'documentEffectiveDate';
  static const documentTitle = 'documentTitle';
  static const contentHash = 'contentHash';
  static const checkboxText = 'checkboxText';
  static const buttonText = 'buttonText';
  static const locale = 'locale';
  static const appVersion = 'appVersion';
  static const platform = 'platform';
  static const supersedesAcceptanceId = 'supersedesAcceptanceId';
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
