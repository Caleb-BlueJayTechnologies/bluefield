import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// How a time entry came to exist.
class TimeEntrySource {
  TimeEntrySource._();

  static const clock = 'clock'; // employee clocked in/out normally
  static const manual = 'manual'; // created directly by management
  static const correction = 'correction'; // created from an approved correction request
}

/// A single break taken during a shift. Breaks live inside their
/// parent TimeEntryModel's [TimeEntryModel.breaks] list rather than as
/// their own clock-out/clock-in pair — starting or ending a break
/// never touches clockInAt/clockOutAt, so the shift's own running
/// timer (and the entry's identity) is unaffected by however many
/// breaks happen during it. See TimeEntryService.startBreak/endBreak.
class BreakEntry {
  final DateTime startedAt;

  /// Null while the break is still ongoing.
  final DateTime? endedAt;

  /// Employee's own choice at the moment they started the break (see
  /// TimeEntryService.startBreak) — paid break time still counts
  /// toward worked/payable hours and exists purely so management can
  /// see how much paid break time was taken; unpaid break time is
  /// subtracted from payable hours at payroll time (see
  /// TimeEntryModel.payableDuration).
  final bool isPaid;

  const BreakEntry({
    required this.startedAt,
    this.endedAt,
    required this.isPaid,
  });

  bool get isActive => endedAt == null;

  /// Duration so far — the completed span once ended, or time elapsed
  /// since it started for a still-active break (computed fresh each
  /// call, same as TimeEntryModel.rawDuration never storing a value).
  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  Map<String, dynamic> toMap() {
    return {
      'startedAt': Timestamp.fromDate(startedAt),
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'isPaid': isPaid,
    };
  }

  factory BreakEntry.fromMap(Map<String, dynamic> map) {
    return BreakEntry(
      startedAt: FSTimestamp.parseOr(map['startedAt']),
      endedAt: FSTimestamp.tryParse(map['endedAt']),
      isPaid: map['isPaid'] == true,
    );
  }

  BreakEntry copyWith({DateTime? endedAt}) {
    return BreakEntry(
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      isPaid: isPaid,
    );
  }
}

/// A single clock-in/clock-out record. Stored at
/// `companies/{companyId}/timeEntries/{timeEntryId}`.
///
/// Raw clockInAt/clockOutAt are always the true, unmodified values (or
/// the corrected values, if a correction was approved — see
/// originalClockInAt/originalClockOutAt for what came before). Rounding
/// is NEVER stored on this model — it must be computed on demand from
/// the company's clock-rounding policy at display/payroll time, via
/// [applyRounding] below, so raw history stays intact even if the
/// company's rounding setting changes later.
class TimeEntryModel {
  final String timeEntryId;
  final String companyId;
  final String employeeId;

  final String? jobId;
  final String? crewId;

  /// Raw, authoritative clock-in time (server timestamp when created).
  final DateTime clockInAt;

  /// Null while the employee is still clocked in.
  final DateTime? clockOutAt;

  final String? clockInLocation;
  final String? clockOutLocation;

  /// True if this clock-out was for a break, not the end of the
  /// shift. Doesn't change payroll math at all — the gap between this
  /// entry's clockOutAt and the next entry's clockInAt is already
  /// naturally unpaid, since totals are summed per-entry, not across
  /// a whole day. This just lets the UI and reports show "took a
  /// break" instead of it looking like two unrelated shifts.
  final bool isBreak;

  /// True if this specific clock-in/out happened outside the
  /// company's configured clock-in zone. Persisted permanently (not
  /// just a one-time notification) so managers reviewing time history
  /// later can still see it happened.
  final bool isOutsideGeofenceAtClockIn;
  final bool isOutsideGeofenceAtClockOut;

  final String? notes;

  final String source; // TimeEntrySource.*

  // --- Manual edit audit trail ---
  final String? editedBy;
  final DateTime? editedAt;
  final String? editReason;

  /// The values clockInAt/clockOutAt held before the most recent edit.
  /// Null if this entry has never been edited.
  final DateTime? originalClockInAt;
  final DateTime? originalClockOutAt;

  /// True once this entry has an unresolved correction request pending
  /// review. Maintained by the service layer when a correction request
  /// is created/approved/rejected — a lightweight cache to avoid an
  /// extra query on every list screen, not the source of truth (the
  /// correction request document itself is).
  final bool hasPendingCorrectionRequest;

