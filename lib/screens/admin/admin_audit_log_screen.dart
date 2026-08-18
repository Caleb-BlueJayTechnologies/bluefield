import 'package:flutter/material.dart';

import '../../Models/audit_log_model.dart';
import '../../Services/audit_log_service.dart';
import '../../Services/platform_admin_service.dart';
import '../../theme/app_theme.dart';

class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  final AuditLogService _auditLogService = AuditLogService();
  final PlatformAdminService _adminService = PlatformAdminService();
  final TextEditingController _searchController = TextEditingController();

  String _searchText = '';
  late Future<Map<String, String>> _adminNamesFuture;

  // Cached once so the search box's per-keystroke setState() doesn't
  // tear down and resubscribe this Firestore listener.
  late final Stream<List<AuditLogEntry>> _entriesStream = _auditLogService.watchRecentEntries();

  @override
  void initState() {
    super.initState();
    _adminNamesFuture = _loadAdminNames();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _loadAdminNames() async {
    final admins = await _adminService.getAllAdmins();
    return {for (final a in admins) a.adminId: a.displayName};
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'company.suspend':
        return 'Suspended company';
      case 'company.reactivate':
        return 'Reactivated company';
      case 'company.setInternal':
        return 'Changed internal-account flag';
      case 'company.setTest':
        return 'Changed test-company flag';
      case 'company.updateNotes':
        return 'Updated internal notes';
      case 'company.changePricingProgram':
        return 'Changed pricing program';
      case 'platformAdmin.grant':
        return 'Granted platform admin access';
      case 'platformAdmin.changeRole':
        return 'Changed platform admin role';
      case 'platformAdmin.activate':
        return 'Reactivated platform admin';
      case 'platformAdmin.deactivate':
        return 'Deactivated platform admin';
      case 'killSwitch.create':
        return 'Created kill switch';
      case 'killSwitch.activate':
        return 'Activated kill switch';
      case 'killSwitch.deactivate':
        return 'Deactivated kill switch';
      case 'killSwitch.delete':
        return 'Deleted kill switch';
      default:
        return action;
    }
  }

  IconData _actionIcon(String action) {
    if (action.startsWith('company.suspend')) return Icons.block_outlined;
    if (action.startsWith('company.reactivate')) return Icons.check_circle_outline;
    if (action.startsWith('company.')) return Icons.business_outlined;
    if (action.startsWith('platformAdmin.')) return Icons.admin_panel_settings_outlined;
    if (action.startsWith('killSwitch.')) return Icons.power_settings_new_outlined;
    return Icons.history_outlined;
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.month}/${value.day}/${value.year} • $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Audit Log', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                  hintText: 'Search admin, company, or action...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<Map<String, String>>(
                  future: _adminNamesFuture,
                  builder: (context, namesSnapshot) {
                    final adminNamesById = namesSnapshot.data ?? {};

                    return StreamBuilder<List<AuditLogEntry>>(
                      stream: _entriesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                        }

                        final entries = snapshot.data ?? [];
                        final filtered = _searchText.isEmpty
                            ? entries
                            : entries.where((e) {
                                final adminName = (adminNamesById[e.adminId] ?? e.adminId).toLowerCase();
                                return adminName.contains(_searchText) ||
                                    e.targetName.toLowerCase().contains(_searchText) ||
                                    e.action.toLowerCase().contains(_searchText);
                              }).toList();

                        if (entries.isEmpty) {
                          return const Center(child: Text('No admin actions logged yet.', style: TextStyle(color: AppTheme.mutedText)));
                        }
                        if (filtered.isEmpty) {
                          return const Center(child: Text('No entries match your search.', style: TextStyle(color: AppTheme.mutedText)));
                        }

                        return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            final adminName = adminNamesById[entry.adminId] ?? entry.adminId;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: ListTile(
                                leading: Icon(_actionIcon(entry.action), color: AppTheme.blue),
                                title: Text(_actionLabel(entry.action), style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${entry.targetName} • by $adminName', style: const TextStyle(fontSize: 12)),
                                    if (entry.oldValue != null || entry.newValue != null)
                                      Text(
                                        [
                                          if (entry.oldValue != null) 'from: ${entry.oldValue}',
                                          if (entry.newValue != null) 'to: ${entry.newValue}',
                                        ].join('  '),
                                        style: const TextStyle(fontSize: 11, color: AppTheme.mutedText),
                                      ),
                                    Text(_formatDateTime(entry.createdAt), style: const TextStyle(fontSize: 11, color: AppTheme.mutedText)),
                                  ],
                                ),
                              ),
                            );
                          },
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
