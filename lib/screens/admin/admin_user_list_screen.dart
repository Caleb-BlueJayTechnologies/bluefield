import 'package:flutter/material.dart';

import '../../Models/app_user.dart';
import '../../Services/admin_user_service.dart';
import '../../theme/app_theme.dart';
import 'admin_user_detail_screen.dart';

class AdminUserListScreen extends StatefulWidget {
  const AdminUserListScreen({super.key});

  @override
  State<AdminUserListScreen> createState() => _AdminUserListScreenState();
}

class _AdminUserListScreenState extends State<AdminUserListScreen> {
  final AdminUserService _userService = AdminUserService();
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  // Cached once so the search box's per-keystroke setState() doesn't
  // tear down and resubscribe this Firestore listener.
  late final Stream<List<AppUser>> _usersStream = _userService.watchAllUsers();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Users', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
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
                  hintText: 'Search by name, email, or UID...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: StreamBuilder<List<AppUser>>(
                  stream: _usersStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                    }

                    final users = snapshot.data ?? [];
                    final filtered = _searchText.isEmpty
                        ? users
                        : users
                            .where((u) =>
                                u.fullName.toLowerCase().contains(_searchText) ||
                                u.email.toLowerCase().contains(_searchText) ||
                                u.uid.toLowerCase().contains(_searchText))
                            .toList();

                    if (users.isEmpty) {
                      return const Center(child: Text('No users yet.', style: TextStyle(color: AppTheme.mutedText)));
                    }
                    if (filtered.isEmpty) {
                      return const Center(child: Text('No users match your search.', style: TextStyle(color: AppTheme.mutedText)));
                    }

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final user = filtered[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                            title: Text(user.fullName.isEmpty ? '(No name)' : user.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(user.email, style: const TextStyle(color: AppTheme.mutedText, fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => AdminUserDetailScreen(uid: user.uid)),
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
