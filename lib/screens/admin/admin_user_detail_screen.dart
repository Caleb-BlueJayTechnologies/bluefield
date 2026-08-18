import 'package:flutter/material.dart';

import '../../Models/app_user.dart';
import '../../Services/admin_user_service.dart';
import '../../theme/app_theme.dart';

class AdminUserDetailScreen extends StatefulWidget {
  final String uid;

  const AdminUserDetailScreen({super.key, required this.uid});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  final AdminUserService _userService = AdminUserService();
  late Stream<({AppUser user, String? companyName, String? role, bool? membershipActive})> _detailStream;

  @override
  void initState() {
    super.initState();
    _detailStream = _userService.watchUserDetail(widget.uid);
  }

  String _formatDate(DateTime value) => '${value.month}/${value.day}/${value.year}';

  String _roleLabel(String? role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'manager':
        return 'Manager';
      case 'employee':
        return 'Employee';
      default:
        return '—';
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
        title: const Text('User Details', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<({AppUser user, String? companyName, String? role, bool? membershipActive})>(
        stream: _detailStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                snapshot.error?.toString() ?? 'Unable to load this user.',
                style: const TextStyle(color: AppTheme.mutedText),
              ),
            );
          }

          final user = snapshot.data!.user;

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
                      Text(user.fullName.isEmpty ? '(No name)' : user.fullName,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(user.email, style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard('Account', [
                _infoRow('User ID', user.uid),
                _infoRow('Created', _formatDate(user.createdAt)),
                _infoRow('Email Verified', user.emailVerified ? 'Yes' : 'No'),
                _infoRow('Onboarding Complete', user.onboardingComplete ? 'Yes' : 'No'),
                if (user.phone?.isNotEmpty == true) _infoRow('Phone', user.phone!),
              ]),
              _sectionCard('Company Membership', [
                _infoRow('Company', snapshot.data!.companyName ?? 'Not found'),
                _infoRow('Role', _roleLabel(snapshot.data!.role)),
                _infoRow('Membership Status', snapshot.data!.membershipActive == true ? 'Active' : 'Inactive/Archived'),
              ]),
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
          SizedBox(width: 150, child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
