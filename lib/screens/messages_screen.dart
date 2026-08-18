import 'package:flutter/material.dart';

import '../Models/employee_model.dart';
import '../Models/message_thread_model.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/messaging_service.dart';
import '../theme/app_theme.dart';
import 'conversation_screen.dart';
import 'new_direct_message_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final AuthService _authService = AuthService();
  final MessagingService _messagingService = MessagingService();
  final EmployeeService _employeeService = EmployeeService();

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  String _selectedFilter = 'All';

  late Future<_MessagesReferenceData> _referenceFuture;

  // Cached once per companyId/userId so the search box's per-keystroke
  // setState() (and the filter-chip taps, same setState mechanism)
  // don't tear down and resubscribe this Firestore listener every time.
  String? _threadsStreamKey;
  Stream<List<MessageThreadModel>>? _threadsStream;

  final Map<String, String> _filterToType = const {
    'Company': ThreadType.companyWide,
    'Crew': ThreadType.crew,
    'Jobs': ThreadType.job,
    'Direct': ThreadType.direct,
  };

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

  Future<_MessagesReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId, includeArchived: true);
    final employeesById = {for (final e in employees) e.employeeId: e.employee};

    return _MessagesReferenceData(companyId: companyId, userId: profile.uid, employeesById: employeesById);
  }

  String _threadTitle(MessageThreadModel thread, _MessagesReferenceData reference) {
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

  String _threadLabel(String type) {
    switch (type) {
      case ThreadType.companyWide:
        return 'COMPANY';
      case ThreadType.crew:
        return 'CREW';
      case ThreadType.job:
        return 'JOB';
      case ThreadType.manager:
        return 'MANAGER';
      default:
        return 'DIRECT';
    }
  }

  IconData _threadIcon(String type) {
    switch (type) {
      case ThreadType.companyWide:
        return Icons.campaign;
      case ThreadType.crew:
        return Icons.groups;
      case ThreadType.job:
        return Icons.home_work_outlined;
      case ThreadType.manager:
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.person_outline;
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '';
    final now = DateTime.now();
    final isToday = value.year == now.year && value.month == now.month && value.day == now.day;
    if (isToday) {
      final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
      final minute = value.minute.toString().padLeft(2, '0');
      return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
    }
    return '${value.month}/${value.day}';
  }

  Stream<List<MessageThreadModel>> _ensureThreadsStream(_MessagesReferenceData reference) {
    final key = '${reference.companyId}::${reference.userId}';
    if (_threadsStreamKey != key || _threadsStream == null) {
      _threadsStreamKey = key;
      _threadsStream = _messagingService.watchThreadsForUser(
        companyId: reference.companyId,
        userId: reference.userId,
      );
    }
    return _threadsStream!;
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

  Future<void> _openThread(_MessagesReferenceData reference, MessageThreadModel thread) async {
    await _messagingService.markThreadRead(
      companyId: reference.companyId,
      threadId: thread.threadId,
      userId: reference.userId,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationScreen(companyId: reference.companyId, threadId: thread.threadId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Messages', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                  ),
                  IconButton(
                    tooltip: 'Archived Conversations',
                    icon: const Icon(Icons.archive_outlined, color: AppTheme.mutedText),
                    onPressed: _showArchivedThreads,
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ['All', 'Company', 'Crew', 'Jobs', 'Direct']
                              .map((label) => _filterChip(label, _selectedFilter == label))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FutureBuilder<_MessagesReferenceData>(
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
                      stream: _ensureThreadsStream(reference),
                      builder: (context, threadSnapshot) {
                        if (threadSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (threadSnapshot.hasError) {
                          return Center(
                            child: Text(threadSnapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)),
                          );
                        }

                        var threads = threadSnapshot.data ?? [];

                        if (_selectedFilter != 'All') {
                          final type = _filterToType[_selectedFilter];
                          threads = threads.where((t) => t.type == type).toList();
                        }

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
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: threads.length,
                          itemBuilder: (context, index) {
                            final thread = threads[index];
                            final unread = thread.unreadCountFor(reference.userId) > 0;

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
                              child: MessageCard(
                                icon: _threadIcon(thread.type),
                                label: _threadLabel(thread.type),
                                title: _threadTitle(thread, reference),
                                preview: thread.lastMessagePreview ?? 'No messages yet.',
                                time: _formatTime(thread.lastMessageAt),
                                unread: unread,
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
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const NewDirectMessageScreen()));
                          },
                          icon: const Icon(Icons.add_comment_outlined),
                          label: const Text('New Message'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String text, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = text),
        child: Chip(
          label: Text(text),
          backgroundColor: selected ? AppTheme.blue : const Color(0xFFEAF1F8),
          labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.darkText, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _MessagesReferenceData {
  final String companyId;
  final String userId;
  final Map<String, EmployeeModel> employeesById;

  const _MessagesReferenceData({required this.companyId, required this.userId, required this.employeesById});
}

class MessageCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;
  final String preview;
  final String time;
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback? onArchive;

  const MessageCard({
    super.key,
    required this.icon,
    required this.label,
    required this.title,
    required this.preview,
    required this.time,
    required this.unread,
    required this.onTap,
    this.onArchive,
  });

  Color get badgeColor {
    switch (label) {
      case 'COMPANY':
        return const Color(0xFFE3F2FD);
      case 'CREW':
        return const Color(0xFFE8F5E9);
      case 'JOB':
        return const Color(0xFFFFF3E0);
      case 'MANAGER':
        return const Color(0xFFEDE7F6);
      default:
        return const Color(0xFFF3E5F5);
    }
  }

  Color get iconColor {
    switch (label) {
      case 'COMPANY':
        return const Color(0xFF1565C0);
      case 'CREW':
        return const Color(0xFF2E7D32);
      case 'JOB':
        return const Color(0xFFE65100);
      case 'MANAGER':
        return const Color(0xFF5E35B1);
      default:
        return const Color(0xFF6A1B9A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(backgroundColor: badgeColor, child: Icon(icon, color: iconColor)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.bold, color: AppTheme.darkText),
              ),
            ),
            Text(
              time,
              style: TextStyle(
                fontSize: 12,
                fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                color: unread ? AppTheme.blue : AppTheme.mutedText,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(999)),
                  child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: iconColor)),
                ),
                if (unread) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppTheme.blue, borderRadius: BorderRadius.circular(999)),
                    child: const Text('NEW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: unread ? AppTheme.darkText : AppTheme.mutedText, fontWeight: unread ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
        trailing: onArchive != null
            ? IconButton(
                tooltip: 'Archive',
                icon: const Icon(Icons.archive_outlined, color: AppTheme.mutedText),
                onPressed: onArchive,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
