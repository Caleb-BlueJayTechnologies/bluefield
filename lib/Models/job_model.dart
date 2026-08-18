import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// A job/work order. Stored at `companies/{companyId}/jobs/{jobId}`.
///
/// A multi-day job is ONE record with a start date and end date — never
/// split into per-day documents. A single-day job simply has
/// startDate == endDate. See isMultiDay / dateRangeLabel below.
///
/// Customer fields are all optional: internal jobs with no customer and
/// no physical location must be fully supported (Section 7).
class JobModel {
  final String jobId;
  final String companyId;

  final String title;
  final String? description;
  final String? notes;

  // --- Customer (all optional; a job may have no customer at all) ---
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? customerAddress;

  /// The physical work site, if any. May differ from customerAddress
  /// (e.g. job performed at a location other than the customer's own
  /// address), and may be null entirely for internal/office jobs.
  final String? jobLocation;

  /// Additional stops beyond the primary [jobLocation] — e.g. a moving
  /// job with several pickup/drop-off addresses. Capped at 4 entries
  /// (5 total including the primary) — enforced where the list is
  /// actually built (toMapForCreate/copyWith below), not just trusted
  /// from callers, since a job address list has no legitimate reason
  /// to grow unbounded.
  static const maxAdditionalLocations = 4;
  final List<String> additionalJobLocations;

  // --- Scheduling ---
  /// Date-only (time components should be zeroed by the caller). For a
  /// single-day job, startDate == endDate.
  final DateTime startDate;
  final DateTime endDate;

  /// Specific time-of-day window, if this isn't an all-day job. Null
  /// means all-day. When set, these represent the time portion for the
  /// startDate/endDate above.
  final DateTime? startTime;
  final DateTime? endTime;

  // --- Assignment ---
  final List<String> assignedCrewIds;
  final List<String> assignedEmployeeIds;
  final List<String> assignedVehicleIds;
  final List<String> assignedEquipmentIds;

  // --- Status lifecycle ---
  final String status; // FSJobStatus.*
  final DateTime? statusChangedAt;
  final String? statusChangedBy;

  final String? cancellationReason;
  final String? cancelledBy;
  final DateTime? cancelledAt;

  final String? completedBy;
  final DateTime? completedAt;

  final String? reopenedBy;
  final DateTime? reopenedAt;

  /// Set if this job was created from a job template, for traceability.
  final String? templateId;

  /// Links to this job's dedicated conversation thread
  /// (companies/{companyId}/messageThreads/{threadId}), if one exists.
  final String? conversationThreadId;

