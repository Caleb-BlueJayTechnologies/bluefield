import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/messaging_service.dart';
import '../theme/app_theme.dart';
import 'conversation_screen.dart';

/// Contact picker for starting a new direct message. Rather than
/// letting an employee message literally anyone in the company, the
/// allowed list is scoped to two groups:
///   - Every owner/manager — management should always be reachable
///     directly, regardless of crew.
///   - Anyone sharing the current user's crew — actual day-to-day
///     co-workers. An employee with no crew assigned only sees
///     management in their list, not the entire employee roster.
/// Owners/managers themselves get the full roster (see
/// _ContactsReferenceData.isManagement below) since restricting who
/// leadership can reach out to isn't the goal here.
class NewDirectMessageScreen extends StatefulWidget {
  const NewDirectMessageScreen({super.key});

  @override
  State<NewDirectMessageScreen> createState() => _NewDirectMessageScreenState();
}

class _NewDirectMessageScreenState extends State<NewDirectMessageScreen> {
  final AuthService _authService = AuthService();
  final EmployeeService _employeeService = EmployeeService();
  final MessagingService _messagingService = MessagingService();

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  bool _isOpeningThread = false;

  late Future<_ContactsReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_ContactsReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final all = await _employeeService.getEmployeesByCompany(companyId: companyId, includeArchived: false);
    final self = all.where((e) => e.employeeId == profile.uid).toList();
    final selfCrewIds = self.isNotEmpty ? self.first.employee.crewIds : const <String>[];
    final isManagement = self.isNotEmpty && (self.first.role == FSRoles.owner || self.first.role == FSRoles.manager);

    final allowed = all.where((e) {
      if (e.employeeId == profile.uid) return false; // never message yourself
      if (isManagement) return true; // leadership can reach anyone
      final theyAreManagement = e.role == FSRoles.owner || e.role == FSRoles.manager;
      final sharesCrew = e.employee.crewIds.any(selfCrewIds.contains);
      return theyAreManagement || sharesCrew;
    }).toList()
      ..sort((a, b) => a.employee.fullName.toLowerCase().compareTo(b.employee.fullName.toLowerCase()));

    return _ContactsReferenceData(companyId: companyId, userId: profile.uid, allowedContacts: allowed);
  }

  Future<void> _openThreadWith(_ContactsReferenceData reference, EmployeeWithMembership contact) async {
    if (_isOpeningThread) return;
    setState(() => _isOpeningThread = true);

    try {
      final threadId = await _messagingService.getOrCreateDirectThread(
        companyId: reference.companyId,
        userA: reference.userId,
        userB: contact.employeeId,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ConversationScreen(companyId: reference.companyId, threadId: threadId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isOpeningThread = false);
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case FSRoles.owner:
        return 'Owner';
      case FSRoles.manager:
        return 'Manager';
      default:
        return 'Employee';
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
        title: const Text('New Message', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                  hintText: 'Search people...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<_ContactsReferenceData>(
                  future: _referenceFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return Center(
                        child: Text(
                          snapshot.error?.toString() ?? 'Unable to load contacts.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      );
                    }

                    final reference = snapshot.data!;
                    final filtered = _searchText.isEmpty
                        ? reference.allowedContacts
                        : reference.allowedContacts
                            .where((c) => c.employee.fullName.toLowerCase().contains(_searchText))
                            .toList();

                    if (reference.allowedContacts.isEmpty) {
                      return const Center(
                        child: Text(
                          'No one is available to message yet.\nManagement and your crew will show up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.mutedText, fontSize: 15),
                        ),
                      );
                    }
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text('No one matches your search.', style: TextStyle(color: AppTheme.mutedText)),
                      );
                    }

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final contact = filtered[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                            title: Text(contact.employee.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(_roleLabel(contact.role), style: const TextStyle(color: AppTheme.mutedText)),
                            trailing: _isOpeningThread
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.chevron_right),
                            onTap: _isOpeningThread ? null : () => _openThreadWith(reference, contact),
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

class _ContactsReferenceData {
  final String companyId;
  final String userId;
  final List<EmployeeWithMembership> allowedContacts;

  const _ContactsReferenceData({
    required this.companyId,
    required this.userId,
    required this.allowedContacts,
  });
}
