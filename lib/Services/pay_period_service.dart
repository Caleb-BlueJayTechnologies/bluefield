import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/employee_model.dart';
import '../Models/membership.dart';
import '../Models/pay_period_model.dart';
import '../Models/time_entry_model.dart';
import '../Models/time_off_request_model.dart';
import 'company_audit_log_service.dart';
import 'company_settings_service.dart';

/// Per-employee row in a weekly/period payroll summary.
class PayrollSummaryRow {
  final String employeeId;
  final String employeeName;
  final bool isArchived;

  /// Date (day-only) -> hours worked that day.
  final Map<DateTime, double> dailyHours;

  final double regularHours;
  final double overtimeHours;
  final double paidLeaveHours;
  final double unpaidLeaveHours;
  final int editedEntryCount;
  final int missingClockOutCount;

  const PayrollSummaryRow({
    required this.employeeId,
    required this.employeeName,
    required this.isArchived,
    required this.dailyHours,
    required this.regularHours,
    required this.overtimeHours,
    required this.paidLeaveHours,
    required this.unpaidLeaveHours,
    required this.editedEntryCount,
    required this.missingClockOutCount,
  });

  double get totalWorkedHours => regularHours + overtimeHours;
  double get totalHours => totalWorkedHours + paidLeaveHours;
}

/// Payroll preparation (Section 9). Deliberately does NOT calculate
/// wages — see Section 9's "keep wage calculations out until
/// intentionally implemented and legally reviewed." This only totals
/// hours for the owner to hand off to whatever payroll process they use.
///
/// Cycle type (weekly/biweekly/etc), rounding rule, and workweek start
/// day are read from company_settings_service rather than duplicated
/// here — those already exist on CompanySettingsModel. This service
/// only stores what genuinely doesn't exist elsewhere yet: the anchor
/// date for calculating period boundaries, and the overtime threshold.
/// One day's clock-in/out for a detailed printable timesheet — unlike
/// PayrollSummaryRow.dailyHours (which only keeps the total), this
/// preserves the actual punch times so a printable report can show
/// "7:30 AM - 3:15 PM" the way a physical timesheet would.
class DailyPunch {
  final DateTime date;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final double hours;
  final bool isEdited;
  final bool isMissingClockOut;

  const DailyPunch({
    required this.date,
    required this.clockInAt,
    this.clockOutAt,
    required this.hours,
    this.isEdited = false,
    this.isMissingClockOut = false,
  });
}

/// One calendar week's worth of punches plus the week total — a
/// biweekly pay period is two of these back to back.
class WeekTimesheet {
  final DateTime weekStart;
  final List<DailyPunch> punches;
  final double totalHours;

  const WeekTimesheet({
    required this.weekStart,
    required this.punches,
    required this.totalHours,
  });
}

/// One employee's full detailed timesheet for a pay period — the
/// data behind the printable report, grouped into weeks with a
/// period total, matching a traditional paper timesheet's layout.
class DetailedTimesheet {
  final String employeeId;
  final String employeeName;
  final bool isArchived;
  final List<WeekTimesheet> weeks;
  final double periodTotalHours;

  const DetailedTimesheet({
    required this.employeeId,
    required this.employeeName,
    required this.isArchived,
    required this.weeks,
    required this.periodTotalHours,
  });
}

class PayPeriodService {
  final FirebaseFirestore _firestore;
  final CompanySettingsService _settingsService;
  final CompanyAuditLogService _auditLogService;

  PayPeriodService({
    FirebaseFirestore? firestore,
    CompanySettingsService? settingsService,
    CompanyAuditLogService? auditLogService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _settingsService = settingsService ?? CompanySettingsService(),
        _auditLogService = auditLogService ?? CompanyAuditLogService();

  /// Best-effort display name lookup for audit log readability — same
  /// pattern used by EmployeeService/JobService/CompanyService.
  Future<String?> _fullNameForUser(String userId) async {
    final doc = await _firestore.collection(FSCollections.users).doc(userId).get();
    final data = doc.data();
    if (data == null) return null;
    final first = data['firstName']?.toString() ?? '';
    final last = data['lastName']?.toString() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? null : full;
  }

  CollectionReference<Map<String, dynamic>> _payPeriodsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.payPeriods);
  }

