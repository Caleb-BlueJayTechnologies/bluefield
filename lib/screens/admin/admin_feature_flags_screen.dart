import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../Models/feature_flag_model.dart';
import '../../Services/feature_flag_service.dart';
import '../../theme/app_theme.dart';
import 'environment_indicator.dart';

class AdminFeatureFlagsScreen extends StatefulWidget {
  const AdminFeatureFlagsScreen({super.key});

  @override
  State<AdminFeatureFlagsScreen> createState() => _AdminFeatureFlagsScreenState();
}

class _AdminFeatureFlagsScreenState extends State<AdminFeatureFlagsScreen> {
  final FeatureFlagService _service = FeatureFlagService();
  late Stream<List<FeatureFlagModel>> _flagsStream;
  bool _isActing = false;

  @override
  void initState() {
    super.initState();
    _flagsStream = _service.watchAllFlags();
  }

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _openCreateDialog() async {
    final keyController = TextEditingController();
    final descController = TextEditingController();
    final companyIdsController = TextEditingController();
    var rollout = 0;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Feature Flag'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: keyController,
                  decoration: const InputDecoration(labelText: 'Flag Key', hintText: 'e.g. newSchedulingUi'),
                ),
                const SizedBox(height: 12),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
                const SizedBox(height: 12),
                TextField(
                  controller: companyIdsController,
                  decoration: const InputDecoration(labelText: 'Enabled Company IDs (comma-separated, optional)'),
                ),
                const SizedBox(height: 12),
                Text('Rollout Percentage: $rollout%', style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  value: rollout.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '$rollout%',
                  onChanged: (value) => setDialogState(() => rollout = value.round()),
                ),
                const SizedBox(height: 4),
                const Text(
                  'A company gets this flag if it\'s in the ID list above OR falls into this rollout bucket — either is enough.',
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
      ),
    );

    if (created != true) return;
    if (keyController.text.trim().isEmpty) return;

    final companyIds = companyIdsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    setState(() => _isActing = true);
    try {
      await _service.createFlag(
        actingAdminId: _myUid,
        flagKey: keyController.text.trim(),
        description: descController.text.trim(),
        enabledCompanyIds: companyIds,
        rolloutPercentage: rollout,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flag created.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _openEditDialog(FeatureFlagModel flag) async {
    final companyIdsController = TextEditingController(text: flag.enabledCompanyIds.join(', '));
    var rollout = flag.rolloutPercentage;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(flag.flagKey),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: companyIdsController,
                  decoration: const InputDecoration(labelText: 'Enabled Company IDs (comma-separated)'),
                ),
                const SizedBox(height: 12),
                Text('Rollout Percentage: $rollout%', style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  value: rollout.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '$rollout%',
                  onChanged: (value) => setDialogState(() => rollout = value.round()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final companyIds = companyIdsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    setState(() => _isActing = true);
    try {
      await _service.updateFlag(
        actingAdminId: _myUid,
        flagKey: flag.flagKey,
        enabledCompanyIds: companyIds,
        rolloutPercentage: rollout,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _toggleActive(FeatureFlagModel flag) async {
    setState(() => _isActing = true);
    try {
      await _service.updateFlag(actingAdminId: _myUid, flagKey: flag.flagKey, isActive: !flag.isActive);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _confirmDelete(FeatureFlagModel flag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Flag?'),
        content: Text('This permanently deletes "${flag.flagKey}". Any code checking this flag will get false afterward.'),
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
      await _service.deleteFlag(actingAdminId: _myUid, flagKey: flag.flagKey);
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
        title: const Text('Feature Flags', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isActing ? null : _openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Flag'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const EnvironmentIndicator(),
            Expanded(
              child: StreamBuilder<List<FeatureFlagModel>>(
                stream: _flagsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final flags = snapshot.data ?? [];
                  if (flags.isEmpty) {
                    return const Center(
                      child: Text('No feature flags yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                    itemCount: flags.length,
                    itemBuilder: (context, index) {
                      final flag = flags[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(flag.flagKey,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.darkText)),
                                  ),
                                  Switch(value: flag.isActive, onChanged: _isActing ? null : (_) => _toggleActive(flag)),
                                ],
                              ),
                              if (flag.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(flag.description, style: const TextStyle(color: AppTheme.mutedText)),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                '${flag.rolloutPercentage}% rollout • ${flag.enabledCompanyIds.length} company override(s)',
                                style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: _isActing ? null : () => _openEditDialog(flag),
                                    child: const Text('Edit'),
                                  ),
                                  TextButton(
                                    onPressed: _isActing ? null : () => _confirmDelete(flag),
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
