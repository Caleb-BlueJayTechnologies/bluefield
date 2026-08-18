import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../Models/company_settings_model.dart';
import '../Models/time_entry_model.dart';
import '../Services/company_settings_service.dart';
import '../Services/time_entry_service.dart';
import '../theme/app_theme.dart';
import 'my_time_history_screen.dart';

class ClockInScreen extends StatefulWidget {
  const ClockInScreen({super.key});

  @override
  State<ClockInScreen> createState() => _ClockInScreenState();
}

class _ClockInScreenState extends State<ClockInScreen> {
  final TimeEntryService _timeEntryService = TimeEntryService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  bool _isLoading = false;
  late Future<String> _companyFuture;

  // Ticks the UI every 30s so the "Time running" display for an active
  // clock-in counts up live instead of freezing at whatever value it
  // had when this screen was last rebuilt.
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _companyFuture = _timeEntryService.getCurrentCompanyId();
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  /// Best-effort GPS capture — returns null on any failure (denied
  /// permission, disabled services, etc.) rather than throwing, so a
  /// technical GPS problem never traps someone out of clocking in or
  /// out. A null position just means the geofence check gets skipped
  /// entirely, same as a company that hasn't set a zone at all.
  Future<Position?> _captureCurrentPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> _clockIn({bool confirmedOutsideZone = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    GeofenceConfirmationRequiredException? needsConfirmation;

    try {
      final position = await _captureCurrentPosition();

      await _timeEntryService.clockIn(
        latitude: position?.latitude,
        longitude: position?.longitude,
        confirmedOutsideZone: confirmedOutsideZone,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clocked in.')),
      );
    } on GeofenceConfirmationRequiredException catch (e) {
      needsConfirmation = e;
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readErrorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }

    if (needsConfirmation != null && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Outside Clock-In Zone'),
          content: Text('${needsConfirmation!.toString()} Clock in anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clock In Anyway')),
          ],
        ),
      );
      if (confirmed == true) {
        await _clockIn(confirmedOutsideZone: true);
      }
    }
  }

  Future<void> _clockOut({
    required String companyId,
    required String timeEntryId,
  }) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final position = await _captureCurrentPosition();

      await _timeEntryService.clockOut(
        companyId: companyId,
        timeEntryId: timeEntryId,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clocked out.')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readErrorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Shows the Paid/Unpaid choice, then starts the break. Neither
  /// option clocks the employee out — see TimeEntryService.startBreak.
  Future<void> _promptStartBreak({
    required String companyId,
    required String timeEntryId,
  }) async {
    if (_isLoading) return;

    final isPaid = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Start Break', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                const SizedBox(height: 6),
                const Text(
                  'Your clock stays running either way — this just tells management whether this break counts toward paid hours.',
                  style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('Paid Break'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('Unpaid Break'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (isPaid == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _timeEntryService.startBreak(
        companyId: companyId,
        timeEntryId: timeEntryId,
        isPaid: isPaid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isPaid ? 'Paid break started.' : 'Unpaid break started.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _endBreak({
    required String companyId,
    required String timeEntryId,
  }) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      await _timeEntryService.endBreak(companyId: companyId, timeEntryId: timeEntryId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Break ended.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openMyTimeHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MyTimeHistoryScreen()),
    );
  }

  String _readErrorMessage(Object error) {
    var message = error.toString().trim();

    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }
    if (message.startsWith('Bad state: ')) {
      message = message.substring('Bad state: '.length);
    }

    return message.isEmpty ? 'Something went wrong.' : message;
  }

  Widget _buildHistoryButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _openMyTimeHistory,
        icon: const Icon(Icons.history_outlined),
        label: const Text('My Time History'),
      ),
    );
  }

  Widget _buildDisabledClockCard({required String message}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time_filled_outlined, size: 46, color: AppTheme.blue),
            const SizedBox(height: 14),
            const Text(
              'Clock Unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.mutedText),
            ),
            const SizedBox(height: 20),
            _buildHistoryButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildClockCard({required String companyId, required User user, required bool breaksEnabled}) {
    return StreamBuilder<TimeEntryModel?>(
      stream: _timeEntryService.watchActiveClockEntry(
        companyId: companyId,
        employeeId: user.uid,
      ),
      builder: (context, clockSnapshot) {
        if (clockSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (clockSnapshot.hasError) {
          return _ClockMessageCard(
            icon: Icons.error_outline,
            title: 'Unable to load clock status',
            message: _readErrorMessage(clockSnapshot.error!),
          );
        }

        final activeEntry = clockSnapshot.data;
        final isClockedIn = activeEntry != null;
        final activeBreak = activeEntry?.activeBreak;
        final isOnBreak = activeBreak != null;

        return Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.blue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isClockedIn ? Icons.timer_outlined : Icons.access_time,
                        color: AppTheme.blue,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isClockedIn ? 'Currently Clocked In' : 'Currently Clocked Out',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isOnBreak
                                ? '${activeBreak!.isPaid ? 'Paid' : 'Unpaid'} break in progress.'
                                : isClockedIn
                                    ? 'Your work timer is active.'
                                    : 'Start your workday when ready.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: isOnBreak ? Colors.orange.shade800 : AppTheme.mutedText,
                              fontWeight: isOnBreak ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (isClockedIn) ...[
                  _ClockInfoRow(
                    label: 'Clocked in at',
                    value: _timeEntryService.formatTime(activeEntry.clockInAt),
                  ),
                  const SizedBox(height: 12),
                  _ClockInfoRow(
                    label: 'Time running',
                    value: _timeEntryService.formatDuration(
                      DateTime.now().difference(activeEntry.clockInAt),
                    ),
                  ),
                  if (isOnBreak) ...[
                    const SizedBox(height: 12),
                    _ClockInfoRow(
                      label: '${activeBreak!.isPaid ? 'Paid' : 'Unpaid'} break running',
                      value: _timeEntryService.formatDuration(activeBreak!.duration),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
                if (isClockedIn) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _clockOut(
                                companyId: companyId,
                                timeEntryId: activeEntry.timeEntryId,
                              ),
                      icon: const Icon(Icons.logout_outlined),
                      label: Text(
                        _isLoading ? 'Saving...' : 'Clock Out',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  if (breaksEnabled) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: isOnBreak
                          ? FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
                              onPressed: _isLoading
                                  ? null
                                  : () => _endBreak(companyId: companyId, timeEntryId: activeEntry.timeEntryId),
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: const Text('End Break'),
                            )
                          : OutlinedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () => _promptStartBreak(companyId: companyId, timeEntryId: activeEntry.timeEntryId),
                              icon: const Icon(Icons.free_breakfast_outlined),
                              label: const Text('Start Break'),
                            ),
                    ),
                  ],
                ] else
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _clockIn,
                      icon: const Icon(Icons.login_outlined),
                      label: Text(
                        _isLoading ? 'Saving...' : 'Clock In',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _buildHistoryButton(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsContent({required String companyId, required User user}) {
    return StreamBuilder<CompanySettingsModel>(
      stream: _settingsService.watchCompanySettings(companyId),
      builder: (context, settingsSnapshot) {
        if (settingsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (settingsSnapshot.hasError) {
          return _ClockMessageCard(
            icon: Icons.settings_outlined,
            title: 'Unable to load settings',
            message: _readErrorMessage(settingsSnapshot.error!),
          );
        }

        final settings = settingsSnapshot.data;

        if (settings == null) {
          return const _ClockMessageCard(
            icon: Icons.settings_outlined,
            title: 'Settings unavailable',
            message: 'Company settings could not be loaded.',
          );
        }

        if (!_settingsService.isTeamTimeEnabled(settings)) {
          return _ClockMessageCard(
            icon: Icons.access_time_outlined,
            title: 'Team Time Unavailable',
            message: _settingsService.disabledMessageForFeature('teamTime'),
          );
        }

        if (!_settingsService.isClockInOutEnabled(settings)) {
          return _buildDisabledClockCard(
            message: _settingsService.disabledMessageForFeature('clockInOut'),
          );
        }

        return _buildClockCard(
          companyId: companyId,
          user: user,
          breaksEnabled: _settingsService.areBreaksEnabled(settings),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Clock In / Out',
          style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: FutureBuilder<String>(
                      future: _companyFuture,
                      builder: (context, companySnapshot) {
                        if (companySnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (user == null) {
                          return const _ClockMessageCard(
                            icon: Icons.person_off_outlined,
                            title: 'Not signed in',
                            message: 'Sign in before using the clock system.',
                          );
                        }

                        if (companySnapshot.hasError ||
                            companySnapshot.data == null ||
                            companySnapshot.data!.isEmpty) {
                          return _ClockMessageCard(
                            icon: Icons.business_outlined,
                            title: 'Company not found',
                            message: companySnapshot.error != null
                                ? _readErrorMessage(companySnapshot.error!)
                                : 'This account is not linked to a company.',
                          );
                        }

                        return _buildSettingsContent(
                          companyId: companySnapshot.data!,
                          user: user,
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ClockInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ClockInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppTheme.mutedText),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.darkText),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockMessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _ClockMessageCard({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppTheme.blue),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.darkText),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}
