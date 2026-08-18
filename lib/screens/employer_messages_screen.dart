import 'package:flutter/material.dart';

import '../Models/employee_model.dart';
import '../Models/message_thread_model.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/messaging_service.dart';
import '../theme/app_theme.dart';
import 'conversation_screen.dart';

class EmployerMessagesScreen extends StatefulWidget {
  const EmployerMessagesScreen({super.key});

  @override
  State<EmployerMessagesScreen> createState() => _EmployerMessagesScreenState();
}

class _EmployerMessagesScreenState extends State<EmployerMessagesScreen> {
  final AuthService _authService = AuthService();
  final MessagingService _messagingService = MessagingService();
  final EmployeeService _employeeService = EmployeeService();

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  late Future<_EmployerMessagesData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_EmployerMessagesData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId);
    final employeesById = {for (final e in employees) e.employeeId: e.employee};

    return _EmployerMessagesData(
      companyId: companyId,
      userId: profile.uid,
      employeesById: employeesById,
      employees: employees.map((e) => e.employee).where((e) => e.employeeId != profile.uid).toList(),
    );
  }

  String _threadTitle(MessageThreadModel thread, _EmployerMessagesData reference) {
    if (thread.title?.trim().isNotEmpty == true) return thread.title!;

    if (thread.type == ThreadType.direct) {
      final otherId = thread.participantUserIds.firstWhere((id) => id != reference.userId, orElse: () => '');
      return reference.employeesById[otherId]?.fullName ?? 'Direct Message';
    }

    switch (thread.type) {
      case ThreadType.companyWide:
        return 'Company Announcements';
      case ThreadType.manager:
        return 'Manager Discussion';
      case ThreadType.crew:
        return 'Crew Chat';
      case ThreadType.job:
        return 'Job Discussion';
      default:
        return 'Conversation';
    }
  }

  String _threadSubtitle(MessageThreadModel thread) {
    switch (thread.type) {
      case ThreadType.direct:
        return 'Direct Message';
      case ThreadType.companyWide:
        return '${thread.participantUserIds.length} Employees';
      case ThreadType.crew:
        return '${thread.participantUserIds.length} Members';
      default:
        return '${thread.participantUserIds.length} Participants';
    }
  }

  IconData _threadIcon(String type) {
    switch (type) {
      case ThreadType.companyWide:
        return Icons.campaign_outlined;
      case ThreadType.crew:
        return Icons.groups_outlined;
      case ThreadType.job:
        return Icons.home_work_outlined;
      case ThreadType.manager:
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.person_outline;
    }
  }

  Future<void> _showArchivedThreads() async {
    final reference = await _referenceFuture;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Archived Conversations',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                const SizedBox(height: 4),
                const Text('Nothing is deleted — restore any of these to see it in your list again.',
                    style: TextStyle(fontSize: 13, color: AppTheme.mutedText)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                  child: StreamBuilder<List<MessageThreadModel>>(
                    stream: _messagingService.watchArchivedThreadsForUser(
                      companyId: reference.companyId,
                      userId: reference.userId,
                    ),
                    builder: (context, snapshot) {
                      final archived = snapshot.data ?? [];
                      if (archived.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('No archived conversations.', style: TextStyle(color: AppTheme.mutedText)),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: archived.length,
                        itemBuilder: (context, index) {
                          final thread = archived[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(_threadIcon(thread.type), color: AppTheme.mutedText),
                            title: Text(_threadTitle(thread, reference)),
                            subtitle: Text(thread.lastMessagePreview ?? 'No messages yet.', maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: TextButton(
                              onPressed: () => _messagingService.unarchiveThreadForUser(
                                companyId: reference.companyId,
                                threadId: thread.threadId,
                                userId: reference.userId,
                              ),
                              child: const Text('Restore'),
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
      },
    );
  }

  Future<void> _openThread(_EmployerMessagesData reference, MessageThreadModel thread) async {
    await _messagingService.markThreadRead(companyId: reference.companyId, threadId: thread.threadId, userId: reference.userId);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationScreen(companyId: reference.companyId, threadId: thread.threadId),
      ),
    );
  }

  Future<void> _startNewMessage(_EmployerMessagesData reference) async {
    final selected = await showModalBottomSheet<EmployeeModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('New Message', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                const SizedBox(height: 12),
                if (reference.employees.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No other employees to message.', style: TextStyle(color: AppTheme.mutedText)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: reference.employees.length,
                      itemBuilder: (context, index) {
                        final employee = reference.employees[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(employee.fullName),
                          onTap: () => Navigator.pop(context, employee),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    try {
      final threadId = await _messagingService.getOrCreateDirectThread(
        companyId: reference.companyId,
        userA: reference.userId,
        userB: selected.employeeId,
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConversationScreen(companyId: reference.companyId, threadId: threadId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
        title: const Text('Messages', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Archived Conversations',
            icon: const Icon(Icons.archive_outlined),
            onPressed: _showArchivedThreads,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search conversations...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FutureBuilder<_EmployerMessagesData>(
                  future: _referenceFuture,
                  builder: (context, refSnapshot) {
                    if (refSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (refSnapshot.hasError || !refSnapshot.hasData) {
                      return Center(
                        child: Text(
                          refSnapshot.error?.toString() ?? 'Unable to load messages.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      );
                    }

                    final reference = refSnapshot.data!;

                    return StreamBuilder<List<MessageThreadModel>>(
                      stream: _messagingService.watchThreadsForUser(companyId: reference.companyId, userId: reference.userId),
                      builder: (context, threadSnapshot) {
                        if (threadSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (threadSnapshot.hasError) {
                          return Center(child: Text(threadSnapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                        }

                        var threads = threadSnapshot.data ?? [];

                        if (_searchText.isNotEmpty) {
                          threads = threads.where((t) {
                            final title = _threadTitle(t, reference).toLowerCase();
                            final preview = (t.lastMessagePreview ?? '').toLowerCase();
                            return title.contains(_searchText) || preview.contains(_searchText);
                          }).toList();
                        }

                        if (threads.isEmpty) {
                          return const Center(
                            child: Text('No conversations yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                          );
                        }

                        return ListView.builder(
                          itemCount: threads.length,
                          itemBuilder: (context, index) {
                            final thread = threads[index];

                            return Dismissible(
                              key: ValueKey(thread.threadId),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(16)),
                                child: const Icon(Icons.archive_outlined, color: Colors.white),
                              ),
                              confirmDismiss: (_) async {
                                await _messagingService.archiveThreadForUser(
                                  companyId: reference.companyId,
                                  threadId: thread.threadId,
                                  userId: reference.userId,
                                );
                                if (!context.mounted) return false;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Conversation archived.'),
                                    action: SnackBarAction(
                                      label: 'Undo',
                                      onPressed: () => _messagingService.unarchiveThreadForUser(
                                        companyId: reference.companyId,
                                        threadId: thread.threadId,
                                        userId: reference.userId,
                                      ),
                                    ),
                                  ),
                                );
                                return true;
                              },
                              child: ConversationCard(
                                title: _threadTitle(thread, reference),
                                subtitle: _threadSubtitle(thread),
                                preview: thread.lastMessagePreview ?? 'No messages yet.',
                                unreadCount: thread.unreadCountFor(reference.userId),
                                icon: _threadIcon(thread.type),
                                onTap: () => _openThread(reference, thread),
                                onArchive: () async {
                                  await _messagingService.archiveThreadForUser(
                                    companyId: reference.companyId,
                                    threadId: thread.threadId,
                                    userId: reference.userId,
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Conversation archived.'),
                                      action: SnackBarAction(
                                        label: 'Undo',
                                        onPressed: () => _messagingService.unarchiveThreadForUser(
                                          companyId: reference.companyId,
                                          threadId: thread.threadId,
                                          userId: reference.userId,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
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
                child: FutureBuilder<_EmployerMessagesData>(
                  future: _referenceFuture,
                  builder: (context, snapshot) {
                    return FilledButton.icon(
                      onPressed: snapshot.hasData ? () => _startNewMessage(snapshot.data!) : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('New Message'),
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

class _EmployerMessagesData {
  final String companyId;
  final String userId;
  final Map<String, EmployeeModel> employeesById;
  final List<EmployeeModel> employees;

  const _EmployerMessagesData({
    required this.companyId,
    required this.userId,
    required this.employeesById,
    required this.employees,
  });
}

class ConversationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String preview;
  final int unreadCount;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onArchive;

  const ConversationCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.unreadCount,
    required this.icon,
    required this.onTap,
    this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(backgroundColor: AppTheme.blue.withOpacity(0.12), child: Icon(icon, color: AppTheme.blue)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: const TextStyle(color: AppTheme.mutedText)),
            const SizedBox(height: 4),
            Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.mutedText)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppTheme.blue, borderRadius: BorderRadius.circular(999)),
                child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            if (onArchive != null)
              IconButton(
                tooltip: 'Archive',
                icon: const Icon(Icons.archive_outlined, color: AppTheme.mutedText),
                onPressed: onArchive,
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
