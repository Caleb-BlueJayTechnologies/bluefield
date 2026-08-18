import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Services/time_entry_service.dart';
import '../theme/app_theme.dart';
import 'demo_data_seeder.dart';

/// Only ever pushed from a debug entry point gated to the
/// GenericMoversDemo@gmail.com account (see employer_dashboard_screen.dart)
/// — this screen itself also re-checks the signed-in email before
/// letting the button do anything, since DemoDataSeeder.run() enforces
/// the same check anyway.
class DemoDataSeedScreen extends StatefulWidget {
  const DemoDataSeedScreen({super.key});

  @override
  State<DemoDataSeedScreen> createState() => _DemoDataSeedScreenState();
}

class _DemoDataSeedScreenState extends State<DemoDataSeedScreen> {
  final TimeEntryService _timeEntryService = TimeEntryService();
  final List<String> _log = [];
  bool _running = false;
  bool _done = false;
  String? _error;

  Future<void> _confirmAndRun() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Generate demo data?'),
          content: const Text(
            'This first WIPES any demo data a previous run generated — '
            'employees, crews, vehicles, equipment, jobs, time entries, '
            'time off, and messages — then writes a fresh, full year of '
            'backdated history in its place. Your own Owner profile and '
            'company settings are left alone. This can take a couple of '
            "minutes and can't be undone from inside the app.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Generate'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _run();
  }

  Future<void> _run() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() => _error = 'No signed-in user found.');
      return;
    }

    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _log.clear();
    });

    try {
      final companyId = await _timeEntryService.getCurrentCompanyId();
      final seeder = DemoDataSeeder();
      await seeder.run(
        companyId: companyId,
        ownerId: user.uid,
        signedInEmail: user.email!,
        onProgress: (message) {
          if (!mounted) return;
          setState(() => _log.add(message));
        },
      );
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
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
          'Generate Demo Data',
          style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Demo seed — safe to re-run',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '8 employees across 2 crews, 3 vans, a dozen pieces of '
                        'equipment, a full year of jobs and time-clock history, '
                        'a year of time-off requests, and message history — all '
                        'backdated. Re-running this wipes and regenerates '
                        'everything above, so it always comes back clean.',
                        style: TextStyle(color: AppTheme.mutedText),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _running ? null : _confirmAndRun,
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: Text(_running ? 'Generating...' : 'Generate Demo Data'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Card(
                  elevation: 0,
                  color: Colors.red.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                ),
              if (_done)
                Card(
                  elevation: 0,
                  color: Colors.green.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  child: const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'Done — pull to refresh anywhere in the app to see the new data.',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${index + 1}. ${_log[index]}',
                        style: const TextStyle(color: AppTheme.darkText, fontSize: 13),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
