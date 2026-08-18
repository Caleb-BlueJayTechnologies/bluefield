import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:printing/printing.dart';
import '../Models/pay_period_model.dart';
import '../Services/company_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/pay_period_service.dart';
import '../Services/permission_service.dart';
import '../Services/time_entry_service.dart';
import '../Services/timesheet_pdf_generator.dart';
import '../theme/app_theme.dart';
import 'payroll_summary_screen.dart';

class PayPeriodsScreen extends StatefulWidget {
  const PayPeriodsScreen({super.key});

  @override
  State<PayPeriodsScreen> createState() => _PayPeriodsScreenState();
}

class _PayPeriodsScreenState extends State<PayPeriodsScreen> {
  final PayPeriodService _payPeriodService = PayPeriodService();
  final CompanyService _companyService = CompanyService();
  final CompanySettingsService _settingsService = CompanySettingsService();
  final TimeEntryService _timeEntryService = TimeEntryService();
  final PermissionService _permissionService = PermissionService();

  final TextEditingController _customDaysController = TextEditingController();
  final TextEditingController _overtimeThresholdController = TextEditingController();

  late Future<String> _companyFuture;
  late Future<String> _roleFuture;
  late Future<Map<String, dynamic>?> _currentPeriodFuture;

  String? _userId;
  String _selectedCycleType = 'biweekly';
  DateTime? _selectedFirstStartDate;
  bool _formInitialized = false;

