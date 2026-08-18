import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/job_model.dart';
import '../Models/time_entry_model.dart';
import '../Services/company_settings_service.dart';
import '../theme/app_theme.dart';

class PayrollSummaryScreen extends StatelessWidget {
  final String companyId;
  final String payPeriodName;
  final String startDate;
  final String endDate;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final bool isLocked;

  const PayrollSummaryScreen({
    super.key,
    required this.companyId,
    required this.payPeriodName,
    required this.startDate,
    required this.endDate,
    required this.startDateTime,
    required this.endDateTime,
    required this.isLocked,
  });

  String _formatTime(DateTime? date) {
    if (date == null) return 'Missing';
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

  String _hours(int minutes) => (minutes / 60).toStringAsFixed(2);

  DateTime _startOfDay(DateTime v) => DateTime(v.year, v.month, v.day);
  DateTime _endOfDay(DateTime v) =>
      DateTime(v.year, v.month, v.day, 23, 59, 59, 999);

  /// Maps company_settings_service's free-text rounding rule to the
  /// FSClockRounding constant TimeEntryModel.applyRounding expects —
  /// same mapping used in pay_period_service.dart, kept local here
  /// since this file doesn't otherwise depend on that service.
  String _mapRoundingRule(String raw) {
    switch (raw) {
      case '5 minutes':
        return FSClockRounding.nearest5;
      case '10 minutes':
        return FSClockRounding.nearest10;
      case '15 minutes':
        return FSClockRounding.nearest15;
      default:
        return FSClockRounding.none;
    }
  }

  Future<_PayrollSummaryData> _loadSummaryData() async {
    final firestore = FirebaseFirestore.instance;
    final settingsService = CompanySettingsService();

    final settings = await settingsService.getCompanySettings(companyId);
    final roundingPolicy = _mapRoundingRule(settingsService.teamTimeRoundingRule(settings));

    // Queried by clockInAt date range rather than the stamped
    // payPeriodId field — that field is only written onto entries when
    // a period is locked (see PayPeriodService.lockPayPeriod), so an
    // open/current period's entries wouldn't have it yet. Matches the
    // exact range PayPeriodService.buildPayrollSummary uses, so a
    // preview here always agrees with what locking would produce.
    final entriesSnapshot = await firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.timeEntries)
        .where(FSFields.clockInAt,
            isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(startDateTime)))
        .where(FSFields.clockInAt,
            isLessThanOrEqualTo: Timestamp.fromDate(_endOfDay(endDateTime)))
        .get();

    final entries = entriesSnapshot.docs.map((d) => TimeEntryModel.fromSnapshot(d)).toList();

