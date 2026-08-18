import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// Employment classification, shown for HR/reporting purposes only.
/// Never used to gate access — see MembershipModel.role for that.
class EmploymentType {
  EmploymentType._();

  static const fullTime = 'fullTime';
  static const partTime = 'partTime';
  static const seasonal = 'seasonal';
  static const contractor = 'contractor';
  static const other = 'other';

  static const all = [fullTime, partTime, seasonal, contractor, other];
}

/// A tri-state override: use the company default, or force it on/off
/// for this one employee. Matches Section 4's requirement that overrides
/// record "whether the override uses company default or explicit
/// enabled/disabled state."
enum CompanyDefaultOverride { useCompanyDefault, forceEnabled, forceDisabled }

CompanyDefaultOverride _overrideFromMap(dynamic value) {
  switch (value?.toString()) {
    case 'forceEnabled':
      return CompanyDefaultOverride.forceEnabled;
    case 'forceDisabled':
      return CompanyDefaultOverride.forceDisabled;
    default:
      return CompanyDefaultOverride.useCompanyDefault;
  }
}

String _overrideToMap(CompanyDefaultOverride value) => value.name;

/// The HR/profile record for a person working at a company. Stored at
/// `companies/{companyId}/employees/{employeeId}`, where employeeId is
/// always equal to the user's Firebase Auth UID (same as the linked
/// MembershipModel.userId).
///
/// This model deliberately holds NO security role and NO access status —
/// those live only on MembershipModel, so there is exactly one place
/// that controls what a person can do. This model only answers "who is
/// this person and how is their work configured."
class EmployeeModel {
  /// Equal to the linked MembershipModel.userId / Firebase Auth UID.
  final String employeeId;
  final String companyId;

  final String firstName;
  final String lastName;
  final String? preferredName;

  /// Informational only — never grants or restricts access. The
  /// security role lives on MembershipModel.role instead.
  final String? jobTitle;

  /// Every crew/team this employee belongs to. An empty list means
  /// "no crews," which must be a valid, explicit state everywhere
  /// crew is shown or filtered on — not treated as an error.
  ///
  /// This is the source of truth for crew rostering: crew_service reads
  /// membership by querying employees where crewIds array-contains X
  /// rather than also keeping a separate memberIds list on the crew
  /// doc, so there is only one place membership can drift out of sync.
  final List<String> crewIds;

  final String? phone;

  /// Read-only mirror of the linked AppUser's login email, kept here so
  /// employee list/detail screens don't need a second read. The
  /// authoritative value is always users/{uid}.email — never write this
  /// field directly without also updating that document.
  final String? loginEmail;

  /// Read-only mirror of the linked AppUser's requiresPasswordChange
  /// flag — same pattern and same reason as [loginEmail] above.
  /// Mirrored here specifically so a manager/owner viewing this
  /// employee (who can already read employees/{uid} as any company
  /// member) can tell whether they've completed their initial
  /// password setup, without needing users/{uid} read access widened
  /// to non-self accounts just for this one check. Authoritative value
  /// is always users/{uid}.requiresPasswordChange — never write this
  /// field directly without also updating that document (see
  /// AuthService.changePassword, which updates both together).
  final bool requiresPasswordChange;

  final DateTime? hireDate;
  final String employmentType; // EmploymentType.*
  final String? employeeNumber;

  /// Visible only to users with the "view sensitive employee data"
  /// permission — the model doesn't enforce that, the service and UI do.
  final String? notes;

  /// Whether this employee must clock in, relative to the company-wide
  /// setting (Company Settings > Team Time > employee clock requirement).
  final CompanyDefaultOverride clockInRequirementOverride;

  /// Whether corrections/time edits for this employee skip normal
  /// manager-approval behavior, relative to the company-wide setting.
  final CompanyDefaultOverride managerApprovalOverride;

  final DateTime createdAt;
  final DateTime updatedAt;

