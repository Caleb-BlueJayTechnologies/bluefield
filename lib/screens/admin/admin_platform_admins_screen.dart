import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../Firebase/firestore_schema.dart';
import '../../Models/platform_admin_model.dart';
import '../../Services/platform_admin_service.dart';
import '../../theme/app_theme.dart';

class AdminPlatformAdminsScreen extends StatefulWidget {
  const AdminPlatformAdminsScreen({super.key});

  @override
  State<AdminPlatformAdminsScreen> createState() => _AdminPlatformAdminsScreenState();
}

class _AdminPlatformAdminsScreenState extends State<AdminPlatformAdminsScreen> {
  final PlatformAdminService _adminService = PlatformAdminService();
  late Stream<List<PlatformAdminModel>> _adminsStream;
  bool _isActing = false;

  @override
  void initState() {
    super.initState();
    _adminsStream = _adminService.watchAllAdmins();
  }

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _roleLabel(String role) {
    switch (role) {
      case FSPlatformAdminRole.superAdmin:
        return 'Super Admin';
      case FSPlatformAdminRole.supportAdmin:
        return 'Support Admin';
      case FSPlatformAdminRole.billingAdmin:
        return 'Billing Admin';
      case FSPlatformAdminRole.productAdmin:
        return 'Product Admin';
      default:
        return role;
    }
  }

  Future<void> _openAddAdminDialog() async {
    final emailController = TextEditingController();
    var selectedRole = FSPlatformAdminRole.supportAdmin;
    ({String uid, String email, String displayName})? found;
    String? lookupError;
    var isLookingUp = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Platform Admin'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email of an existing BlueField account'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: isLookingUp
                            ? null
                            : () async {
                                setDialogState(() {
                                  isLookingUp = true;
                                  lookupError = null;
                                  found = null;
                                });
                                final result = await _adminService.findUserByEmail(emailController.text);
                                setDialogState(() {
                                  isLookingUp = false;
                                  found = result;
                                  if (result == null) {
                                    lookupError = 'No BlueField account found with that email.';
                                  }
                                });
                              },
                        child: Text(isLookingUp ? 'Looking up...' : 'Look Up'),
                      ),
                    ),
                    if (lookupError != null) ...[
                      const SizedBox(height: 8),
                      Text(lookupError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                    if (found != null) ...[
                      const SizedBox(height: 12),
                      Text('Found: ${found!.displayName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: [
                          FSPlatformAdminRole.superAdmin,
                          FSPlatformAdminRole.supportAdmin,
                          FSPlatformAdminRole.billingAdmin,
                          FSPlatformAdminRole.productAdmin,
                        ].map((r) => DropdownMenuItem(value: r, child: Text(_roleLabel(r)))).toList(),
                        onChanged: (value) => setDialogState(() => selectedRole = value ?? selectedRole),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton(
                  onPressed: found == null
                      ? null
                      : () async {
                          Navigator.pop(context);
                          setState(() => _isActing = true);
                          try {
                            await _adminService.grantAdminAccess(
                              actingAdminId: _myUid,
                              targetUid: found!.uid,
                              email: found!.email,
                              displayName: found!.displayName,
                              role: selectedRole,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text('${found!.displayName} added as ${_roleLabel(selectedRole)}.')));
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                          } finally {
                            if (mounted) setState(() => _isActing = false);
                          }
                        },
                  child: const Text('Grant Access'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _changeRole(PlatformAdminModel admin, String newRole) async {
    setState(() => _isActing = true);
    try {
      await _adminService.updateAdminRole(actingAdminId: _myUid, targetAdminId: admin.adminId, newRole: newRole);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _toggleActive(PlatformAdminModel admin) async {
    setState(() => _isActing = true);
    try {
      await _adminService.setAdminActive(
        actingAdminId: _myUid,
        targetAdminId: admin.adminId,
        active: !admin.active,
      );
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
        title: const Text('Platform Admins', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<PlatformAdminModel>>(
                  stream: _adminsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                    }

                    final admins = snapshot.data ?? [];
                    if (admins.isEmpty) {
                      return const Center(child: Text('No platform admins found.', style: TextStyle(color: AppTheme.mutedText)));
                    }

                    return ListView.builder(
                      itemCount: admins.length,
                      itemBuilder: (context, index) {
                        final admin = admins[index];
                        final isMe = admin.adminId == _myUid;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: admin.active ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                                  child: Icon(
                                    Icons.admin_panel_settings_outlined,
                                    color: admin.active ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isMe ? '${admin.displayName} (You)' : admin.displayName,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Text(admin.email, style: const TextStyle(color: AppTheme.mutedText, fontSize: 12)),
                                      const SizedBox(height: 6),
                                      DropdownButton<String>(
                                        value: [
                                          FSPlatformAdminRole.superAdmin,
                                          FSPlatformAdminRole.supportAdmin,
                                          FSPlatformAdminRole.billingAdmin,
                                          FSPlatformAdminRole.productAdmin,
                                        ].contains(admin.role)
                                            ? admin.role
                                            : null,
                                        hint: Text('Unknown role: ${admin.role}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                                        underline: const SizedBox.shrink(),
                                        isDense: true,
                                        items: [
                                          FSPlatformAdminRole.superAdmin,
                                          FSPlatformAdminRole.supportAdmin,
                                          FSPlatformAdminRole.billingAdmin,
                                          FSPlatformAdminRole.productAdmin,
                                        ]
                                            .map((r) =>
                                                DropdownMenuItem(value: r, child: Text(_roleLabel(r), style: const TextStyle(fontSize: 13))))
                                            .toList(),
                                        onChanged: _isActing ? null : (value) => value == null ? null : _changeRole(admin, value),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: admin.active,
                                  onChanged: (isMe || _isActing) ? null : (_) => _toggleActive(admin),
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isActing ? null : _openAddAdminDialog,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add Platform Admin'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