  /// Set once this entry's pay period has been locked. Locked entries
  /// must not be editable without first reopening the period.
  final String? payPeriodId;
  final bool isLocked;

  /// Breaks taken during this shift — see BreakEntry above for why
  /// these live here instead of ending/restarting the clock-in/out
  /// pair. Empty for entries created before breaks were tracked this
  /// way, and for entries whose only break used the old
  /// clock-out-with-isBreak-true flow (that flow ended the entry
  /// entirely, so there was never anything to append here).
  final List<BreakEntry> breaks;

  final DateTime createdAt;
  final DateTime updatedAt;

  const TimeEntryModel({
    required this.timeEntryId,
    required this.companyId,
    required this.employeeId,
    this.jobId,
    this.crewId,
    required this.clockInAt,
    this.clockOutAt,
    this.clockInLocation,
    this.clockOutLocation,
    this.isBreak = false,
    this.isOutsideGeofenceAtClockIn = false,
    this.isOutsideGeofenceAtClockOut = false,
    this.notes,
    this.source = TimeEntrySource.clock,
    this.editedBy,
    this.editedAt,
    this.editReason,
    this.originalClockInAt,
    this.originalClockOutAt,
    this.hasPendingCorrectionRequest = false,
    this.payPeriodId,
    this.isLocked = false,
    this.breaks = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => clockOutAt == null;
  bool get isComplete => clockOutAt != null;
  bool get isEdited => editedAt != null;
  bool get spansMidnight =>
      clockOutAt != null &&
      (clockOutAt!.year != clockInAt.year ||
          clockOutAt!.month != clockInAt.month ||
          clockOutAt!.day != clockInAt.day);

  /// The break currently in progress, if any. There should only ever
  /// be at most one — TimeEntryService.startBreak refuses to start a
  /// second one while one is already active.
  BreakEntry? get activeBreak {
    for (final b in breaks) {
      if (b.isActive) return b;
    }
    return null;
  }

  bool get isOnBreak => activeBreak != null;

  /// Paid break time is tracked purely for management visibility — it
  /// still counts as worked/payable time, so it's never subtracted
  /// from rawDuration/roundedDuration/payableDuration below.
  Duration get totalPaidBreakDuration => breaks
      .where((b) => b.isPaid)
      .fold(Duration.zero, (sum, b) => sum + b.duration);

  /// Subtracted from payable hours at payroll time — see
  /// payableDuration. Still counted toward rawDuration/roundedDuration
  /// (the clock literally keeps running through an unpaid break), it's
  /// only removed from what actually gets paid.
  Duration get totalUnpaidBreakDuration => breaks
      .where((b) => !b.isPaid)
      .fold(Duration.zero, (sum, b) => sum + b.duration);

  /// Raw duration, computed on demand (never stored, so it can never go
  /// stale relative to the raw timestamps it's derived from). Includes
  /// break time (paid and unpaid) — this is the plain clock-in-to-
  /// clock-out span, not what's payable; see payableDuration for that.
  Duration? get rawDuration =>
      clockOutAt != null ? clockOutAt!.difference(clockInAt) : null;

  /// Applies a clock-rounding policy (FSClockRounding.*) to a single
  /// timestamp for payroll/display purposes only. The stored raw value
  /// is never changed by this — call it fresh wherever a rounded value
  /// is needed.
  ///
  /// [roundDown] controls the rounding direction:
  /// - false (default): rounds to the NEAREST interval boundary,
  ///   half-up on an exact tie. Used for clock-out.
  /// - true: always rounds DOWN to the interval boundary at or before
  ///   the raw time, never up regardless of how close it is to the
  ///   next boundary. Used for clock-in, so an employee who punches in
  ///   a few minutes early — or a few minutes into the next interval —
  ///   is never rounded up into extra paid time.
  static DateTime applyRounding(DateTime time, String roundingPolicy, {bool roundDown = false}) {
    final int intervalMinutes;
    switch (roundingPolicy) {
      case FSClockRounding.nearest5:
        intervalMinutes = 5;
        break;
      case FSClockRounding.nearest6:
        intervalMinutes = 6;
        break;
      case FSClockRounding.nearest10:
        intervalMinutes = 10;
        break;
      case FSClockRounding.nearest15:
        intervalMinutes = 15;
        break;
      case FSClockRounding.none:
      default:
        return time;
    }

    final totalMinutes = time.hour * 60 + time.minute;
    final remainder = totalMinutes % intervalMinutes;
    final roundedTotalMinutes = roundDown
        ? totalMinutes - remainder
        : (remainder * 2 >= intervalMinutes
            ? totalMinutes + (intervalMinutes - remainder)
            : totalMinutes - remainder);

    final dayStart = DateTime(time.year, time.month, time.day);
    return dayStart.add(Duration(minutes: roundedTotalMinutes));
  }

  /// Rounded duration for payroll, given a rounding policy. Still
  /// computed on demand — nothing here is persisted.
  ///
  /// Clock-in and clock-out round in different directions on purpose:
  /// clock-in always rounds DOWN (roundDown: true) so an early or
  /// just-past-the-boundary punch-in never gets rounded up into extra
  /// paid time, while clock-out rounds to the NEAREST boundary (the
  /// default). See applyRounding's doc comment for the full rationale.
  Duration? roundedDuration(String roundingPolicy) {
    if (clockOutAt == null) return null;
    final roundedIn = applyRounding(clockInAt, roundingPolicy, roundDown: true);
    final roundedOut = applyRounding(clockOutAt!, roundingPolicy);
    final diff = roundedOut.difference(roundedIn);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// What's actually payable for this entry: the rounded clock-in/out
  /// span minus any unpaid break time taken during it. This is what
  /// payroll math (pay_period_service.dart) should sum, not
  /// roundedDuration directly — roundedDuration is the raw punched
  /// span including unpaid breaks, payableDuration is what the
  /// employee is owed for. Paid break time is deliberately NOT
  /// subtracted (see totalPaidBreakDuration's doc comment). Null while
  /// the entry is still active, same as roundedDuration.
  Duration? payableDuration(String roundingPolicy) {
    final base = roundedDuration(roundingPolicy);
    if (base == null) return null;
    final result = base - totalUnpaidBreakDuration;
    return result.isNegative ? Duration.zero : result;
  }

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      FSFields.employeeId: employeeId,
      FSFields.jobId: jobId,
      FSFields.crewId: crewId,
      FSFields.clockInAt: Timestamp.fromDate(clockInAt),
      FSFields.clockOutAt: clockOutAt != null ? Timestamp.fromDate(clockOutAt!) : null,
      'clockInLocation': clockInLocation,
      'clockOutLocation': clockOutLocation,
      'isBreak': isBreak,
      'isOutsideGeofenceAtClockIn': isOutsideGeofenceAtClockIn,
      'isOutsideGeofenceAtClockOut': isOutsideGeofenceAtClockOut,
      'notes': notes,
      'source': source,
      'editedBy': editedBy,
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,
      'editReason': editReason,
      FSFields.originalValue: originalClockInAt != null
          ? Timestamp.fromDate(originalClockInAt!)
          : null,
      'originalClockOutAt': originalClockOutAt != null
          ? Timestamp.fromDate(originalClockOutAt!)
          : null,
      'hasPendingCorrectionRequest': hasPendingCorrectionRequest,
      'payPeriodId': payPeriodId,
      'isLocked': isLocked,
      'breaks': breaks.map((b) => b.toMap()).toList(),
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForClockIn({
    required String companyId,
    required String employeeId,
    String? jobId,
    String? crewId,
    String? clockInLocation,
    String? notes,
  }) {
    return {
      FSFields.companyId: companyId,
      FSFields.employeeId: employeeId,
      FSFields.jobId: jobId,
      FSFields.crewId: crewId,
      FSFields.clockInAt: FieldValue.serverTimestamp(),
      FSFields.clockOutAt: null,
      'clockInLocation': clockInLocation,
      'clockOutLocation': null,
      'isBreak': false,
      'isOutsideGeofenceAtClockIn': false,
      'isOutsideGeofenceAtClockOut': false,
      'notes': notes,
      'source': TimeEntrySource.clock,
      'editedBy': null,
      'editedAt': null,
      'editReason': null,
      FSFields.originalValue: null,
      'originalClockOutAt': null,
      'hasPendingCorrectionRequest': false,
      'payPeriodId': null,
      'isLocked': false,
      'breaks': <Map<String, dynamic>>[],
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory TimeEntryModel.fromMap(String timeEntryId, Map<String, dynamic> map) {
    return TimeEntryModel(
      timeEntryId: timeEntryId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      employeeId: map[FSFields.employeeId]?.toString() ?? '',
      jobId: map[FSFields.jobId]?.toString(),
      crewId: map[FSFields.crewId]?.toString(),
      clockInAt: FSTimestamp.parseOr(map[FSFields.clockInAt]),
      clockOutAt: FSTimestamp.tryParse(map[FSFields.clockOutAt]),
      clockInLocation: map['clockInLocation']?.toString(),
      clockOutLocation: map['clockOutLocation']?.toString(),
      isBreak: map['isBreak'] == true,
      isOutsideGeofenceAtClockIn: map['isOutsideGeofenceAtClockIn'] == true,
      isOutsideGeofenceAtClockOut: map['isOutsideGeofenceAtClockOut'] == true,
      notes: map['notes']?.toString(),
      source: map['source']?.toString() ?? TimeEntrySource.clock,
      editedBy: map['editedBy']?.toString(),
      editedAt: FSTimestamp.tryParse(map['editedAt']),
      editReason: map['editReason']?.toString(),
      originalClockInAt: FSTimestamp.tryParse(map[FSFields.originalValue]),
      originalClockOutAt: FSTimestamp.tryParse(map['originalClockOutAt']),
      hasPendingCorrectionRequest:
          map['hasPendingCorrectionRequest'] == true,
      payPeriodId: map['payPeriodId']?.toString(),
      isLocked: map['isLocked'] == true,
      breaks: (map['breaks'] as List<dynamic>? ?? [])
          .map((b) => BreakEntry.fromMap(Map<String, dynamic>.from(b as Map)))
          .toList(),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory TimeEntryModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Time entry document ${doc.id} has no data.');
    }
    return TimeEntryModel.fromMap(doc.id, data);
  }

  TimeEntryModel copyWith({
    String? jobId,
    String? crewId,
    DateTime? clockInAt,
    bool clearClockOut = false,
    DateTime? clockOutAt,
    String? clockInLocation,
    String? clockOutLocation,
    bool? isBreak,
    bool? isOutsideGeofenceAtClockIn,
    bool? isOutsideGeofenceAtClockOut,
    String? notes,
    String? source,
    String? editedBy,
    DateTime? editedAt,
    String? editReason,
    DateTime? originalClockInAt,
    DateTime? originalClockOutAt,
    bool? hasPendingCorrectionRequest,
    String? payPeriodId,
    bool? isLocked,
    List<BreakEntry>? breaks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TimeEntryModel(
      timeEntryId: timeEntryId,
      companyId: companyId,
      employeeId: employeeId,
      jobId: jobId ?? this.jobId,
      crewId: crewId ?? this.crewId,
      clockInAt: clockInAt ?? this.clockInAt,
      clockOutAt: clearClockOut ? null : (clockOutAt ?? this.clockOutAt),
      clockInLocation: clockInLocation ?? this.clockInLocation,
      clockOutLocation: clockOutLocation ?? this.clockOutLocation,
      isBreak: isBreak ?? this.isBreak,
      isOutsideGeofenceAtClockIn: isOutsideGeofenceAtClockIn ?? this.isOutsideGeofenceAtClockIn,
      isOutsideGeofenceAtClockOut: isOutsideGeofenceAtClockOut ?? this.isOutsideGeofenceAtClockOut,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      editedBy: editedBy ?? this.editedBy,
      editedAt: editedAt ?? this.editedAt,
      editReason: editReason ?? this.editReason,
      originalClockInAt: originalClockInAt ?? this.originalClockInAt,
      originalClockOutAt: originalClockOutAt ?? this.originalClockOutAt,
      hasPendingCorrectionRequest:
          hasPendingCorrectionRequest ?? this.hasPendingCorrectionRequest,
      payPeriodId: payPeriodId ?? this.payPeriodId,
      isLocked: isLocked ?? this.isLocked,
      breaks: breaks ?? this.breaks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
