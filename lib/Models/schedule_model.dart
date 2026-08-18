import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// What kind of thing a schedule entry represents.
class ScheduleType {
  ScheduleType._();

  static const job = 'job'; // linked to a JobModel via jobId
  static const shift = 'shift'; // plain work shift, no job attached
  static const meeting = 'meeting';
  static const other = 'other';
}

/// A schedule entry publishing status. Employees should not see or be
/// notified about draft entries — only published ones.
class ScheduleStatus {
  ScheduleStatus._();

  static const draft = 'draft';
  static const published = 'published';
}

/// A calendar/schedule entry. Stored at
/// `companies/{companyId}/schedules/{scheduleId}`.
///
/// Overnight shifts are handled naturally since startAt/endAt are full
/// timestamps, not date-only values — an entry starting at 10 PM and
/// ending at 6 AM the next day is just endAt.isAfter(startAt) with a
/// day boundary crossed, no special-casing required by callers.
class ScheduleModel {
  final String scheduleId;
  final String companyId;

  final String title;
  final String? description;

  final bool isAllDay;

  /// Full timestamps (date + time). For an all-day entry, callers should
  /// set startAt to the start of day and endAt to the end of day.
  final DateTime startAt;
  final DateTime endAt;

  final String type; // ScheduleType.*
  final String? jobId; // set when type == ScheduleType.job

  final List<String> crewIds;
  final List<String> employeeIds;

  final String status; // ScheduleStatus.*
  final DateTime? publishedAt;
  final String? publishedBy;

  /// True if the creator explicitly acknowledged and overrode a
  /// scheduling conflict warning (double-booked employee/crew/vehicle,
  /// or overlap with approved time off) when this was saved. Conflict
  /// detection itself is computed live by schedule_service, not stored.
  final bool conflictOverrideAcknowledged;

  final String createdByUserId;
  final String? lastEditedByUserId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const ScheduleModel({
    required this.scheduleId,
    required this.companyId,
    required this.title,
    this.description,
    required this.isAllDay,
    required this.startAt,
    required this.endAt,
    required this.type,
    this.jobId,
    required this.crewIds,
    required this.employeeIds,
    required this.status,
    this.publishedAt,
    this.publishedBy,
    this.conflictOverrideAcknowledged = false,
    required this.createdByUserId,
    this.lastEditedByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDraft => status == ScheduleStatus.draft;
  bool get isPublished => status == ScheduleStatus.published;

  bool get spansMidnight =>
      startAt.year != endAt.year ||
      startAt.month != endAt.month ||
      startAt.day != endAt.day;

  static bool isValidTimeRange(DateTime start, DateTime end) =>
      end.isAfter(start);

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'title': title,
      'description': description,
      'isAllDay': isAllDay,
      FSFields.startAt: Timestamp.fromDate(startAt),
      FSFields.endAt: Timestamp.fromDate(endAt),
      'type': type,
      FSFields.jobId: jobId,
      'crewIds': crewIds,
      'employeeIds': employeeIds,
      FSFields.status: status,
      'publishedAt': publishedAt != null ? Timestamp.fromDate(publishedAt!) : null,
      'publishedBy': publishedBy,
      'conflictOverrideAcknowledged': conflictOverrideAcknowledged,
      'createdByUserId': createdByUserId,
      'lastEditedByUserId': lastEditedByUserId,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String title,
    String? description,
    bool isAllDay = false,
    required DateTime startAt,
    required DateTime endAt,
    String type = ScheduleType.shift,
    String? jobId,
    List<String> crewIds = const [],
    List<String> employeeIds = const [],
    String status = ScheduleStatus.draft,
    bool conflictOverrideAcknowledged = false,
    required String createdByUserId,
  }) {
    return {
      FSFields.companyId: companyId,
      'title': title,
      'description': description,
      'isAllDay': isAllDay,
      FSFields.startAt: Timestamp.fromDate(startAt),
      FSFields.endAt: Timestamp.fromDate(endAt),
      'type': type,
      FSFields.jobId: jobId,
      'crewIds': crewIds,
      'employeeIds': employeeIds,
      FSFields.status: status,
      'publishedAt':
          status == ScheduleStatus.published ? FieldValue.serverTimestamp() : null,
      'publishedBy': status == ScheduleStatus.published ? createdByUserId : null,
      'conflictOverrideAcknowledged': conflictOverrideAcknowledged,
      'createdByUserId': createdByUserId,
      'lastEditedByUserId': null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory ScheduleModel.fromMap(String scheduleId, Map<String, dynamic> map) {
    final start = FSTimestamp.tryParse(map[FSFields.startAt]);
    final end = FSTimestamp.tryParse(map[FSFields.endAt]);
    final fallback = start ?? DateTime.now();

    return ScheduleModel(
      scheduleId: scheduleId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString(),
      isAllDay: map['isAllDay'] == true,
      startAt: start ?? fallback,
      endAt: end ?? fallback,
      type: map['type']?.toString() ?? ScheduleType.shift,
      jobId: map[FSFields.jobId]?.toString(),
      crewIds: List<String>.from(map['crewIds'] ?? []),
      employeeIds: List<String>.from(map['employeeIds'] ?? []),
      status: map[FSFields.status]?.toString() ?? ScheduleStatus.draft,
      publishedAt: FSTimestamp.tryParse(map['publishedAt']),
      publishedBy: map['publishedBy']?.toString(),
      conflictOverrideAcknowledged:
          map['conflictOverrideAcknowledged'] == true,
      createdByUserId: map['createdByUserId']?.toString() ?? '',
      lastEditedByUserId: map['lastEditedByUserId']?.toString(),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory ScheduleModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Schedule document ${doc.id} has no data.');
    }
    return ScheduleModel.fromMap(doc.id, data);
  }

  ScheduleModel copyWith({
    String? title,
    String? description,
    bool? isAllDay,
    DateTime? startAt,
    DateTime? endAt,
    String? type,
    bool clearJob = false,
    String? jobId,
    List<String>? crewIds,
    List<String>? employeeIds,
    String? status,
    DateTime? publishedAt,
    String? publishedBy,
    bool? conflictOverrideAcknowledged,
    String? lastEditedByUserId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduleModel(
      scheduleId: scheduleId,
      companyId: companyId,
      title: title ?? this.title,
      description: description ?? this.description,
      isAllDay: isAllDay ?? this.isAllDay,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      type: type ?? this.type,
      jobId: clearJob ? null : (jobId ?? this.jobId),
      crewIds: crewIds ?? this.crewIds,
      employeeIds: employeeIds ?? this.employeeIds,
      status: status ?? this.status,
      publishedAt: publishedAt ?? this.publishedAt,
      publishedBy: publishedBy ?? this.publishedBy,
      conflictOverrideAcknowledged:
          conflictOverrideAcknowledged ?? this.conflictOverrideAcknowledged,
      createdByUserId: createdByUserId,
      lastEditedByUserId: lastEditedByUserId ?? this.lastEditedByUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
