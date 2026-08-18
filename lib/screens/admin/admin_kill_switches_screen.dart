import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../Models/kill_switch_model.dart';
import '../../Services/kill_switch_service.dart';
import '../../theme/app_theme.dart';
import 'environment_indicator.dart';

class AdminKillSwitchesScreen extends StatefulWidget {
  const AdminKillSwitchesScreen({super.key});

  @override
  State<AdminKillSwitchesScreen> createState() => _AdminKillSwitchesScreenState();
}

class _AdminKillSwitchesScreenState extends State<AdminKillSwitchesScreen> {
  final KillSwitchService _service = KillSwitchService();
  late Stream<List<KillSwitchModel>> _switchesStream;
  bool _isActing = false;

  @override
  void initState() {
    super.initState();
    _switchesStream = _service.watchAllSwitches();
  }

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _formatDate(DateTime value) {
    return '${value.month}/${value.day}/${value.year} • ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openCreateDialog() async {
    final keyController = TextEditingController();
    final descController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Kill Switch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: keyController,
                decoration: const InputDecoration(labelText: 'Switch Key', hintText: 'e.g. messaging, jobCreation, timeClockIn'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'What does this control?'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              const Text(
                'Creating this doesn\'t disable anything yet — it starts off. You activate it separately when needed.',
                style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );

    if (created != true) return;
    if (keyController.text.trim().isEmpty) return;

    setState(() => _isActing = true);
    try {
      await _service.createSwitch(
        actingAdminId: _myUid,
        switchKey: keyController.text.trim(),
        description: descController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kill switch created.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _confirmActivate(KillSwitchModel sw) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activate Kill Switch?'),
        content: Text(
          'This immediately disables "${sw.switchKey}" for every company using the app right now — not a rollout, '
          'not a test group, everyone, instantly. Only use this for genuine incident response.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Activate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isActing = true);
    try {
      await _service.activate(actingAdminId: _myUid, switchKey: sw.switchKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${sw.switchKey}" is now disabled for everyone.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _deactivate(KillSwitchModel sw) async {
    setState(() => _isActing = true);
    try {
      await _service.deactivate(actingAdminId: _myUid, switchKey: sw.switchKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${sw.switchKey}" restored.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _confirmDelete(KillSwitchModel sw) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Kill Switch?'),
        content: Text('This permanently removes "${sw.switchKey}". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isActing = true);
    try {
      await _service.deleteSwitch(actingAdminId: _myUid, switchKey: sw.switchKey);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
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
        title: const Text('Kill Switches', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isActing ? null : _openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Switch'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const EnvironmentIndicator(),
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const Text(
                'For incident response only. Activating a switch disables that system for every company immediately — '
                'this is not a gradual rollout tool. See Feature Flags for that.',
                style: TextStyle(fontSize: 11, color: AppTheme.mutedText),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<KillSwitchModel>>(
                stream: _switchesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final switches = snapshot.data ?? [];
                  if (switches.isEmpty) {
                    return const Center(
                      child: Text('No kill switches configured.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                    itemCount: switches.length,
                    itemBuilder: (context, index) {
                      final sw = switches[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: sw.isKilled ? Colors.red.shade50 : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: sw.isKilled ? BorderSide(color: Colors.red.shade200) : BorderSide.none,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    sw.isKilled ? Icons.power_off_outlined : Icons.power_outlined,
                                    color: sw.isKilled ? Colors.red : Colors.green,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(sw.switchKey,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.darkText)),
                                  ),
                                  Text(
                                    sw.isKilled ? 'DISABLED' : 'Active',
                                    style: TextStyle(
                                      color: sw.isKilled ? Colors.red : Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              if (sw.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(sw.description, style: const TextStyle(color: AppTheme.mutedText)),
                              ],
                              if (sw.isKilled && sw.activatedAt != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Disabled ${_formatDate(sw.activatedAt!)}',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (sw.isKilled)
                                    FilledButton(
                                      onPressed: _isActing ? null : () => _deactivate(sw),
                                      child: const Text('Restore'),
                                    )
                                  else
                                    OutlinedButton(
                                      onPressed: _isActing ? null : () => _confirmActivate(sw),
                                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('Activate'),
                                    ),
                                  TextButton(
                                    onPressed: _isActing ? null : () => _confirmDelete(sw),
                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