  final String createdByUserId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const JobModel({
    required this.jobId,
    required this.companyId,
    required this.title,
    this.description,
    this.notes,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.customerAddress,
    this.jobLocation,
    this.additionalJobLocations = const [],
    required this.startDate,
    required this.endDate,
    this.startTime,
    this.endTime,
    required this.assignedCrewIds,
    required this.assignedEmployeeIds,
    this.assignedVehicleIds = const [],
    this.assignedEquipmentIds = const [],
    required this.status,
    this.statusChangedAt,
    this.statusChangedBy,
    this.cancellationReason,
    this.cancelledBy,
    this.cancelledAt,
    this.completedBy,
    this.completedAt,
    this.reopenedBy,
    this.reopenedAt,
    this.templateId,
    this.conversationThreadId,
    required this.createdByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isMultiDay =>
      startDate.year != endDate.year ||
      startDate.month != endDate.month ||
      startDate.day != endDate.day;

  bool get isAllDay => startTime == null && endTime == null;

  bool get hasCustomer =>
      (customerName != null && customerName!.trim().isNotEmpty);

  bool get hasLocation => jobLocation != null && jobLocation!.trim().isNotEmpty;

  bool get hasAdditionalLocations => additionalJobLocations.isNotEmpty;

  bool get isActive =>
      status == FSJobStatus.draft ||
      status == FSJobStatus.scheduled ||
      status == FSJobStatus.inProgress;

  bool get isTerminal =>
      status == FSJobStatus.completed ||
      status == FSJobStatus.cancelled ||
      status == FSJobStatus.archived;

  /// Validates that end date is not before start date. Callers (the
  /// service layer / forms) must check this before writing.
  static bool isValidDateRange(DateTime start, DateTime end) =>
      !end.isBefore(start);

  /// Returns the deduplicated set of employee IDs directly assigned,
  /// excluding any employeeIds also reachable through assignedCrewIds.
  /// The caller must supply crew membership (from EmployeeModel.crewId
  /// queries) since crew rosters are dynamic and not stored on the job.
  static List<String> dedupeDirectAssignments({
    required List<String> directEmployeeIds,
    required Set<String> employeeIdsInAssignedCrews,
  }) {
    return directEmployeeIds
        .where((id) => !employeeIdsInAssignedCrews.contains(id))
        .toList();
  }

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'title': title,
      'description': description,
      'notes': notes,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'customerAddress': customerAddress,
      'jobLocation': jobLocation,
      'additionalJobLocations': additionalJobLocations,
      FSFields.startDate: Timestamp.fromDate(startDate),
      FSFields.endDate: Timestamp.fromDate(endDate),
      'startTime': startTime != null ? Timestamp.fromDate(startTime!) : null,
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'assignedCrewIds': assignedCrewIds,
      'assignedEmployeeIds': assignedEmployeeIds,
      'assignedVehicleIds': assignedVehicleIds,
      'assignedEquipmentIds': assignedEquipmentIds,
      FSFields.status: status,
      FSFields.statusChangedAt: statusChangedAt != null
          ? Timestamp.fromDate(statusChangedAt!)
          : null,
      FSFields.statusChangedBy: statusChangedBy,
      'cancellationReason': cancellationReason,
      'cancelledBy': cancelledBy,
      'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
      'completedBy': completedBy,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'reopenedBy': reopenedBy,
      'reopenedAt': reopenedAt != null ? Timestamp.fromDate(reopenedAt!) : null,
      'templateId': templateId,
      'conversationThreadId': conversationThreadId,
      'createdByUserId': createdByUserId,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String title,
    String? description,
    String? notes,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? jobLocation,
    List<String> additionalJobLocations = const [],
    required DateTime startDate,
    required DateTime endDate,
    DateTime? startTime,
    DateTime? endTime,
    List<String> assignedCrewIds = const [],
    List<String> assignedEmployeeIds = const [],
    List<String> assignedVehicleIds = const [],
    List<String> assignedEquipmentIds = const [],
    String status = FSJobStatus.draft,
    String? templateId,
    required String createdByUserId,
  }) {
    return {
      FSFields.companyId: companyId,
      'title': title,
      'description': description,
      'notes': notes,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'customerAddress': customerAddress,
      'jobLocation': jobLocation,
      'additionalJobLocations': additionalJobLocations.take(JobModel.maxAdditionalLocations).toList(),
      FSFields.startDate: Timestamp.fromDate(startDate),
      FSFields.endDate: Timestamp.fromDate(endDate),
      'startTime': startTime != null ? Timestamp.fromDate(startTime) : null,
      'endTime': endTime != null ? Timestamp.fromDate(endTime) : null,
      'assignedCrewIds': assignedCrewIds,
      'assignedEmployeeIds': assignedEmployeeIds,
      'assignedVehicleIds': assignedVehicleIds,
      'assignedEquipmentIds': assignedEquipmentIds,
      FSFields.status: status,
      FSFields.statusChangedAt: FieldValue.serverTimestamp(),
      FSFields.statusChangedBy: createdByUserId,
      'cancellationReason': null,
      'cancelledBy': null,
      'cancelledAt': null,
      'completedBy': null,
      'completedAt': null,
      'reopenedBy': null,
      'reopenedAt': null,
      'templateId': templateId,
      'conversationThreadId': null,
      'createdByUserId': createdByUserId,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  /// A job written before additionalJobLocations existed has an old
  /// single `secondJobLocation` string field instead — read that as a
  /// one-item list rather than silently dropping it. New writes only
  /// ever populate `additionalJobLocations`, so this is purely a
  /// read-time compatibility shim, not something new jobs produce.
  static List<String> _readAdditionalLocations(Map<String, dynamic> map) {
    final list = map['additionalJobLocations'];
    if (list is List) {
      return list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    final legacy = map['secondJobLocation']?.toString();
    if (legacy != null && legacy.trim().isNotEmpty) {
      return [legacy];
    }
    return const [];
  }

  factory JobModel.fromMap(String jobId, Map<String, dynamic> map) {
    final start = FSTimestamp.tryParse(map[FSFields.startDate]);
    final end = FSTimestamp.tryParse(map[FSFields.endDate]);
    final fallback = start ?? DateTime.now();

    return JobModel(
      jobId: jobId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString(),
      notes: map['notes']?.toString(),
      customerName: map['customerName']?.toString(),
      customerPhone: map['customerPhone']?.toString(),
      customerEmail: map['customerEmail']?.toString(),
      customerAddress: map['customerAddress']?.toString(),
      jobLocation: map['jobLocation']?.toString(),
      additionalJobLocations: _readAdditionalLocations(map),
      startDate: start ?? fallback,
      endDate: end ?? fallback,
      startTime: FSTimestamp.tryParse(map['startTime']),
      endTime: FSTimestamp.tryParse(map['endTime']),
      assignedCrewIds: List<String>.from(map['assignedCrewIds'] ?? []),
      assignedEmployeeIds:
          List<String>.from(map['assignedEmployeeIds'] ?? []),
      assignedVehicleIds: map['assignedVehicleIds'] is List
          ? List<String>.from(map['assignedVehicleIds'])
          : (map['assignedVehicleId'] != null ? [map['assignedVehicleId'].toString()] : const []),
      assignedEquipmentIds: List<String>.from(map['assignedEquipmentIds'] ?? const []),
      status: map[FSFields.status]?.toString() ?? FSJobStatus.draft,
      statusChangedAt: FSTimestamp.tryParse(map[FSFields.statusChangedAt]),
      statusChangedBy: map[FSFields.statusChangedBy]?.toString(),
      cancellationReason: map['cancellationReason']?.toString(),
      cancelledBy: map['cancelledBy']?.toString(),
      cancelledAt: FSTimestamp.tryParse(map['cancelledAt']),
      completedBy: map['completedBy']?.toString(),
      completedAt: FSTimestamp.tryParse(map['completedAt']),
      reopenedBy: map['reopenedBy']?.toString(),
      reopenedAt: FSTimestamp.tryParse(map['reopenedAt']),
      templateId: map['templateId']?.toString(),
      conversationThreadId: map['conversationThreadId']?.toString(),
      createdByUserId: map['createdByUserId']?.toString() ?? '',
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory JobModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Job document ${doc.id} has no data.');
    }
    return JobModel.fromMap(doc.id, data);
  }

  JobModel copyWith({
    String? title,
    String? description,
    String? notes,
    bool clearCustomer = false,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    bool clearLocation = false,
    String? jobLocation,
    List<String>? additionalJobLocations,
    DateTime? startDate,
    DateTime? endDate,
    bool clearTimes = false,
    DateTime? startTime,
    DateTime? endTime,
    List<String>? assignedCrewIds,
    List<String>? assignedEmployeeIds,
    bool clearVehicle = false,
    List<String>? assignedVehicleIds,
    List<String>? assignedEquipmentIds,
    String? status,
    DateTime? statusChangedAt,
    String? statusChangedBy,
    String? cancellationReason,
    String? cancelledBy,
    DateTime? cancelledAt,
    String? completedBy,
    DateTime? completedAt,
    String? reopenedBy,
    DateTime? reopenedAt,
    String? templateId,
    String? conversationThreadId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JobModel(
      jobId: jobId,
      companyId: companyId,
      title: title ?? this.title,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
      customerPhone:
          clearCustomer ? null : (customerPhone ?? this.customerPhone),
      customerEmail:
          clearCustomer ? null : (customerEmail ?? this.customerEmail),
      customerAddress:
          clearCustomer ? null : (customerAddress ?? this.customerAddress),
      jobLocation: clearLocation ? null : (jobLocation ?? this.jobLocation),
      additionalJobLocations: clearLocation
          ? const []
          : (additionalJobLocations?.take(JobModel.maxAdditionalLocations).toList() ?? this.additionalJobLocations),
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      startTime: clearTimes ? null : (startTime ?? this.startTime),
      endTime: clearTimes ? null : (endTime ?? this.endTime),
      assignedCrewIds: assignedCrewIds ?? this.assignedCrewIds,
      assignedEmployeeIds: assignedEmployeeIds ?? this.assignedEmployeeIds,
      assignedVehicleIds: clearVehicle ? const [] : (assignedVehicleIds ?? this.assignedVehicleIds),
      assignedEquipmentIds: clearVehicle ? const [] : (assignedEquipmentIds ?? this.assignedEquipmentIds),
      status: status ?? this.status,
      statusChangedAt: statusChangedAt ?? this.statusChangedAt,
      statusChangedBy: statusChangedBy ?? this.statusChangedBy,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      completedBy: completedBy ?? this.completedBy,
      completedAt: completedAt ?? this.completedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      templateId: templateId ?? this.templateId,
      conversationThreadId: conversationThreadId ?? this.conversationThreadId,
      createdByUserId: createdByUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
