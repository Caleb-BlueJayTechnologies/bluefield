import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../Models/company_model.dart';
import '../../Services/admin_company_service.dart';
import '../../theme/app_theme.dart';
import 'admin_company_audit_screen.dart';
import 'admin_view_as_screen.dart';

class AdminCompanyDetailScreen extends StatefulWidget {
  final String companyId;

  const AdminCompanyDetailScreen({super.key, required this.companyId});

  @override
  State<AdminCompanyDetailScreen> createState() => _AdminCompanyDetailScreenState();
}

class _AdminCompanyDetailScreenState extends State<AdminCompanyDetailScreen> {
  final AdminCompanyService _companyService = AdminCompanyService();
  final TextEditingController _notesController = TextEditingController();

  bool _isSavingNotes = false;
  bool _isActing = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String get _adminId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _pricingLabel(String program) {
    switch (program) {
      case CompanyPricingProgram.founding:
        return 'Founding';
      case CompanyPricingProgram.beta:
        return 'Beta';
      case CompanyPricingProgram.earlyAdopter:
        return 'Early Adopter';
      case CompanyPricingProgram.legacy:
        return 'Legacy';
      default:
        return 'Standard';
    }
  }

  String _subscriptionLabel(String status) {
    switch (status) {
      case CompanySubscriptionStatus.active:
        return 'Active';
      case CompanySubscriptionStatus.pastDue:
        return 'Past Due';
      case CompanySubscriptionStatus.cancelled:
        return 'Cancelled';
      case CompanySubscriptionStatus.internal:
        return 'Internal';
      default:
        return 'Trialing';
    }
  }

  String _formatDate(DateTime value) => '${value.month}/${value.day}/${value.year}';

