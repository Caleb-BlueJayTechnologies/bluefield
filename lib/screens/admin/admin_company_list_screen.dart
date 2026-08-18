import 'package:flutter/material.dart';

import '../../Models/company_model.dart';
import '../../Services/admin_company_service.dart';
import '../../theme/app_theme.dart';
import 'admin_company_detail_screen.dart';

class AdminCompanyListScreen extends StatefulWidget {
  const AdminCompanyListScreen({super.key});

  @override
  State<AdminCompanyListScreen> createState() => _AdminCompanyListScreenState();
}

class _AdminCompanyListScreenState extends State<AdminCompanyListScreen> {
  final AdminCompanyService _companyService = AdminCompanyService();
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  // Cached so the search box's per-keystroke setState() doesn't tear
  // down and resubscribe these Firestore listeners — the main list
  // stream, and one per-row employee-count stream (keyed by
  // companyId, since each row would otherwise get a brand-new Stream
  // object — and therefore a forced resubscribe — every time the
  // outer rebuild causes itemBuilder to run again).
  Stream<List<CompanyModel>>? _companiesStream;
  final Map<String, Stream<int>> _employeeCountStreams = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }

  Stream<List<CompanyModel>> _ensureCompaniesStream() {
    return _companiesStream ??= _companyService.watchAllCompanies();
  }

  Stream<int> _ensureEmployeeCountStream(String companyId) {
    return _employeeCountStreams.putIfAbsent(
      companyId,
      () => _companyService.watchEmployeeCount(companyId),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Companies', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by company name or ID...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: StreamBuilder<List<CompanyModel>>(
                  stream: _ensureCompaniesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                    }

                    final companies = snapshot.data ?? [];
                    final filtered = _searchText.isEmpty
                        ? companies
                        : companies
                            .where((c) =>
                                c.companyName.toLowerCase().contains(_searchText) ||
                                c.companyId.toLowerCase().contains(_searchText))
                            .toList();

                    if (companies.isEmpty) {
                      return const Center(child: Text('No companies yet.', style: TextStyle(color: AppTheme.mutedText)));
                    }
                    if (filtered.isEmpty) {
                      return const Center(child: Text('No companies match your search.', style: TextStyle(color: AppTheme.mutedText)));
                    }

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final company = filtered[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: company.isActive ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                              child: Icon(
                                company.isActive ? Icons.business_outlined : Icons.block_outlined,
                                color: company.isActive ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                              ),
                            ),
                            title: Row(
                              children: [
                                Flexible(child: Text(company.companyName, style: const TextStyle(fontWeight: FontWeight.bold))),
                                if (company.isInternalAccount) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.verified, size: 14, color: AppTheme.blue),
                                ],
                                if (company.isTestCompany) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.science_outlined, size: 14, color: AppTheme.mutedText),
                                ],
                              ],
                            ),
                            subtitle: StreamBuilder<int>(
                              stream: _ensureEmployeeCountStream(company.companyId),
                              builder: (context, empSnapshot) {
                                final count = empSnapshot.data ?? 0;
                                return Text(
                                  '${company.companyId} • $count Employee${count == 1 ? '' : 's'} • ${_pricingLabel(company.pricingProgram)}',
                                  style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
                                );
                              },
                            ),
                            trailing: const Icon(Icons.chevron_right),
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
      ),
    );
  }
}
