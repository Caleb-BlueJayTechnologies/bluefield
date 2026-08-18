import 'package:flutter/material.dart';

import '../../Models/company_model.dart';
import '../../Services/admin_company_service.dart';
import '../../theme/app_theme.dart';
import 'admin_company_detail_screen.dart';
import 'environment_indicator.dart';

/// Every company holding a locked-in pricing commitment (founding,
/// beta, or early adopter) — the promises made at signup that need to
/// be honored regardless of what current pricing looks like. Read-only:
/// changing a company's tier still happens from its own detail screen,
/// this is just a dedicated place to see the whole list at once.
class AdminFoundingCommitmentsScreen extends StatefulWidget {
  const AdminFoundingCommitmentsScreen({super.key});

  @override
  State<AdminFoundingCommitmentsScreen> createState() => _AdminFoundingCommitmentsScreenState();
}

class _AdminFoundingCommitmentsScreenState extends State<AdminFoundingCommitmentsScreen> {
  final AdminCompanyService _companyService = AdminCompanyService();
  late Stream<List<CompanyModel>> _companiesStream;

  @override
  void initState() {
    super.initState();
    _companiesStream = _companyService.watchAllCompanies();
  }

  String _tierLabel(String program) {
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
        return program;
    }
  }

  String _commitmentText(String program) {
    switch (program) {
      case CompanyPricingProgram.founding:
        return 'Free for life';
      case CompanyPricingProgram.beta:
        return 'Locked discount';
      case CompanyPricingProgram.earlyAdopter:
        return 'Locked pricing';
      case CompanyPricingProgram.legacy:
        return 'Grandfathered rate';
      default:
        return '';
    }
  }

  Color _tierColor(String program) {
    switch (program) {
      case CompanyPricingProgram.founding:
        return Colors.purple;
      case CompanyPricingProgram.beta:
        return AppTheme.blue;
      case CompanyPricingProgram.earlyAdopter:
        return Colors.teal;
      case CompanyPricingProgram.legacy:
        return Colors.brown;
      default:
        return AppTheme.mutedText;
    }
  }

  String _formatDate(DateTime value) => '${value.month}/${value.day}/${value.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Founding Commitments', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                  'Every company with a locked-in pricing commitment from signup. These promises should be honored '
                  'regardless of what current pricing looks like — changing one from here isn\'t possible on purpose; '
                  'use the company\'s own detail page if a change is genuinely needed.',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<CompanyModel>>(
                stream: _companiesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final companies = (snapshot.data ?? [])
                      .where((c) => c.pricingProgram != CompanyPricingProgram.standard)
                      .toList()
                    ..sort((a, b) => (a.customerNumber ?? 999999).compareTo(b.customerNumber ?? 999999));

                  if (companies.isEmpty) {
                    return const Center(
                      child: Text('No companies currently hold a locked pricing commitment.',
                          style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: companies.length,
                    itemBuilder: (context, index) {
                      final company = companies[index];
                      final color = _tierColor(company.pricingProgram);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.12),
                            child: Text(
                              company.customerNumber != null ? '#${company.customerNumber}' : '?',
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                          title: Text(company.companyName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                          subtitle: Text('${_tierLabel(company.pricingProgram)} — ${_commitmentText(company.pricingProgram)} • Since ${_formatDate(company.createdAt)}'),
                          trailing: const Icon(Icons.chevron_right, color: AppTheme.mutedText),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => AdminCompanyDetailScreen(companyId: company.companyId)),
                            );
                          },
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