  Future<void> _confirmAndRun(String title, String message, Future<void> Function() action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isActing = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _suspend() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suspend Company'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason', hintText: 'Required'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, reasonController.text), child: const Text('Suspend')),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;

    await _confirmAndRun(
      'Suspend Company',
      'This company will lose access to the app immediately. Continue?',
      () => _companyService.suspendCompany(actingAdminId: _adminId, companyId: widget.companyId, reason: reason),
    );
  }

  Future<void> _saveNotes(String currentNotes) async {
    setState(() => _isSavingNotes = true);
    try {
      await _companyService.updateAdminNotes(
        actingAdminId: _adminId,
        companyId: widget.companyId,
        notes: _notesController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notes saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSavingNotes = false);
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
        title: const Text('Company Profile', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<CompanyModel>>(
        stream: _companyService.watchAllCompanies(),
        builder: (context, snapshot) {
          final companies = snapshot.data;
          final company = companies?.where((c) => c.companyId == widget.companyId).toList();

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (company == null || company.isEmpty) {
            return const Center(child: Text('Company not found.', style: TextStyle(color: AppTheme.mutedText)));
          }

          final c = company.first;
          if (_notesController.text.isEmpty && c.adminNotes != null) {
            _notesController.text = c.adminNotes!;
          }

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                elevation: 0,
                color: AppTheme.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.companyName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('ID: ${c.companyId}', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text(c.isActive ? 'Active' : 'Suspended', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard('Overview', [
                _infoRow('Created', _formatDate(c.createdAt)),
                _infoRow('Pricing Program', _pricingLabel(c.pricingProgram)),
                _infoRow('Subscription', _subscriptionLabel(c.subscriptionStatus)),
                _infoRow('Employee Limit', '${c.employeeLimit}'),
                if (c.customerNumber != null) _infoRow('Customer #', '${c.customerNumber}'),
                StreamBuilder<int>(
                  stream: _companyService.watchEmployeeCount(c.companyId),
                  builder: (context, s) => _infoRow('Current Employees', '${s.data ?? '...'}'),
                ),
                FutureBuilder<List<String>>(
                  future: _companyService.getOwnerNames(c.companyId),
                  builder: (context, s) => _infoRow('Owner(s)', (s.data ?? []).join(', ').isEmpty ? '—' : s.data!.join(', ')),
                ),
                if (c.suspendedReason != null) _infoRow('Suspension Reason', c.suspendedReason!),
              ]),
              _sectionCard('Flags', [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Internal (BlueJay) Account'),
                  subtitle: const Text('Excluded from customer stats', style: TextStyle(fontSize: 12)),
                  value: c.isInternalAccount,
                  onChanged: _isActing
                      ? null
                      : (value) => _confirmAndRun(
                            value ? 'Mark Internal' : 'Unmark Internal',
                            'Change internal-account status for this company?',
                            () => _companyService.setInternalAccount(
                                actingAdminId: _adminId, companyId: c.companyId, isInternal: value),
                          ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Test / Demo Company'),
                  subtitle: const Text('Excluded from analytics and billing', style: TextStyle(fontSize: 12)),
                  value: c.isTestCompany,
                  onChanged: _isActing
                      ? null
                      : (value) => _confirmAndRun(
                            value ? 'Mark as Test' : 'Unmark as Test',
                            'Change test-company status for this company?',
                            () => _companyService.setTestCompany(
                                actingAdminId: _adminId, companyId: c.companyId, isTest: value),
                          ),
                ),
              ]),
              _sectionCard('Pricing Program', [
                DropdownButtonFormField<String>(
                  value: c.pricingProgram,
                  items: [
                    CompanyPricingProgram.founding,
                    CompanyPricingProgram.beta,
                    CompanyPricingProgram.earlyAdopter,
                    CompanyPricingProgram.legacy,
                    CompanyPricingProgram.standard,
                  ].map((p) => DropdownMenuItem(value: p, child: Text(_pricingLabel(p)))).toList(),
                  onChanged: _isActing
                      ? null
                      : (value) {
                          if (value == null || value == c.pricingProgram) return;

                          final isDowngradeFromLockedTier =
                              (c.pricingProgram == CompanyPricingProgram.founding ||
                                  c.pricingProgram == CompanyPricingProgram.beta ||
                                  c.pricingProgram == CompanyPricingProgram.earlyAdopter ||
                                  c.pricingProgram == CompanyPricingProgram.legacy) &&
                              value == CompanyPricingProgram.standard;

                          _confirmAndRun(
                            isDowngradeFromLockedTier ? 'Change a Locked Pricing Commitment' : 'Change Pricing Program',
                            isDowngradeFromLockedTier
                                ? 'This company was permanently promised ${_pricingLabel(c.pricingProgram)} pricing '
                                    'as customer #${c.customerNumber ?? '?'}. Moving them to ${_pricingLabel(value)} '
                                    'changes what they were actually offered at signup. This should only be done to '
                                    'correct a genuine data-entry mistake, not as a routine change. Continue?'
                                : 'Move this company to ${_pricingLabel(value)} pricing?',
                            () => _companyService.changePricingProgram(
                                actingAdminId: _adminId, companyId: c.companyId, newProgram: value),
                          );
                        },
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminCompanyAuditScreen(companyId: c.companyId, companyName: c.companyName),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history_outlined, size: 18),
                  label: const Text('View Audit Log'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminViewAsScreen(companyId: c.companyId, companyName: c.companyName),
                      ),
                    );
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View As'),
                ),
              ),
              _sectionCard('Internal Notes', [
                TextField(
                  controller: _notesController,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Private notes — never visible to the company'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _isSavingNotes ? null : () => _saveNotes(c.adminNotes ?? ''),
                    icon: _isSavingNotes
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save Notes'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isActing
                      ? null
                      : () {
                          if (c.isActive) {
                            _suspend();
                          } else {
                            _confirmAndRun(
                              'Reactivate Company',
                              'Restore this company\'s access to the app?',
                              () => _companyService.reactivateCompany(actingAdminId: _adminId, companyId: c.companyId),
                            );
                          }
                        },
                  icon: Icon(c.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                      color: c.isActive ? Colors.red : Colors.green),
                  label: Text(
                    c.isActive ? 'Suspend Company' : 'Reactivate Company',
                    style: TextStyle(color: c.isActive ? Colors.red : Colors.green),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