  const EmployeeModel({
    required this.employeeId,
    required this.companyId,
    required this.firstName,
    required this.lastName,
    this.preferredName,
    this.jobTitle,
    this.crewIds = const [],
    this.phone,
    this.loginEmail,
    this.requiresPasswordChange = false,
    this.hireDate,
    this.employmentType = EmploymentType.fullTime,
    this.employeeNumber,
    this.notes,
    this.clockInRequirementOverride = CompanyDefaultOverride.useCompanyDefault,
    this.managerApprovalOverride = CompanyDefaultOverride.useCompanyDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  String get displayName =>
      (preferredName != null && preferredName!.trim().isNotEmpty)
          ? preferredName!.trim()
          : firstName;

  bool get hasCrew => crewIds.isNotEmpty;

  bool get hasMultipleCrews => crewIds.length > 1;

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'firstName': firstName,
      'lastName': lastName,
      'preferredName': preferredName,
      FSFields.jobTitle: jobTitle,
      'crewIds': crewIds,
      'phone': phone,
      'loginEmail': loginEmail,
      'requiresPasswordChange': requiresPasswordChange,
      'hireDate': hireDate != null ? Timestamp.fromDate(hireDate!) : null,
      'employmentType': employmentType,
      'employeeNumber': employeeNumber,
      'notes': notes,
      'clockInRequirementOverride':
          _overrideToMap(clockInRequirementOverride),
      'managerApprovalOverride': _overrideToMap(managerApprovalOverride),
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String firstName,
    required String lastName,
    String? preferredName,
    String? jobTitle,
    List<String> crewIds = const [],
    String? phone,
    String? loginEmail,
    bool requiresPasswordChange = true,
    DateTime? hireDate,
    String employmentType = EmploymentType.fullTime,
    String? employeeNumber,
    String? notes,
  }) {
    return {
      FSFields.companyId: companyId,
      'firstName': firstName,
      'lastName': lastName,
      'preferredName': preferredName,
      FSFields.jobTitle: jobTitle,
      'crewIds': crewIds,
      'phone': phone,
      'loginEmail': loginEmail,
      'requiresPasswordChange': requiresPasswordChange,
      'hireDate': hireDate != null ? Timestamp.fromDate(hireDate) : null,
      'employmentType': employmentType,
      'employeeNumber': employeeNumber,
      'notes': notes,
      'clockInRequirementOverride':
          _overrideToMap(CompanyDefaultOverride.useCompanyDefault),
      'managerApprovalOverride':
          _overrideToMap(CompanyDefaultOverride.useCompanyDefault),
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  /// A doc written before the multi-crew migration has a single old
  /// `crewId` string field instead of the new `crewIds` array — read
  /// that as a one-item list rather than silently losing the
  /// employee's existing crew assignment. New writes only ever
  /// populate `crewIds`, so this is purely a read-time compatibility
  /// shim.
  static List<String> _readCrewIds(Map<String, dynamic> map) {
    final list = map['crewIds'];
    if (list is List) {
      return list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    final legacy = map[FSFields.crewId]?.toString();
    if (legacy != null && legacy.trim().isNotEmpty) {
      return [legacy];
    }
    return const [];
  }

  factory EmployeeModel.fromMap(String employeeId, Map<String, dynamic> map) {
    return EmployeeModel(
      employeeId: employeeId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      firstName: map['firstName']?.toString() ?? '',
      lastName: map['lastName']?.toString() ?? '',
      preferredName: map['preferredName']?.toString(),
      jobTitle: map[FSFields.jobTitle]?.toString(),
      crewIds: _readCrewIds(map),
      phone: map['phone']?.toString(),
      loginEmail: map['loginEmail']?.toString(),
      requiresPasswordChange: map['requiresPasswordChange'] == true,
      hireDate: FSTimestamp.tryParse(map['hireDate']),
      employmentType:
          map['employmentType']?.toString() ?? EmploymentType.fullTime,
      employeeNumber: map['employeeNumber']?.toString(),
      notes: map['notes']?.toString(),
      clockInRequirementOverride:
          _overrideFromMap(map['clockInRequirementOverride']),
      managerApprovalOverride:
          _overrideFromMap(map['managerApprovalOverride']),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory EmployeeModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Employee document ${doc.id} has no data.');
    }
    return EmployeeModel.fromMap(doc.id, data);
  }

  EmployeeModel copyWith({
    String? firstName,
    String? lastName,
    String? preferredName,
    String? jobTitle,
    bool clearCrew = false,
    List<String>? crewIds,
    String? phone,
    String? loginEmail,
    bool? requiresPasswordChange,
    DateTime? hireDate,
    String? employmentType,
    String? employeeNumber,
    String? notes,
    CompanyDefaultOverride? clockInRequirementOverride,
    CompanyDefaultOverride? managerApprovalOverride,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeModel(
      employeeId: employeeId,
      companyId: companyId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      preferredName: preferredName ?? this.preferredName,
      jobTitle: jobTitle ?? this.jobTitle,
      crewIds: clearCrew ? const [] : (crewIds ?? this.crewIds),
      phone: phone ?? this.phone,
      loginEmail: loginEmail ?? this.loginEmail,
      requiresPasswordChange: requiresPasswordChange ?? this.requiresPasswordChange,
      hireDate: hireDate ?? this.hireDate,
      employmentType: employmentType ?? this.employmentType,
      employeeNumber: employeeNumber ?? this.employeeNumber,
      notes: notes ?? this.notes,
      clockInRequirementOverride:
          clockInRequirementOverride ?? this.clockInRequirementOverride,
      managerApprovalOverride:
          managerApprovalOverride ?? this.managerApprovalOverride,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
