import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../Models/company_model.dart';
import '../../Models/pricing_tier_model.dart';
import '../../Services/pricing_tier_service.dart';
import '../../theme/app_theme.dart';
import 'environment_indicator.dart';

class AdminPricingTiersScreen extends StatefulWidget {
  const AdminPricingTiersScreen({super.key});

  @override
  State<AdminPricingTiersScreen> createState() => _AdminPricingTiersScreenState();
}

class _AdminPricingTiersScreenState extends State<AdminPricingTiersScreen> {
  final PricingTierService _service = PricingTierService();
  late Stream<List<PricingTierModel>> _tiersStream;
  bool _isActing = false;

  static const _knownTierKeys = [
    CompanyPricingProgram.founding,
    CompanyPricingProgram.beta,
    CompanyPricingProgram.earlyAdopter,
    CompanyPricingProgram.legacy,
    CompanyPricingProgram.standard,
  ];

  @override
  void initState() {
    super.initState();
    _tiersStream = _service.watchAllTiers();
  }

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _defaultLabel(String tierKey) {
    switch (tierKey) {
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

  Future<void> _openEditDialog(String tierKey, PricingTierModel? existing) async {
    final nameController = TextEditingController(text: existing?.displayName ?? _defaultLabel(tierKey));
    final priceController = TextEditingController(text: existing?.monthlyPrice.toStringAsFixed(2) ?? '0.00');
    final descController = TextEditingController(text: existing?.description ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_defaultLabel(tierKey)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Display Name')),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Monthly Price', prefixText: '\$'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'What does this tier include?'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              const Text(
                'Informational only — nothing charges money based on this yet.',
                style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    final price = double.tryParse(priceController.text.trim());
    if (price == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price.')));
      return;
    }

    setState(() => _isActing = true);
    try {
      await _service.saveTier(
        actingAdminId: _myUid,
        tierKey: tierKey,
        displayName: nameController.text.trim(),
        monthlyPrice: price,
        description: descController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tier saved.')));
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
        title: const Text('Pricing Configuration', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const EnvironmentIndicator(),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'What each pricing tier actually means. Informational reference only — there\'s no billing '
                  'integration wired up yet, so nothing here charges money.',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<PricingTierModel>>(
                stream: _tiersStream,
                builder: (context, snapshot) {
                  final configuredByKey = {for (final t in snapshot.data ?? <PricingTierModel>[]) t.tierKey: t};

                  return ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: _knownTierKeys.length,
                    itemBuilder: (context, index) {
                      final tierKey = _knownTierKeys[index];
                      final existing = configuredByKey[tierKey];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        child: ListTile(
                          title: Text(existing?.displayName ?? _defaultLabel(tierKey),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                          subtitle: Text(
                            existing == null
                                ? 'Not yet configured'
                                : '\$${existing.monthlyPrice.toStringAsFixed(2)}/mo — ${existing.description.isEmpty ? 'No description' : existing.description}',
                            style: TextStyle(color: existing == null ? Colors.orange : AppTheme.mutedText),
                          ),
                          trailing: TextButton(
                            onPressed: _isActing ? null : () => _openEditDialog(tierKey, existing),
                            child: Text(existing == null ? 'Configure' : 'Edit'),
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