    // Resolve employee names — entries only carry employeeId.
    final employeeIds = entries.map((e) => e.employeeId).toSet().toList();
    final employeesById = <String, EmployeeModel>{};
    for (final chunk in _chunked(employeeIds, 30)) {
      if (chunk.isEmpty) continue;
      final snap = await firestore
          .collection(FSCollections.companies)
          .doc(companyId)
          .collection(FSCompanySub.employees)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        employeesById[doc.id] = EmployeeModel.fromSnapshot(doc);
      }
    }

    // Resolve job names — entries only carry jobId.
    final jobIds = entries.map((e) => e.jobId).whereType<String>().toSet().toList();
    final jobsById = <String, JobModel>{};
    for (final chunk in _chunked(jobIds, 30)) {
      if (chunk.isEmpty) continue;
      final snap = await firestore
          .collection(FSCollections.companies)
          .doc(companyId)
          .collection(FSCompanySub.jobs)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        jobsById[doc.id] = JobModel.fromSnapshot(doc);
      }
    }

    // Resolve crew names — entries only carry crewId.
    final crewIds = entries.map((e) => e.crewId).whereType<String>().toSet().toList();
    final crewsById = <String, CrewModel>{};
    for (final chunk in _chunked(crewIds, 30)) {
      if (chunk.isEmpty) continue;
      final snap = await firestore
          .collection(FSCollections.companies)
          .doc(companyId)
          .collection(FSCompanySub.crews)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        crewsById[doc.id] = CrewModel.fromSnapshot(doc);
      }
    }

    // Pending corrections tied to this period's entries — correction
    // requests reference timeEntryId, not payPeriodId directly, so this
    // joins through the entry IDs actually in this period.
    final entryIds = entries.map((e) => e.timeEntryId).toList();
    int pendingCorrections = 0;
    for (final chunk in _chunked(entryIds, 30)) {
      if (chunk.isEmpty) continue;
      final snap = await firestore
          .collection(FSCollections.companies)
          .doc(companyId)
          .collection(FSCompanySub.correctionRequests)
          .where(FSFields.timeEntryId, whereIn: chunk)
          .where(FSFields.status, isEqualTo: FSCorrectionStatus.pending)
          .get();
      pendingCorrections += snap.docs.length;
    }

    final summaries = <String, _EmployeePayrollSummary>{};

    for (final entry in entries) {
      final employee = employeesById[entry.employeeId];
      final employeeName = employee?.fullName.trim().isNotEmpty == true
          ? employee!.fullName
          : 'Unknown Worker';

      summaries.putIfAbsent(
        entry.employeeId,
        () => _EmployeePayrollSummary(employeeName: employeeName),
      );

      // payableDuration, not roundedDuration — nets out unpaid break
      // time so this per-entry breakdown adds up to the same totals
      // buildPayrollSummary reports for the period, rather than
      // silently running higher by any unpaid break time taken.
      final roundedMinutes = entry.payableDuration(roundingPolicy)?.inMinutes ?? 0;
      final job = entry.jobId != null ? jobsById[entry.jobId] : null;
      final crew = entry.crewId != null ? crewsById[entry.crewId] : null;

      summaries[entry.employeeId]!.addEntry(
        _PayrollEntry(
          entryId: entry.timeEntryId,
          date: _formatDate(entry.clockInAt),
          clockIn: _formatTime(entry.clockInAt),
          clockOut: _formatTime(entry.clockOutAt),
          totalMinutes: roundedMinutes,
          jobName: job?.title ?? 'No linked job',
          crewName: crew?.crewName ?? 'No linked crew',
          isEdited: entry.isEdited,
          isMissingClockOut: entry.isActive,
        ),
      );
    }

    final sortedSummaries = summaries.values.toList()
      ..sort((a, b) => a.employeeName.toLowerCase().compareTo(b.employeeName.toLowerCase()));

    return _PayrollSummaryData(
      summaries: sortedSummaries,
      totalShifts: entries.length,
      pendingCorrections: pendingCorrections,
    );
  }

  List<List<T>> _chunked<T>(List<T> items, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      chunks.add(items.sublist(i, i + size > items.length ? items.length : i + size));
    }
    return chunks.isEmpty ? [<T>[]] : chunks;
  }

  String _buildCopyText(_PayrollSummaryData data, int totalMinutes) {
    final buffer = StringBuffer();

    buffer.writeln('PAYROLL SUMMARY');
    buffer.writeln('Pay Period: $payPeriodName');
    buffer.writeln('Dates: $startDate - $endDate');
    buffer.writeln('');
    buffer.writeln('Total Employees: ${data.summaries.length}');
    buffer.writeln('Total Hours: ${_hours(totalMinutes)}');
    buffer.writeln('Total Shifts: ${data.totalShifts}');
    buffer.writeln('Edited Entries: ${data.summaries.fold(0, (s, e) => s + e.editedEntries)}');
    buffer.writeln(
        'Missing Clock-Outs: ${data.summaries.fold(0, (s, e) => s + e.missingClockOuts)}');
    buffer.writeln('Pending Corrections: ${data.pendingCorrections}');
    buffer.writeln('');

    for (final summary in data.summaries) {
      buffer.writeln(summary.employeeName);
      buffer.writeln('Total Hours: ${_hours(summary.totalMinutes)}');
      buffer.writeln('Shifts: ${summary.entries.length}');

      final jobs = summary.jobs.toList()..sort();
      if (jobs.isNotEmpty) buffer.writeln('Jobs: ${jobs.join(', ')}');

      buffer.writeln('');

      for (final entry in summary.entries) {
        buffer.writeln(
          '- ${entry.date}: ${entry.clockIn} - ${entry.clockOut}, ${_hours(entry.totalMinutes)} hrs, ${entry.jobName}',
        );
      }

      buffer.writeln('');
    }

    return buffer.toString().trim();
  }

  Future<void> _copySummary(BuildContext context, _PayrollSummaryData data, int totalMinutes) async {
    final text = _buildCopyText(data, totalMinutes);
    await Clipboard.setData(ClipboardData(text: text));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payroll summary copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Payroll Summary',
          style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<_PayrollSummaryData>(
          future: _loadSummaryData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.mutedText),
                  ),
                ),
              );
            }

            final data = snapshot.data ??
                const _PayrollSummaryData(summaries: [], totalShifts: 0, pendingCorrections: 0);

            final totalMinutes =
                data.summaries.fold<int>(0, (sum, s) => sum + s.totalMinutes);
            final editedEntries =
                data.summaries.fold<int>(0, (sum, s) => sum + s.editedEntries);
            final missingClockOuts =
                data.summaries.fold<int>(0, (sum, s) => sum + s.missingClockOuts);

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _PayrollHeaderCard(
                  payPeriodName: payPeriodName,
                  startDate: startDate,
                  endDate: endDate,
                  isLocked: isLocked,
                  totalEmployees: data.summaries.length,
                  totalHours: _hours(totalMinutes),
                  totalShifts: data.totalShifts,
                  editedEntries: editedEntries,
                  missingClockOuts: missingClockOuts,
                  pendingCorrections: data.pendingCorrections,
                  onCopy: () => _copySummary(context, data, totalMinutes),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Employees',
                  style: TextStyle(
                    color: AppTheme.darkText,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (data.summaries.isEmpty)
                  const _EmptyPayrollSummaryCard()
                else
                  ...data.summaries.map(
                    (summary) => _EmployeePayrollCard(summary: summary, hoursFormatter: _hours),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PayrollSummaryData {
  final List<_EmployeePayrollSummary> summaries;
  final int totalShifts;
  final int pendingCorrections;

  const _PayrollSummaryData({
    required this.summaries,
    required this.totalShifts,
    required this.pendingCorrections,
  });
}

class _PayrollHeaderCard extends StatelessWidget {
  final String payPeriodName;
  final String startDate;
  final String endDate;
  final bool isLocked;
  final int totalEmployees;
  final String totalHours;
  final int totalShifts;
  final int editedEntries;
  final int missingClockOuts;
  final int pendingCorrections;
  final VoidCallback onCopy;

  const _PayrollHeaderCard({
    required this.payPeriodName,
    required this.startDate,
    required this.endDate,
    required this.isLocked,
    required this.totalEmployees,
    required this.totalHours,
    required this.totalShifts,
    required this.editedEntries,
    required this.missingClockOuts,
    required this.pendingCorrections,
    required this.onCopy,
  });

  bool get hasWarnings => editedEntries > 0 || missingClockOuts > 0 || pendingCorrections > 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isLocked ? 'Locked Pay Period' : 'Open Pay Period',
              style: const TextStyle(color: AppTheme.darkText, fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(payPeriodName, style: const TextStyle(color: AppTheme.mutedText, fontSize: 14)),
            const SizedBox(height: 4),
            Text('$startDate - $endDate', style: const TextStyle(color: AppTheme.mutedText, fontSize: 14)),
            const SizedBox(height: 16),
            _SummaryMetricRow(label: 'Employees', value: totalEmployees.toString()),
            _SummaryMetricRow(label: 'Total Hours', value: totalHours),
            _SummaryMetricRow(label: 'Total Shifts', value: totalShifts.toString()),
            _SummaryMetricRow(label: 'Edited Entries', value: editedEntries.toString()),
            _SummaryMetricRow(label: 'Missing Clock-Outs', value: missingClockOuts.toString()),
            _SummaryMetricRow(label: 'Pending Corrections', value: pendingCorrections.toString()),
            if (!isLocked) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: const Text(
                  'This period is still open — numbers may change before it\'s locked.',
                  style: TextStyle(color: AppTheme.blue, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            if (hasWarnings) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Text(
                  'Review warnings before running payroll.',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy Payroll Summary'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryMetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 14)),
          ),
          Text(
            value,
            style: const TextStyle(color: AppTheme.darkText, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _EmployeePayrollCard extends StatelessWidget {
  final _EmployeePayrollSummary summary;
  final String Function(int minutes) hoursFormatter;

  const _EmployeePayrollCard({required this.summary, required this.hoursFormatter});

  @override
  Widget build(BuildContext context) {
    final jobs = summary.jobs.toList()..sort();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        title: Text(
          summary.employeeName,
          style: const TextStyle(color: AppTheme.darkText, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${hoursFormatter(summary.totalMinutes)} hrs • ${summary.entries.length} shifts',
          style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
        ),
        children: [
          _SummaryMetricRow(label: 'Total Hours', value: hoursFormatter(summary.totalMinutes)),
          _SummaryMetricRow(label: 'Shifts', value: summary.entries.length.toString()),
          _SummaryMetricRow(label: 'Edited Entries', value: summary.editedEntries.toString()),
          _SummaryMetricRow(label: 'Missing Clock-Outs', value: summary.missingClockOuts.toString()),
          if (jobs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Jobs: ${jobs.join(', ')}',
                  style: const TextStyle(color: AppTheme.mutedText, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 14),
          ...summary.entries.map(
            (entry) => _PayrollEntryRow(entry: entry, hoursFormatter: hoursFormatter),
          ),
        ],
      ),
    );
  }
}

class _PayrollEntryRow extends StatelessWidget {
  final _PayrollEntry entry;
  final String Function(int minutes) hoursFormatter;

  const _PayrollEntryRow({required this.entry, required this.hoursFormatter});

  @override
  Widget build(BuildContext context) {
    final warningText = entry.isMissingClockOut
        ? 'Missing clock-out'
        : entry.isEdited
            ? 'Edited'
            : '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.date, style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('${entry.clockIn} - ${entry.clockOut}', style: const TextStyle(color: AppTheme.mutedText)),
          const SizedBox(height: 5),
          Text('${hoursFormatter(entry.totalMinutes)} hrs • ${entry.jobName}',
              style: const TextStyle(color: AppTheme.mutedText)),
          if (entry.crewName.isNotEmpty && entry.crewName != 'No linked crew')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(entry.crewName, style: const TextStyle(color: AppTheme.mutedText)),
            ),
          if (warningText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                warningText,
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyPayrollSummaryCard extends StatelessWidget {
  const _EmptyPayrollSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Text(
          'No time entries found for this pay period.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.mutedText),
        ),
      ),
    );
  }
}

class _EmployeePayrollSummary {
  final String employeeName;
  final List<_PayrollEntry> entries = [];

  _EmployeePayrollSummary({required this.employeeName});

  int get totalMinutes => entries.fold(0, (total, entry) => total + entry.totalMinutes);

  int get editedEntries => entries.where((entry) => entry.isEdited).length;

  int get missingClockOuts => entries.where((entry) => entry.isMissingClockOut).length;

  Set<String> get jobs => entries
      .map((entry) => entry.jobName)
      .where((job) => job.trim().isNotEmpty && job != 'No linked job')
      .toSet();

  void addEntry(_PayrollEntry entry) {
    entries.add(entry);
    entries.sort((a, b) => a.date.compareTo(b.date));
  }
}

class _PayrollEntry {
  final String entryId;
  final String date;
  final String clockIn;
  final String clockOut;
  final int totalMinutes;
  final String jobName;
  final String crewName;
  final bool isEdited;
  final bool isMissingClockOut;

  const _PayrollEntry({
    required this.entryId,
    required this.date,
    required this.clockIn,
    required this.clockOut,
    required this.totalMinutes,
    required this.jobName,
    required this.crewName,
    required this.isEdited,
    required this.isMissingClockOut,
  });
}