  DocumentReference<Map<String, dynamic>> _cycleAnchorRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection('payrollCycleSettings')
        .doc('main');
  }

  CollectionReference<Map<String, dynamic>> _timeEntriesRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeEntries);
  }

  CollectionReference<Map<String, dynamic>> _timeOffRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeOffRequests);
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

  Future<void> _requireOwner({
    required String companyId,
    required String actingUserId,
  }) async {
    final doc = await _membershipsRef(companyId).doc(actingUserId).get();
    if (!doc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(doc);
    if (!membership.grantsAccess || !membership.isOwner) {
      throw Exception('Only owners can manage payroll periods and settings.');
    }
  }

  /// Owner check plus the "Pay Periods" company-settings toggle. Every
  /// mutating/exporting method below used to skip straight to
  /// _requireOwner with no feature-toggle check at all — enforcement
  /// was UI-only (team_time_screen.dart just hides the nav entry), so
  /// disabling Pay Periods after a session already had this screen
  /// open didn't actually stop locking/unlocking/deleting periods or
  /// exporting payroll. Matches the isXEnabled/requireXEnabled
  /// dispatcher pattern every other feature toggle in the app follows.
  Future<void> _requireOwnerAndPayPeriodsEnabled({
    required String companyId,
    required String actingUserId,
  }) async {
    await _requireOwner(
      companyId: companyId,
      actingUserId: actingUserId,
    );
    final settings = await _settingsService.getCompanySettings(companyId);
    _settingsService.requirePayPeriodsEnabled(settings);
  }

  DateTime _startOfDay(DateTime v) => DateTime(v.year, v.month, v.day);
  DateTime _endOfDay(DateTime v) =>
      DateTime(v.year, v.month, v.day, 23, 59, 59, 999);

  /// How many of [request]'s hours actually fall inside this pay
  /// period, for a request whose date range may extend outside it.
  ///
  /// The overlap filter above only decides whether a request touches
  /// the period at all — it doesn't say how MUCH of the request is
  /// inside it. A prior version added the request's full totalHours to
  /// every period it overlapped, so a 5-day PTO request spanning
  /// Dec 29-Jan 2 counted its full hours in BOTH the period ending
  /// Dec 31 and the one starting Jan 1 — double-paying (or worse, for
  /// a request touching 3+ periods) the same leave. totalHours is
  /// snapshotted as a single number for the whole request (see
  /// TimeOffRequestModel's doc comment), with no per-day breakdown
  /// stored, so this assumes it's spread evenly across the request's
  /// own days — true for the default 8-hours/day case
  /// (TimeOffService.submitTimeOffRequest), and the most reasonable
  /// assumption available for a caller-supplied total.
  double _proratedTimeOffHours({
    required TimeOffRequestModel request,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final totalHours = request.totalHours ?? 0;
    if (totalHours <= 0) return 0;

    final requestStart = _startOfDay(request.startDate);
    final requestEnd = _startOfDay(request.endDate);
    final totalDays = requestEnd.difference(requestStart).inDays + 1;
    if (totalDays <= 0) return 0;

    final overlapStart =
        requestStart.isAfter(periodStart) ? requestStart : periodStart;
    final overlapEnd = requestEnd.isBefore(periodEnd) ? requestEnd : periodEnd;
    final overlapDays =
        _startOfDay(overlapEnd).difference(_startOfDay(overlapStart)).inDays + 1;
    if (overlapDays <= 0) return 0;

    return totalHours / totalDays * overlapDays;
  }

  String _dateKey(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';

  String payPeriodIdFromDates(DateTime start, DateTime end) =>
      '${_dateKey(_startOfDay(start))}_${_dateKey(_startOfDay(end))}';

  String defaultPeriodName(DateTime start, DateTime end) =>
      '${start.month}/${start.day}/${start.year} - ${end.month}/${end.day}/${end.year}';

  /// Maps company_settings_service's free-text rounding rule strings
  /// ('5 minutes' / '10 minutes' / '15 minutes' / 'none') onto the
  /// FSClockRounding constants TimeEntryModel.applyRounding expects.
  String _mapRoundingRule(String raw) {
    switch (raw) {
      case '5 minutes':
        return FSClockRounding.nearest5;
      case '10 minutes':
        return FSClockRounding.nearest10;
      case '15 minutes':
        return FSClockRounding.nearest15;
      case 'none':
      default:
        return FSClockRounding.none;
    }
  }

  // --- Cycle anchor settings (firstPeriodStart + overtime threshold only —
  // everything else comes from company_settings_service) ---

  Future<Map<String, dynamic>?> getCycleAnchor(String companyId) async {
    final doc = await _cycleAnchorRef(companyId).get();
    return doc.data();
  }

  Future<void> saveCycleAnchor({
    required String companyId,
    required String actingUserId,
    required DateTime firstPeriodStart,
    int? customPeriodLengthDays,
    double overtimeThresholdHours = 40,
  }) async {
    await _requireOwnerAndPayPeriodsEnabled(companyId: companyId, actingUserId: actingUserId);

    await _cycleAnchorRef(companyId).set({
      'firstPeriodStart': Timestamp.fromDate(_startOfDay(firstPeriodStart)),
      'customPeriodLengthDays': customPeriodLengthDays,
      'overtimeThresholdHours': overtimeThresholdHours,
      'updatedByUserId': actingUserId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
      FSFields.createdAt: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  int _periodLengthForCycle(String cycleType, int? customDays) {
    switch (cycleType) {
      case 'weekly':
        return 7;
      case 'biweekly':
        return 14;
      case 'semimonthly':
        return 15; // approximate; semimonthly isn't a fixed interval
      case 'monthly':
        return 30; // approximate, same reason
      default:
        return (customDays != null && customDays > 0) ? customDays : 14;
    }
  }

  /// Calculates the pay period (start/end date) that [date] (default:
  /// today) falls within, based on the company's cycle type (from
  /// company_settings_service) and this service's anchor date.
  Future<Map<String, dynamic>?> calculateCurrentPayPeriod({
    required String companyId,
    DateTime? date,
  }) async {
    final settings = await _settingsService.getCompanySettings(companyId);
    final anchor = await getCycleAnchor(companyId);
    if (anchor == null || anchor['firstPeriodStart'] == null) return null;

    final firstStart =
        (anchor['firstPeriodStart'] as Timestamp).toDate();
    final cycleType = settings.payPeriodType;
    final customDays = (anchor['customPeriodLengthDays'] as num?)?.toInt();
    final periodLengthDays = _periodLengthForCycle(cycleType, customDays);

    final targetDate = _startOfDay(date ?? DateTime.now());
    final normalizedFirstStart = _startOfDay(firstStart);

    final dayDifference = targetDate.difference(normalizedFirstStart).inDays;
    final periodIndex = (dayDifference / periodLengthDays).floor();

    final periodStart =
        normalizedFirstStart.add(Duration(days: periodIndex * periodLengthDays));
    final periodEnd =
        _endOfDay(periodStart.add(Duration(days: periodLengthDays - 1)));

    return {
      'payPeriodId': payPeriodIdFromDates(periodStart, periodEnd),
      'name': defaultPeriodName(periodStart, periodEnd),
      'startDate': periodStart,
      'endDate': periodEnd,
      'cycleType': cycleType,
      'periodLengthDays': periodLengthDays,
    };
  }

  // --- Weekly / period payroll summary ---

  /// Builds the per-employee summary for [startDate]..[endDate].
  /// Includes archived employees who worked during the period, per
  /// Section 9 — the query is by employeeId on time entries directly,
  /// never filtered by current membership status.
  Future<List<PayrollSummaryRow>> buildPayrollSummary({
    required String companyId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final settings = await _settingsService.getCompanySettings(companyId);
    final roundingPolicy =
        _mapRoundingRule(_settingsService.teamTimeRoundingRule(settings));

    final anchor = await getCycleAnchor(companyId);
    final overtimeThreshold =
        (anchor?['overtimeThresholdHours'] as num?)?.toDouble() ?? 40.0;

    final normalizedStart = _startOfDay(startDate);
    final normalizedEnd = _endOfDay(endDate);

    // Employee names, including archived — needed for the summary
    // regardless of current membership status.
    final employeesSnapshot = await _employeesRef(companyId).get();
    final namesByEmployeeId = <String, String>{};
    for (final doc in employeesSnapshot.docs) {
      final e = EmployeeModel.fromSnapshot(doc);
      namesByEmployeeId[e.employeeId] = e.fullName;
    }

    final membershipsSnapshot = await _membershipsRef(companyId).get();
    final archivedIds = membershipsSnapshot.docs
        .where((d) => MembershipModel.fromSnapshot(d).isArchived)
        .map((d) => d.id)
        .toSet();

    final entriesSnapshot = await _timeEntriesRef(companyId)
        .where(FSFields.clockInAt,
            isGreaterThanOrEqualTo: Timestamp.fromDate(normalizedStart))
        .where(FSFields.clockInAt,
            isLessThanOrEqualTo: Timestamp.fromDate(normalizedEnd))
        .get();

    final entriesByEmployee = <String, List<TimeEntryModel>>{};
    for (final doc in entriesSnapshot.docs) {
      final entry = TimeEntryModel.fromSnapshot(doc);
      entriesByEmployee.putIfAbsent(entry.employeeId, () => []).add(entry);
    }

    final timeOffSnapshot = await _timeOffRef(companyId)
        .where(FSFields.status, isEqualTo: FSTimeOffStatus.approved)
        .get();
    final approvedTimeOff = timeOffSnapshot.docs
        .map((d) => TimeOffRequestModel.fromSnapshot(d))
        .where((r) =>
            r.startDate.isBefore(normalizedEnd) &&
            r.endDate.isAfter(normalizedStart.subtract(const Duration(days: 1))))
        .toList();

    final rows = <PayrollSummaryRow>[];

    for (final employeeId in entriesByEmployee.keys) {
      final entries = entriesByEmployee[employeeId]!;
      final dailyHours = <DateTime, double>{};
      // Keyed by the Monday that starts each calendar week, same
      // grouping buildDetailedTimesheets already uses — overtime has
      // to be judged per week, not against the pay period as a whole.
      final hoursByWeekStart = <DateTime, double>{};
      int editedCount = 0;
      int missingClockOutCount = 0;

      for (final entry in entries) {
        if (entry.isEdited) editedCount++;
        if (entry.isActive) {
          missingClockOutCount++;
          continue; // no completed duration to count yet
        }
        // payableDuration, not roundedDuration — nets out unpaid break
        // time so payroll totals reflect what's actually owed, not the
        // raw punched span. Paid breaks are intentionally left in.
        final duration = entry.payableDuration(roundingPolicy);
        if (duration == null) continue;

        final hours = duration.inMinutes / 60.0;

        final day = _startOfDay(entry.clockInAt);
        dailyHours[day] = (dailyHours[day] ?? 0) + hours;

        final weekday = day.weekday; // 1 = Monday .. 7 = Sunday
        final weekStart = day.subtract(Duration(days: weekday - 1));
        hoursByWeekStart[weekStart] = (hoursByWeekStart[weekStart] ?? 0) + hours;
      }

      // Overtime is a per-week threshold, not a per-pay-period one —
      // comparing the whole period's total against a single threshold
      // meant a biweekly period with exactly 40 hours in each of its
      // two weeks (80 total, correctly 0 overtime) came out as 40
      // regular + 40 overtime. Summing each week's own split fixes
      // weekly cycles too (they're just one bucket) without a special
      // case, and feeds directly into the CSV/printable payroll export.
      double regularHours = 0;
      double overtimeHours = 0;
      for (final weekHours in hoursByWeekStart.values) {
        if (weekHours > overtimeThreshold) {
          regularHours += overtimeThreshold;
          overtimeHours += weekHours - overtimeThreshold;
        } else {
          regularHours += weekHours;
        }
      }

      double paidLeave = 0;
      double unpaidLeave = 0;
      for (final request in approvedTimeOff) {
        if (request.employeeId != employeeId) continue;
        final hours = _proratedTimeOffHours(
          request: request,
          periodStart: normalizedStart,
          periodEnd: normalizedEnd,
        );
        if (request.leaveTypeId == StandardLeaveTypeIds.unpaid) {
          unpaidLeave += hours;
        } else {
          paidLeave += hours;
        }
      }

      rows.add(PayrollSummaryRow(
        employeeId: employeeId,
        employeeName: namesByEmployeeId[employeeId] ?? 'Unknown Employee',
        isArchived: archivedIds.contains(employeeId),
        dailyHours: dailyHours,
        regularHours: regularHours,
        overtimeHours: overtimeHours,
        paidLeaveHours: paidLeave,
        unpaidLeaveHours: unpaidLeave,
        editedEntryCount: editedCount,
        missingClockOutCount: missingClockOutCount,
      ));
    }

    rows.sort((a, b) => a.employeeName.compareTo(b.employeeName));
    return rows;
  }

  /// Builds the detailed, punch-level timesheet data behind the
  /// printable report — the same underlying entries as
  /// buildPayrollSummary, but preserving actual clock-in/out times
  /// grouped into weeks, rather than collapsing to per-day totals.
  /// Only entries with a completed clock-out are included in a day's
  /// punch list; an open (still clocked in) entry is surfaced via
  /// isMissingClockOut on that day instead of a duration.
  Future<List<DetailedTimesheet>> buildDetailedTimesheets({
    required String companyId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final settings = await _settingsService.getCompanySettings(companyId);
    final roundingPolicy =
        _mapRoundingRule(_settingsService.teamTimeRoundingRule(settings));

    final normalizedStart = _startOfDay(startDate);
    final normalizedEnd = _endOfDay(endDate);

    final employeesSnapshot = await _employeesRef(companyId).get();
    final namesByEmployeeId = <String, String>{};
    for (final doc in employeesSnapshot.docs) {
      final e = EmployeeModel.fromSnapshot(doc);
      namesByEmployeeId[e.employeeId] = e.fullName;
    }

    final membershipsSnapshot = await _membershipsRef(companyId).get();
    final archivedIds = membershipsSnapshot.docs
        .where((d) => MembershipModel.fromSnapshot(d).isArchived)
        .map((d) => d.id)
        .toSet();

    final entriesSnapshot = await _timeEntriesRef(companyId)
        .where(FSFields.clockInAt,
            isGreaterThanOrEqualTo: Timestamp.fromDate(normalizedStart))
        .where(FSFields.clockInAt,
            isLessThanOrEqualTo: Timestamp.fromDate(normalizedEnd))
        .get();

    final entriesByEmployee = <String, List<TimeEntryModel>>{};
    for (final doc in entriesSnapshot.docs) {
      final entry = TimeEntryModel.fromSnapshot(doc);
      entriesByEmployee.putIfAbsent(entry.employeeId, () => []).add(entry);
    }

    final timesheets = <DetailedTimesheet>[];

    for (final employeeId in entriesByEmployee.keys) {
      final entries = entriesByEmployee[employeeId]!
        ..sort((a, b) => a.clockInAt.compareTo(b.clockInAt));

      // Group punches by the Monday that starts their week, so a
      // biweekly period naturally splits into two WeekTimesheets.
      final punchesByWeekStart = <DateTime, List<DailyPunch>>{};

      for (final entry in entries) {
        final day = _startOfDay(entry.clockInAt);
        final weekday = day.weekday; // 1 = Monday .. 7 = Sunday
        final weekStart = day.subtract(Duration(days: weekday - 1));

        double hours = 0;
        if (!entry.isActive) {
          // payableDuration here too, so the printable timesheet's
          // hours match what buildPayrollSummary reports for the same
          // period instead of silently disagreeing by any unpaid
          // break time taken during the day.
          final duration = entry.payableDuration(roundingPolicy);
          if (duration != null) hours = duration.inMinutes / 60.0;
        }

        punchesByWeekStart.putIfAbsent(weekStart, () => []).add(DailyPunch(
              date: day,
              clockInAt: entry.clockInAt,
              clockOutAt: entry.clockOutAt,
              hours: hours,
              isEdited: entry.isEdited,
              isMissingClockOut: entry.isActive,
            ));
      }

      final sortedWeekStarts = punchesByWeekStart.keys.toList()..sort();
      final weeks = <WeekTimesheet>[];
      double periodTotal = 0;

      for (final weekStart in sortedWeekStarts) {
        final punches = punchesByWeekStart[weekStart]!..sort((a, b) => a.date.compareTo(b.date));
        final weekTotal = punches.fold<double>(0, (sum, p) => sum + p.hours);
        periodTotal += weekTotal;
        weeks.add(WeekTimesheet(weekStart: weekStart, punches: punches, totalHours: weekTotal));
      }

      timesheets.add(DetailedTimesheet(
        employeeId: employeeId,
        employeeName: namesByEmployeeId[employeeId] ?? 'Unknown Employee',
        isArchived: archivedIds.contains(employeeId),
        weeks: weeks,
        periodTotalHours: periodTotal,
      ));
    }

    timesheets.sort((a, b) => a.employeeName.compareTo(b.employeeName));
    return timesheets;
  }

  // --- Pay period lock / unlock / delete ---

  Future<List<PayPeriodModel>> getPayPeriods(String companyId) async {
    final snapshot =
        await _payPeriodsRef(companyId).orderBy(FSFields.startDate, descending: true).get();
    return snapshot.docs.map((d) => PayPeriodModel.fromSnapshot(d)).toList();
  }

  Stream<List<PayPeriodModel>> watchPayPeriods(String companyId) {
    return _payPeriodsRef(companyId)
        .orderBy(FSFields.startDate, descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => PayPeriodModel.fromSnapshot(d)).toList());
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _entriesInRange({
    required String companyId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final snapshot = await _timeEntriesRef(companyId)
        .where(FSFields.clockInAt,
            isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(startDate)))
        .where(FSFields.clockInAt,
            isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(endDate)))
        .get();
    return snapshot.docs;
  }

  /// Locks a pay period: marks every time entry within the range as
  /// locked (blocking further edits per Section 8/9), and writes an
  /// audit log entry for the lock action itself. Batched at 500 writes
  /// per Firestore's limit.
  Future<void> lockPayPeriod({
    required String companyId,
    required String actingUserId,
    required DateTime startDate,
    required DateTime endDate,
    String? name,
  }) async {
    await _requireOwnerAndPayPeriodsEnabled(companyId: companyId, actingUserId: actingUserId);

    final payPeriodId = payPeriodIdFromDates(startDate, endDate);
    final payPeriodRef = _payPeriodsRef(companyId).doc(payPeriodId);
    final existingDoc = await payPeriodRef.get();

    if (existingDoc.exists &&
        PayPeriodModel.fromSnapshot(existingDoc).isLocked) {
      throw Exception('This pay period is already locked.');
    }

    final entries = await _entriesInRange(
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
    );

    const chunkSize = 500;
    for (var i = 0; i < entries.length; i += chunkSize) {
      final batch = _firestore.batch();
      for (final entry in entries.skip(i).take(chunkSize)) {
        batch.update(entry.reference, {
          'payPeriodId': payPeriodId,
          'isLocked': true,
          FSFields.updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    final periodLabel = name?.trim().isNotEmpty == true
        ? name!.trim()
        : defaultPeriodName(startDate, endDate);

    await payPeriodRef.set({
      FSFields.companyId: companyId,
      'name': periodLabel,
      FSFields.startDate: Timestamp.fromDate(_startOfDay(startDate)),
      FSFields.endDate: Timestamp.fromDate(_endOfDay(endDate)),
      'cycleType':
          existingDoc.data()?['cycleType'] ?? (await _settingsService.getCompanySettings(companyId)).payPeriodType,
      'periodLengthDays':
          existingDoc.data()?['periodLengthDays'] ?? endDate.difference(startDate).inDays + 1,
      FSFields.status: FSPayPeriodStatus.locked,
      'entryCount': entries.length,
      'lockedAt': FieldValue.serverTimestamp(),
      'lockedByUserId': actingUserId,
      'unlockedAt': null,
      'unlockedByUserId': null,
      FSFields.createdAt: existingDoc.data()?[FSFields.createdAt] ?? FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // One audit entry for the lock action itself (previously this wrote
    // one raw doc per time entry to a DIFFERENT collection —
    // FSCompanySub.auditLogs — than the one the company's actual Audit
    // Log screen reads from (FSCompanySub.auditLog, via
    // CompanyAuditLogService). That meant every pay period lock/unlock
    // was invisible on the Audit Log screen, and it wrote up to
    // hundreds of near-duplicate per-entry docs for one action. Routed
    // through the shared service now, same as employee/job/company
    // actions, so it shows up consistently and doesn't block the lock
    // itself if the log write fails.
    try {
      final actorName = await _fullNameForUser(actingUserId) ?? actingUserId;
      await _auditLogService.record(
        companyId: companyId,
        actorUserId: actingUserId,
        actorName: actorName,
        action: 'payPeriodLocked',
        targetType: 'payPeriod',
        targetId: payPeriodId,
        targetName: periodLabel,
        newValue: '${entries.length} time entries',
      );
    } catch (_) {
      // The lock itself already succeeded above.
    }
  }

  Future<void> unlockPayPeriod({
    required String companyId,
    required String actingUserId,
    required String payPeriodId,
  }) async {
    await _requireOwnerAndPayPeriodsEnabled(companyId: companyId, actingUserId: actingUserId);

    final payPeriodRef = _payPeriodsRef(companyId).doc(payPeriodId);
    final doc = await payPeriodRef.get();
    if (!doc.exists) throw Exception('Pay period was not found.');
    final payPeriod = PayPeriodModel.fromSnapshot(doc);
    if (!payPeriod.isLocked) {
      throw Exception('Only locked pay periods can be unlocked.');
    }

    final entriesSnapshot = await _timeEntriesRef(companyId)
        .where('payPeriodId', isEqualTo: payPeriodId)
        .get();

    const chunkSize = 500;
    final docs = entriesSnapshot.docs;
    for (var i = 0; i < docs.length; i += chunkSize) {
      final batch = _firestore.batch();
      for (final entry in docs.skip(i).take(chunkSize)) {
        batch.update(entry.reference, {
          'isLocked': false,
          FSFields.updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    await payPeriodRef.update({
      FSFields.status: FSPayPeriodStatus.open,
      'unlockedAt': FieldValue.serverTimestamp(),
      'unlockedByUserId': actingUserId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    try {
      final actorName = await _fullNameForUser(actingUserId) ?? actingUserId;
      await _auditLogService.record(
        companyId: companyId,
        actorUserId: actingUserId,
        actorName: actorName,
        action: 'payPeriodUnlocked',
        targetType: 'payPeriod',
        targetId: payPeriodId,
        targetName: payPeriod.name,
      );
    } catch (_) {
      // The unlock itself already succeeded above.
    }
  }

  Future<void> deletePayPeriod({
    required String companyId,
    required String actingUserId,
    required String payPeriodId,
  }) async {
    await _requireOwnerAndPayPeriodsEnabled(companyId: companyId, actingUserId: actingUserId);

    final payPeriodRef = _payPeriodsRef(companyId).doc(payPeriodId);
    final doc = await payPeriodRef.get();
    if (!doc.exists) throw Exception('Pay period was not found.');
    final payPeriod = PayPeriodModel.fromSnapshot(doc);
    if (payPeriod.isLocked) {
      throw Exception('Unlock this pay period before deleting it.');
    }

    await payPeriodRef.delete();
  }

  // --- Export ---

  String _csvEscape(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.contains(',') || text.contains('"') || text.contains('\n')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  /// Builds detailed timesheets for an arbitrary date range — used for
  /// both locked historical periods AND the current, still-open period.
  /// Previously this only accepted a payPeriodId and required a stored,
  /// locked PayPeriodModel doc to exist, which meant the current pay
  /// period (which has no stored doc until it's locked) could never be
  /// previewed. Callers already have the date range in hand (either from
  /// a stored PayPeriodModel or from calculateCurrentPayPeriod), so
  /// there's no need to require the doc — this just re-runs the same
  /// math the eventual lock will use. Owner-only, since this exposes
  /// every employee's detailed clock in/out times, not just totals.
  Future<List<DetailedTimesheet>> buildDetailedTimesheetsForPeriod({
    required String companyId,
    required String actingUserId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _requireOwnerAndPayPeriodsEnabled(companyId: companyId, actingUserId: actingUserId);

    return buildDetailedTimesheets(
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// CSV export for an arbitrary date range. No longer restricted to
  /// locked periods — an open period's numbers can still change after
  /// the fact, but that's the acknowledged tradeoff of exporting early
  /// rather than a reason to block it outright; the export is simply a
  /// snapshot as of the moment it's copied.
  Future<String> exportPayPeriodCsv({
    required String companyId,
    required String actingUserId,
    required DateTime startDate,
    required DateTime endDate,
    required String periodName,
  }) async {
    await _requireOwnerAndPayPeriodsEnabled(companyId: companyId, actingUserId: actingUserId);

    final rows = await buildPayrollSummary(
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
    );

    final csvRows = <List<dynamic>>[
      [
        'Employee', 'Regular Hours', 'Overtime Hours', 'Paid Leave Hours',
        'Unpaid Leave Hours', 'Total Hours', 'Edited Entries',
        'Missing Clock-Outs', 'Pay Period', 'Archived Employee',
      ],
    ];

    for (final row in rows) {
      csvRows.add([
        row.employeeName,
        row.regularHours.toStringAsFixed(2),
        row.overtimeHours.toStringAsFixed(2),
        row.paidLeaveHours.toStringAsFixed(2),
        row.unpaidLeaveHours.toStringAsFixed(2),
        row.totalHours.toStringAsFixed(2),
        row.editedEntryCount,
        row.missingClockOutCount,
        periodName,
        row.isArchived ? 'Yes' : 'No',
      ]);
    }

    return csvRows.map((r) => r.map(_csvEscape).join(',')).join('\n');
  }

  /// Plain-text printable/clipboard summary for an arbitrary date range
  /// — same "no longer locked-only" reasoning as exportPayPeriodCsv.
  Future<String> exportPrintableSummary({
    required String companyId,
    required String actingUserId,
    required DateTime startDate,
    required DateTime endDate,
    required String periodName,
  }) async {
    await _requireOwnerAndPayPeriodsEnabled(companyId: companyId, actingUserId: actingUserId);

    final rows = await buildPayrollSummary(
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
    );

    final buffer = StringBuffer();
    buffer.writeln('PAYROLL SUMMARY');
    buffer.writeln('Pay Period: $periodName');
    buffer.writeln('');
    buffer.writeln('Total Employees: ${rows.length}');
    buffer.writeln(
        'Total Hours: ${rows.fold<double>(0, (sum, r) => sum + r.totalHours).toStringAsFixed(2)}');
    buffer.writeln('');
    buffer.writeln('EMPLOYEE TOTALS');
    for (final row in rows) {
      final flags = <String>[
        if (row.editedEntryCount > 0) '${row.editedEntryCount} edited',
        if (row.missingClockOutCount > 0) '${row.missingClockOutCount} missing clock-out',
        if (row.isArchived) 'archived',
      ];
      final flagText = flags.isEmpty ? '' : ' (${flags.join(', ')})';
      buffer.writeln(
          '${row.employeeName} — ${row.regularHours.toStringAsFixed(2)} reg, ${row.overtimeHours.toStringAsFixed(2)} OT, ${row.paidLeaveHours.toStringAsFixed(2)} paid leave$flagText');
    }

    return buffer.toString().trim();
  }
}