  bool _isSavingSettings = false;
  bool _isChangingLock = false;
  bool _isDeleting = false;
  bool _isExporting = false;
  bool _isCopyingPrintable = false;

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _companyFuture = _timeEntryService.getCurrentCompanyId();
    _roleFuture = _permissionService.getCurrentUserRole();
    _currentPeriodFuture = _companyFuture
        .then((companyId) => _payPeriodService.calculateCurrentPayPeriod(companyId: companyId));
    _customDaysController.text = '14';
    _overtimeThresholdController.text = '40';
  }

  @override
  void dispose() {
    _customDaysController.dispose();
    _overtimeThresholdController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Unknown date';
    return '${value.month}/${value.day}/${value.year}';
  }

  Future<void> _initFormOnce(String companyId) async {
    if (_formInitialized) return;
    _formInitialized = true;

    final settings = await _settingsService.getCompanySettings(companyId);
    final anchor = await _payPeriodService.getCycleAnchor(companyId);

    if (!mounted) return;

    setState(() {
      _selectedCycleType = settings.payPeriodType;
      if (anchor != null) {
        final firstStart = anchor['firstPeriodStart'];
        if (firstStart != null) {
          _selectedFirstStartDate = (firstStart as dynamic).toDate();
        }
        final customDays = anchor['customPeriodLengthDays'];
        if (customDays != null) _customDaysController.text = customDays.toString();
        final overtime = anchor['overtimeThresholdHours'];
        if (overtime != null) _overtimeThresholdController.text = overtime.toString();
      }
    });
  }

  Future<void> _pickFirstStartDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedFirstStartDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (picked == null) return;

    setState(() {
      _selectedFirstStartDate = picked;
    });
  }

  void _refreshCurrentPeriod(String companyId) {
    setState(() {
      _currentPeriodFuture =
          _payPeriodService.calculateCurrentPayPeriod(companyId: companyId);
    });
  }

  Future<void> _savePayrollSettings(String companyId) async {
    final firstStart = _selectedFirstStartDate;
    final userId = _userId;

    if (firstStart == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose the first pay period start date.')),
      );
      return;
    }
    if (userId == null) return;

    final customDays = int.tryParse(_customDaysController.text.trim());
    final overtimeThreshold =
        double.tryParse(_overtimeThresholdController.text.trim()) ?? 40;

    if (_selectedCycleType == 'custom' && (customDays == null || customDays < 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid custom day count.')),
      );
      return;
    }

    setState(() {
      _isSavingSettings = true;
    });

    try {
      // Cycle type lives on company settings (payroll.payPeriodType);
      // the anchor date/custom length/overtime threshold live in their
      // own small doc via PayPeriodService — see pay_period_service.dart
      // for why these aren't duplicated in one place.
      final settings = await _settingsService.getCompanySettings(companyId);
      final payroll = Map<String, dynamic>.from(settings.payroll);
      payroll['payPeriodType'] = _selectedCycleType;
      final updated = settings.copyWith(payroll: payroll);
      await _settingsService.saveCompanySettings(updated);

      await _payPeriodService.saveCycleAnchor(
        companyId: companyId,
        actingUserId: userId,
        firstPeriodStart: firstStart,
        customPeriodLengthDays: _selectedCycleType == 'custom' ? customDays : null,
        overtimeThresholdHours: overtimeThreshold,
      );

      _refreshCurrentPeriod(companyId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payroll schedule saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSettings = false;
        });
      }
    }
  }

  Future<void> _lockPeriod({
    required String companyId,
    required Map<String, dynamic> calculatedPeriod,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _isChangingLock = true;
    });

    try {
      await _payPeriodService.lockPayPeriod(
        companyId: companyId,
        actingUserId: userId,
        startDate: calculatedPeriod['startDate'] as DateTime,
        endDate: calculatedPeriod['endDate'] as DateTime,
        name: calculatedPeriod['name']?.toString(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pay period locked.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isChangingLock = false;
        });
      }
    }
  }

  Future<void> _unlockPeriod({
    required String companyId,
    required String payPeriodId,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _isChangingLock = true;
    });

    try {
      await _payPeriodService.unlockPayPeriod(
        companyId: companyId,
        actingUserId: userId,
        payPeriodId: payPeriodId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pay period unlocked.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isChangingLock = false;
        });
      }
    }
  }

  Future<void> _deletePeriod({
    required String companyId,
    required String payPeriodId,
    required String name,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Delete Pay Period?'),
              content: Text(
                'This will permanently delete "$name".\n\nTime entries will NOT be deleted.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await _payPeriodService.deletePayPeriod(
        companyId: companyId,
        actingUserId: userId,
        payPeriodId: payPeriodId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pay period deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Future<void> _exportPeriodCsv({
    required String companyId,
    required DateTime startDate,
    required DateTime endDate,
    required String name,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final csv = await _payPeriodService.exportPayPeriodCsv(
        companyId: companyId,
        actingUserId: userId,
        startDate: startDate,
        endDate: endDate,
        periodName: name,
      );

      await Clipboard.setData(ClipboardData(text: csv));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payroll CSV copied for $name.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _generateTimesheetPdf({
    required String companyId,
    required DateTime startDate,
    required DateTime endDate,
    required String name,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final timesheets = await _payPeriodService.buildDetailedTimesheetsForPeriod(
        companyId: companyId,
        actingUserId: userId,
        startDate: startDate,
        endDate: endDate,
      );

      final company = await _companyService.getCompany(companyId);

      final pdfBytes = await TimesheetPdfGenerator.generate(
        companyName: company?.companyName ?? 'Timesheet Report',
        payPeriodLabel: name,
        timesheets: timesheets,
      );

      if (!mounted) return;

      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: 'Timesheets - $name',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _copyPrintableSummary({
    required String companyId,
    required DateTime startDate,
    required DateTime endDate,
    required String name,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    setState(() {
      _isCopyingPrintable = true;
    });

    try {
      final summary = await _payPeriodService.exportPrintableSummary(
        companyId: companyId,
        actingUserId: userId,
        startDate: startDate,
        endDate: endDate,
        periodName: name,
      );

      await Clipboard.setData(ClipboardData(text: summary));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Printable payroll summary copied for $name. Paste it into Notes, Docs, Word, or email to print.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isCopyingPrintable = false;
        });
      }
    }
  }

  Future<void> _confirmLock({
    required String companyId,
    required Map<String, dynamic> calculatedPeriod,
  }) async {
    final name = calculatedPeriod['name']?.toString() ?? 'Current Pay Period';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lock Pay Period?'),
          content: Text(
            'This will lock all time entries inside "$name" and prevent direct editing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lock'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _lockPeriod(companyId: companyId, calculatedPeriod: calculatedPeriod);
    if (mounted) _refreshCurrentPeriod(companyId);
  }

  Future<void> _confirmUnlock({
    required String companyId,
    required String payPeriodId,
    required String name,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Unlock Pay Period?'),
          content: Text(
            'This will reopen "$name" and allow eligible time entries to be edited again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _unlockPeriod(companyId: companyId, payPeriodId: payPeriodId);
  }

  void _openPayrollSummary({
    required String companyId,
    required String payPeriodName,
    required DateTime startDate,
    required DateTime endDate,
    required bool isLocked,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PayrollSummaryScreen(
          companyId: companyId,
          payPeriodName: payPeriodName,
          startDate: _formatDate(startDate),
          endDate: _formatDate(endDate),
          startDateTime: startDate,
          endDateTime: endDate,
          isLocked: isLocked,
        ),
      ),
    );
  }

  bool get _isBusy => _isChangingLock || _isDeleting || _isExporting || _isCopyingPrintable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Pay Periods',
          style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _companyFuture,
          builder: (context, companySnapshot) {
            if (companySnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (companySnapshot.hasError ||
                companySnapshot.data == null ||
                companySnapshot.data!.isEmpty) {
              return Center(
                child: Text(
                  companySnapshot.error?.toString() ?? 'No company found.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              );
            }

            final companyId = companySnapshot.data!;

            return FutureBuilder<String>(
              future: _roleFuture,
              builder: (context, roleSnapshot) {
                if (roleSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final role = roleSnapshot.data ?? '';
                final canManage = _permissionService.canLockPayPeriods(role) &&
                    _permissionService.canUnlockPayPeriods(role);

                if (!canManage) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Only owners can manage pay periods.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.mutedText),
                      ),
                    ),
                  );
                }

                return FutureBuilder<void>(
                  future: _initFormOnce(companyId),
                  builder: (context, initSnapshot) {
                    return FutureBuilder<Map<String, dynamic>?>(
                      future: _currentPeriodFuture,
                      builder: (context, periodSnapshot) {
                        if (periodSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final calculatedPeriod = periodSnapshot.data;

                        return StreamBuilder<List<PayPeriodModel>>(
                          stream: _payPeriodService.watchPayPeriods(companyId),
                          builder: (context, periodsSnapshot) {
                            if (periodsSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final allPeriods = periodsSnapshot.data ?? [];
                            final currentPayPeriodId =
                                calculatedPeriod?['payPeriodId']?.toString();

                            PayPeriodModel? storedCurrent;
                            for (final p in allPeriods) {
                              if (p.payPeriodId == currentPayPeriodId) {
                                storedCurrent = p;
                                break;
                              }
                            }

                            final currentLocked = storedCurrent?.isLocked ?? false;

                            final historyPeriods = allPeriods
                                .where((p) => p.payPeriodId != currentPayPeriodId)
                                .toList();

                            return ListView(
                              padding: const EdgeInsets.all(18),
                              children: [
                                _PayrollSettingsCard(
                                  selectedCycleType: _selectedCycleType,
                                  firstStartDateText: _selectedFirstStartDate == null
                                      ? 'Choose first start date'
                                      : _formatDate(_selectedFirstStartDate),
                                  customDaysController: _customDaysController,
                                  isSaving: _isSavingSettings,
                                  onCycleChanged: (value) {
                                    setState(() {
                                      _selectedCycleType = value;
                                    });
                                  },
                                  onPickFirstStartDate: _pickFirstStartDate,
                                  onSave: () => _savePayrollSettings(companyId),
                                ),
                                const SizedBox(height: 18),
                                if (calculatedPeriod == null)
                                  const _NoCurrentPeriodCard()
                                else
                                  _CurrentPayPeriodCard(
                                    name: calculatedPeriod['name']?.toString() ??
                                        'Current Pay Period',
                                    startDate:
                                        _formatDate(calculatedPeriod['startDate'] as DateTime?),
                                    endDate:
                                        _formatDate(calculatedPeriod['endDate'] as DateTime?),
                                    status: currentLocked ? 'Locked' : 'Open',
                                    cycleType:
                                        calculatedPeriod['cycleType']?.toString() ?? 'biweekly',
                                    periodLengthDays:
                                        calculatedPeriod['periodLengthDays'] as int? ?? 14,
                                    isLocked: currentLocked,
                                    isBusy: _isBusy,
                                    onLock: () => _confirmLock(
                                      companyId: companyId,
                                      calculatedPeriod: calculatedPeriod,
                                    ),
                                    onUnlock: storedCurrent == null
                                        ? null
                                        : () => _confirmUnlock(
                                              companyId: companyId,
                                              payPeriodId: storedCurrent!.payPeriodId,
                                              name: calculatedPeriod['name']?.toString() ??
                                                  'Current Pay Period',
                                            ),
                                    // View/copy/export/PDF no longer require the
                                    // period to be locked — a manager may need
                                    // to pull numbers before the period ends
                                    // without wanting to lock (and freeze) it
                                    // yet. These are always available for the
                                    // current calculated period.
                                    onViewSummary: () => _openPayrollSummary(
                                      companyId: companyId,
                                      payPeriodName: calculatedPeriod['name']?.toString() ??
                                          'Current Pay Period',
                                      startDate: calculatedPeriod['startDate'] as DateTime,
                                      endDate: calculatedPeriod['endDate'] as DateTime,
                                      isLocked: currentLocked,
                                    ),
                                    onCopyPrintable: () => _copyPrintableSummary(
                                      companyId: companyId,
                                      startDate: calculatedPeriod['startDate'] as DateTime,
                                      endDate: calculatedPeriod['endDate'] as DateTime,
                                      name: calculatedPeriod['name']?.toString() ??
                                          'Current Pay Period',
                                    ),
                                    onExport: () => _exportPeriodCsv(
                                      companyId: companyId,
                                      startDate: calculatedPeriod['startDate'] as DateTime,
                                      endDate: calculatedPeriod['endDate'] as DateTime,
                                      name: calculatedPeriod['name']?.toString() ??
                                          'Current Pay Period',
                                    ),
                                    onGeneratePdf: () => _generateTimesheetPdf(
                                      companyId: companyId,
                                      startDate: calculatedPeriod['startDate'] as DateTime,
                                      endDate: calculatedPeriod['endDate'] as DateTime,
                                      name: calculatedPeriod['name']?.toString() ??
                                          'Current Pay Period',
                                    ),
                                  ),
                                const SizedBox(height: 22),
                                const Text(
                                  'Locked / Historical Pay Periods',
                                  style: TextStyle(
                                    color: AppTheme.darkText,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (historyPeriods.isEmpty)
                                  const _EmptyPayPeriodsCard()
                                else
                                  ...historyPeriods.map((period) {
                                    return _PayPeriodCard(
                                      name: period.name,
                                      startDate: _formatDate(period.startDate),
                                      endDate: _formatDate(period.endDate),
                                      status: period.isLocked ? 'Locked' : 'Open',
                                      entryCount: period.entryCount,
                                      lockedByName: period.lockedByUserId ?? 'Not locked',
                                      lockedAt: period.lockedAt == null
                                          ? 'Not locked'
                                          : _formatDate(period.lockedAt),
                                      isLocked: period.isLocked,
                                      isBusy: _isBusy,
                                      onLock: period.isLocked
                                          ? null
                                          : () => _confirmLock(
                                                companyId: companyId,
                                                calculatedPeriod: {
                                                  'name': period.name,
                                                  'startDate': period.startDate,
                                                  'endDate': period.endDate,
                                                },
                                              ),
                                      onUnlock: () => _confirmUnlock(
                                        companyId: companyId,
                                        payPeriodId: period.payPeriodId,
                                        name: period.name,
                                      ),
                                      onDelete: period.isLocked
                                          ? null
                                          : () => _deletePeriod(
                                                companyId: companyId,
                                                payPeriodId: period.payPeriodId,
                                                name: period.name,
                                              ),
                                      // Same as the current period above —
                                      // view/copy/export/PDF work regardless
                                      // of lock state now.
                                      onViewSummary: () => _openPayrollSummary(
                                        companyId: companyId,
                                        payPeriodName: period.name,
                                        startDate: period.startDate,
                                        endDate: period.endDate,
                                        isLocked: period.isLocked,
                                      ),
                                      onCopyPrintable: () => _copyPrintableSummary(
                                        companyId: companyId,
                                        startDate: period.startDate,
                                        endDate: period.endDate,
                                        name: period.name,
                                      ),
                                      onExport: () => _exportPeriodCsv(
                                        companyId: companyId,
                                        startDate: period.startDate,
                                        endDate: period.endDate,
                                        name: period.name,
                                      ),
                                      onGeneratePdf: () => _generateTimesheetPdf(
                                        companyId: companyId,
                                        startDate: period.startDate,
                                        endDate: period.endDate,
                                        name: period.name,
                                      ),
                                    );
                                  }),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PayrollSettingsCard extends StatelessWidget {
  final String selectedCycleType;
  final String firstStartDateText;
  final TextEditingController customDaysController;
  final bool isSaving;
  final ValueChanged<String> onCycleChanged;
  final VoidCallback onPickFirstStartDate;
  final VoidCallback onSave;

  const _PayrollSettingsCard({
    required this.selectedCycleType,
    required this.firstStartDateText,
    required this.customDaysController,
    required this.isSaving,
    required this.onCycleChanged,
    required this.onPickFirstStartDate,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payroll Schedule',
              style: TextStyle(
                color: AppTheme.darkText,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Set this once. BlueField will calculate current and future pay periods automatically.',
              style: TextStyle(
                color: AppTheme.mutedText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            _CycleOption(
              label: 'Weekly',
              value: 'weekly',
              groupValue: selectedCycleType,
              onChanged: onCycleChanged,
            ),
            _CycleOption(
              label: 'Biweekly',
              value: 'biweekly',
              groupValue: selectedCycleType,
              onChanged: onCycleChanged,
            ),
            _CycleOption(
              label: 'Custom Days',
              value: 'custom',
              groupValue: selectedCycleType,
              onChanged: onCycleChanged,
            ),
            if (selectedCycleType == 'custom') ...[
              const SizedBox(height: 10),
              TextField(
                controller: customDaysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Custom period length',
                  hintText: 'Example: 10',
                ),
              ),
            ],
            const SizedBox(height: 12),
            _DatePickerButton(
              label: 'First Pay Period Start',
              value: firstStartDateText,
              onTap: onPickFirstStartDate,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: const Icon(Icons.save_outlined),
                label: Text(isSaving ? 'Saving...' : 'Save Payroll Schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleOption extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onChanged;

  const _CycleOption({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(
          color: AppTheme.darkText,
          fontWeight: FontWeight.w600,
        ),
      ),
      value: value,
      groupValue: groupValue,
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }
}

class _CurrentPayPeriodCard extends StatelessWidget {
  final String name;
  final String startDate;
  final String endDate;
  final String status;
  final String cycleType;
  final int periodLengthDays;
  final bool isLocked;
  final bool isBusy;
  final VoidCallback onLock;
  final VoidCallback? onUnlock;
  final VoidCallback? onViewSummary;
  final VoidCallback? onCopyPrintable;
  final VoidCallback? onExport;
  final VoidCallback? onGeneratePdf;

  const _CurrentPayPeriodCard({
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.cycleType,
    required this.periodLengthDays,
    required this.isLocked,
    required this.isBusy,
    required this.onLock,
    required this.onUnlock,
    required this.onViewSummary,
    required this.onCopyPrintable,
    required this.onExport,
    this.onGeneratePdf,
  });

  String get _cycleLabel {
    if (cycleType == 'weekly') return 'Weekly';
    if (cycleType == 'biweekly') return 'Biweekly';

    return '$periodLengthDays-day custom cycle';
  }

  @override
  Widget build(BuildContext context) {
    return _PayPeriodActionCard(
      title: 'Current Pay Period',
      name: name,
      startDate: startDate,
      endDate: endDate,
      status: status,
      cycleLabel: _cycleLabel,
      isLocked: isLocked,
      isBusy: isBusy,
      onLock: onLock,
      onUnlock: onUnlock,
      onDelete: null,
      onViewSummary: onViewSummary,
      onCopyPrintable: onCopyPrintable,
      onExport: onExport,
      onGeneratePdf: onGeneratePdf,
      entryCount: null,
      lockedByName: null,
      lockedAt: null,
    );
  }
}

class _PayPeriodCard extends StatelessWidget {
  final String name;
  final String startDate;
  final String endDate;
  final String status;
  final int entryCount;
  final String lockedByName;
  final String lockedAt;
  final bool isLocked;
  final bool isBusy;
  final VoidCallback? onLock;
  final VoidCallback onUnlock;
  final VoidCallback? onDelete;
  final VoidCallback? onViewSummary;
  final VoidCallback? onCopyPrintable;
  final VoidCallback? onExport;
  final VoidCallback? onGeneratePdf;

  const _PayPeriodCard({
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.entryCount,
    required this.lockedByName,
    required this.lockedAt,
    required this.isLocked,
    required this.isBusy,
    this.onLock,
    required this.onUnlock,
    required this.onDelete,
    required this.onViewSummary,
    required this.onCopyPrintable,
    required this.onExport,
    this.onGeneratePdf,
  });

  @override
  Widget build(BuildContext context) {
    return _PayPeriodActionCard(
      title: name,
      name: name,
      startDate: startDate,
      endDate: endDate,
      status: status,
      cycleLabel: null,
      isLocked: isLocked,
      isBusy: isBusy,
      // A historical period that isn't currently locked (it was
      // unlocked, or was never locked while it was still "current" and
      // then aged out of that slot) previously had no way back to
      // Locked from this screen — onLock was always hardcoded to null
      // here, so _PayPeriodActionCard's button logic fell through to
      // Delete-only. Now the caller can pass a real lock callback for
      // exactly this case.
      onLock: onLock,
      onUnlock: onUnlock,
      onDelete: onDelete,
      onViewSummary: onViewSummary,
      onCopyPrintable: onCopyPrintable,
      onExport: onExport,
      onGeneratePdf: onGeneratePdf,
      entryCount: entryCount,
      lockedByName: lockedByName,
      lockedAt: lockedAt,
    );
  }
}

class _PayPeriodActionCard extends StatelessWidget {
  final String title;
  final String name;
  final String startDate;
  final String endDate;
  final String status;
  final String? cycleLabel;
  final bool isLocked;
  final bool isBusy;
  final VoidCallback? onLock;
  final VoidCallback? onUnlock;
  final VoidCallback? onDelete;
  final VoidCallback? onViewSummary;
  final VoidCallback? onCopyPrintable;
  final VoidCallback? onExport;
  final VoidCallback? onGeneratePdf;
  final int? entryCount;
  final String? lockedByName;
  final String? lockedAt;

  const _PayPeriodActionCard({
    required this.title,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.cycleLabel,
    required this.isLocked,
    required this.isBusy,
    required this.onLock,
    required this.onUnlock,
    required this.onDelete,
    required this.onViewSummary,
    required this.onCopyPrintable,
    required this.onExport,
    this.onGeneratePdf,
    required this.entryCount,
    required this.lockedByName,
    required this.lockedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isLocked ? Icons.lock_outline : Icons.lock_open_outlined,
                  color: isLocked ? Colors.orange : AppTheme.blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.darkText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _StatusBadge(label: status, isLocked: isLocked),
              ],
            ),
            const SizedBox(height: 14),
            _PayPeriodRow(label: 'Start', value: startDate),
            const SizedBox(height: 7),
            _PayPeriodRow(label: 'End', value: endDate),
            if (cycleLabel != null) ...[
              const SizedBox(height: 7),
              _PayPeriodRow(label: 'Cycle', value: cycleLabel!),
            ],
            if (entryCount != null) ...[
              const SizedBox(height: 7),
              _PayPeriodRow(label: 'Entries Locked', value: entryCount.toString()),
            ],
            if (lockedByName != null) ...[
              const SizedBox(height: 7),
              _PayPeriodRow(label: 'Locked By', value: lockedByName!),
            ],
            if (lockedAt != null) ...[
              const SizedBox(height: 7),
              _PayPeriodRow(label: 'Locked On', value: lockedAt!),
            ],
            const SizedBox(height: 14),
            // Available regardless of lock state — an open period's
            // numbers can still shift before it's locked, but a manager
            // may need to pull payroll info before then anyway. Each
            // export screen/action flags when the period is still open.
            _ActionButton(
              icon: Icons.receipt_long_outlined,
              label: 'View Payroll Summary',
              onPressed: isBusy ? null : onViewSummary,
              filled: true,
            ),
            const SizedBox(height: 10),
            _ActionButton(
              icon: Icons.print_outlined,
              label: 'Copy Printable Summary',
              onPressed: isBusy ? null : onCopyPrintable,
              filled: false,
            ),
            const SizedBox(height: 10),
            _ActionButton(
              icon: Icons.file_download_outlined,
              label: 'Copy CSV',
              onPressed: isBusy ? null : onExport,
              filled: false,
            ),
            if (onGeneratePdf != null) ...[
              const SizedBox(height: 10),
              _ActionButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Generate Timesheets (PDF)',
                onPressed: isBusy ? null : onGeneratePdf,
                filled: false,
              ),
            ],
            const SizedBox(height: 10),
            if (isLocked)
              _ActionButton(
                icon: Icons.lock_open_outlined,
                label: 'Unlock',
                onPressed: isBusy ? null : onUnlock,
                filled: false,
              )
            else ...[
              // Not locked: offer both Lock and Delete rather than
              // picking just one. A period only ever ends up here (as
              // a stored, non-current doc) after having been locked at
              // least once and then unlocked — there's no reason
              // re-locking it should cost you the ability to delete it
              // instead, or vice versa.
              if (onLock != null)
                _ActionButton(
                  icon: Icons.lock_outline,
                  label: 'Lock Period',
                  onPressed: isBusy ? null : onLock,
                  filled: true,
                ),
              if (onLock != null && onDelete != null) const SizedBox(height: 10),
              if (onDelete != null)
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onPressed: isBusy ? null : onDelete,
                  filled: false,
                  danger: true,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool danger;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.filled,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        style: danger
            ? OutlinedButton.styleFrom(foregroundColor: Colors.red)
            : null,
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DatePickerButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool isLocked;

  const _StatusBadge({
    required this.label,
    required this.isLocked,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isLocked ? Colors.orange.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLocked ? Colors.orange.shade200 : Colors.blue.shade100,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isLocked ? Colors.orange : AppTheme.blue,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PayPeriodRow extends StatelessWidget {
  final String label;
  final String value;

  const _PayPeriodRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 115,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppTheme.darkText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoCurrentPeriodCard extends StatelessWidget {
  const _NoCurrentPeriodCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Text(
          'Set a payroll schedule to calculate the current pay period.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.mutedText),
        ),
      ),
    );
  }
}

class _EmptyPayPeriodsCard extends StatelessWidget {
  const _EmptyPayPeriodsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: const Padding(
        padding: EdgeInsets.all(22),
        child: Text(
          'No historical pay periods yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.mutedText),
        ),
      ),
    );
  }
}
