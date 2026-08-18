import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/employee_model.dart';
import '../Models/message_thread_model.dart';
import '../Services/employee_service.dart';
import '../Services/messaging_service.dart';
import '../theme/app_theme.dart';

class ConversationScreen extends StatefulWidget {
  final String companyId;
  final String threadId;

  const ConversationScreen({super.key, required this.companyId, required this.threadId});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const int _pageSize = 30;
  // Trigger the next older-history fetch once the user scrolls within
  // this many pixels of the "top" (which, under reverse:true, is
  // maxScrollExtent) — fetching a little before they physically hit
  // the end keeps the load feeling seamless instead of causing a
  // visible pause once they're already there.
  static const double _loadMoreThreshold = 400;

  final MessagingService _messagingService = MessagingService();
  final EmployeeService _employeeService = EmployeeService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isSending = false;
  bool _isLoadingOlder = false;
  bool _hasMoreOlder = true;

  // Accumulates every older page fetched so far — never cleared, never
  // trimmed. This is what "keeps history intact" while scrolling: the
  // DATA stays in memory permanently once loaded; only the on-screen
  // WIDGETS are virtualized by ListView.builder itself (Flutter never
  // builds widgets for list items that aren't near the viewport,
  // which is the actual "unload/reload as you scroll" behavior this
  // was asking for — no custom eviction logic needed on top of it).
  final List<MessageWithDoc> _olderMessages = [];

  // Cached on every StreamBuilder rebuild so the scroll listener (which
  // has no direct access to the stream's latest snapshot) always has
  // an up-to-date cursor to page backward from the first time.
  List<MessageWithDoc> _currentLiveMessages = [];

  late Future<Map<String, EmployeeModel>> _employeesFuture;
  // Only ever non-empty for platformSupport threads — a BlueJay admin
  // sending a message here has no entry in the company's employee
  // roster at all, so their display name needs a separate lookup or
  // it falls back to 'Unknown'.
  late Future<Map<String, String>> _adminNamesFuture;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _employeesFuture = _loadEmployees();
    _adminNamesFuture = _loadAdminNames();
    _markRead();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<Map<String, EmployeeModel>> _loadEmployees() async {
    final employees = await _employeeService.getEmployeesByCompany(companyId: widget.companyId, includeArchived: true);
    return {for (final e in employees) e.employeeId: e.employee};
  }

  /// Resolves display names for company members who aren't in the
  /// employees collection — this is specifically owners (who never
  /// get an employee record, only a membership) and any manager in
  /// the same situation. Previously this queried BlueJay's own
  /// platform admin roster by mistake, which has nothing to do with
  /// company owners — that's why an owner's own name (and their sent
  /// messages) showed as "Unknown" instead of their actual name.
  Future<Map<String, String>> _loadAdminNames() async {
    final membershipsSnapshot = await FirebaseFirestore.instance
        .collection(FSCollections.companies)
        .doc(widget.companyId)
        .collection(FSCompanySub.memberships)
        .get();

    // One user-doc lookup per member, fired concurrently instead of
    // awaited one at a time — each lookup is independent of the others.
    final userDocs = await Future.wait(membershipsSnapshot.docs.map(
      (doc) => FirebaseFirestore.instance.collection(FSCollections.users).doc(doc.id).get(),
    ));

    final names = <String, String>{};
    for (final userDoc in userDocs) {
      final data = userDoc.data();
      if (data == null) continue;
      final firstName = data['firstName']?.toString() ?? '';
      final lastName = data['lastName']?.toString() ?? '';
      final fullName = '$firstName $lastName'.trim();
      if (fullName.isNotEmpty) names[userDoc.id] = fullName;
    }
    return names;
  }

  Future<void> _markRead() async {
    final userId = _currentUserId;
    if (userId == null) return;
    await _messagingService.markThreadRead(companyId: widget.companyId, threadId: widget.threadId, userId: userId);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadOlderMessages();
    }
  }

  /// Uses [_currentLiveMessages] to find the correct starting cursor
  /// the very first time this is called (before any older page has
  /// been fetched yet). Every subsequent call pages further back from
  /// the last older message already in memory, independent of
  /// whatever's happening on the live end of the conversation.
  Future<void> _loadOlderMessages() async {
    if (_isLoadingOlder || !_hasMoreOlder) return;

    final cursor = _olderMessages.isNotEmpty
        ? _olderMessages.last.doc
        : (_currentLiveMessages.isNotEmpty ? _currentLiveMessages.last.doc : null);
    if (cursor == null) return;

    setState(() => _isLoadingOlder = true);

    try {
      final page = await _messagingService.getOlderMessages(
        companyId: widget.companyId,
        threadId: widget.threadId,
        beforeDoc: cursor,
        limit: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _olderMessages.addAll(page);
        _hasMoreOlder = page.length == _pageSize;
      });
    } catch (_) {
      // A failed page fetch just means the next scroll-triggered
      // attempt retries — no user-facing error needed for something
      // this transient/retryable.
    } finally {
      if (mounted) setState(() => _isLoadingOlder = false);
    }
  }

  String _threadTitle(MessageThreadModel? thread, Map<String, EmployeeModel> employeesById, bool isEmployeesLoading) {
    if (thread == null) return '';
    if (thread.title?.trim().isNotEmpty == true) return thread.title!;

    if (thread.type == ThreadType.direct) {
      final otherId = thread.participantUserIds.firstWhere((id) => id != _currentUserId, orElse: () => '');
      final resolvedName = employeesById[otherId]?.fullName;
      if (resolvedName != null) return resolvedName;
      // Still waiting on the employee lookup — show nothing rather
      // than a wrong placeholder ('Direct Message') that then gets
      // replaced a moment later once the real name resolves. That
      // replace-after-a-flash was the actual reported bug.
      return isEmployeesLoading ? '' : 'Direct Message';
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

  String _threadSubtitle(MessageThreadModel? thread) {
    if (thread == null) return '';
    return '${thread.participantUserIds.length} Member${thread.participantUserIds.length == 1 ? '' : 's'}';
  }

  Future<void> _showMembersList(MessageThreadModel thread) async {
    final employeesById = await _employeesFuture;
    final adminNamesById = await _adminNamesFuture;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${thread.participantUserIds.length} Member${thread.participantUserIds.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: thread.participantUserIds.length,
                    itemBuilder: (context, index) {
                      final userId = thread.participantUserIds[index];
                      final name = employeesById[userId]?.fullName ?? adminNamesById[userId] ?? 'Unknown';
                      final isMe = userId == _currentUserId;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(isMe ? '$name (You)' : name),
                        trailing: isMe ? null : const Icon(Icons.chevron_right, color: AppTheme.mutedText),
                        onTap: isMe ? null : () => _openDirectMessageWith(userId),
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

  Future<void> _openDirectMessageWith(String otherUserId) async {
    final myUserId = _currentUserId;
    if (myUserId == null) return;

    Navigator.pop(context); // close the members sheet first

    try {
      final threadId = await _messagingService.getOrCreateDirectThread(
        companyId: widget.companyId,
        userA: myUserId,
        userB: otherUserId,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ConversationScreen(companyId: widget.companyId, threadId: threadId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _send() async {
    final userId = _currentUserId;
    final body = _messageController.text.trim();
    if (userId == null || body.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      await _messagingService.sendMessage(
        companyId: widget.companyId,
        threadId: widget.threadId,
        senderUserId: userId,
        body: body,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatTime(DateTime value) {
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: PreferredSize(
        // Both the title (name/subtitle) and the actions (View Members
        // button) need the same thread doc — this used to subscribe to
        // watchThread() twice, once per widget, opening two identical
        // Firestore listeners for the same document. One StreamBuilder
        // now feeds both.
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: StreamBuilder<MessageThreadModel?>(
          stream: _messagingService.watchThread(companyId: widget.companyId, threadId: widget.threadId),
          builder: (context, threadSnapshot) {
            final thread = threadSnapshot.data;

            return AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              surfaceTintColor: Colors.white,
              title: FutureBuilder<Map<String, EmployeeModel>>(
                future: _employeesFuture,
                builder: (context, empSnapshot) {
                  final employeesById = empSnapshot.data ?? {};
                  final isEmployeesLoading = empSnapshot.connectionState == ConnectionState.waiting;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_threadTitle(thread, employeesById, isEmployeesLoading), style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
                      Text(_threadSubtitle(thread), style: const TextStyle(fontSize: 12, color: AppTheme.mutedText)),
                    ],
                  );
                },
              ),
              actions: [
                if (thread != null)
                  IconButton(
                    tooltip: 'View Members',
                    icon: const Icon(Icons.people_outline),
                    onPressed: () => _showMembersList(thread),
                  ),
                const SizedBox(width: 4),
              ],
            );
          },
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, EmployeeModel>>(
          future: _employeesFuture,
          builder: (context, empSnapshot) {
            final employeesById = empSnapshot.data ?? {};

          return FutureBuilder<Map<String, String>>(
            future: _adminNamesFuture,
            builder: (context, adminSnapshot) {
              final adminNamesById = adminSnapshot.data ?? {};

              return Column(
                children: [
                  Expanded(
                    child: StreamBuilder<List<MessageWithDoc>>(
                      stream: _messagingService.watchLatestMessages(
                        companyId: widget.companyId,
                        threadId: widget.threadId,
                        limit: _pageSize,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                        }

                        // Both lists are already newest-first (matches
                        // Firestore's descending createdAt order), so
                        // concatenating them directly gives the full
                        // newest-to-oldest sequence a reverse:true
                        // ListView wants at index 0.
                        final liveMessages = snapshot.data ?? [];
                        _currentLiveMessages = liveMessages;

                        final combined = <MessageWithDoc>[...liveMessages];
                        final seenIds = liveMessages.map((m) => m.doc.id).toSet();
                        for (final older in _olderMessages) {
                          if (seenIds.add(older.doc.id)) combined.add(older);
                        }

                        if (combined.isEmpty) {
                          return const Center(
                            child: Text('No messages yet. Say hello!', style: TextStyle(color: AppTheme.mutedText)),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          // +1 for the "loading older..." indicator at
                          // the far end when there's more history to
                          // fetch — only ever built when actually needed.
                          itemCount: combined.length + (_hasMoreOlder ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == combined.length) {
                              // Fires the fetch lazily the first time this
                              // trailing item actually gets built, as a
                              // backup to the scroll-position listener
                              // (covers the case where the whole history
                              // fits on screen with room to spare, so
                              // _onScroll's position math never triggers).
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _loadOlderMessages();
                              });
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }

                            final entry = combined[index];
                            final message = entry.message;
                            final isMine = message.senderUserId == _currentUserId;
                            final senderName = employeesById[message.senderUserId]?.fullName ??
                                adminNamesById[message.senderUserId] ??
                                'Unknown';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: isMine
                                  ? UserMessage(
                                      message: message.isDeleted ? 'Message deleted' : message.body,
                                      time: _formatTime(message.createdAt),
                                      isEdited: message.isEdited,
                                      isDeleted: message.isDeleted,
                                    )
                                  : OtherMessage(
                                      sender: senderName,
                                      message: message.isDeleted ? 'Message deleted' : message.body,
                                      time: _formatTime(message.createdAt),
                                      isEdited: message.isEdited,
                                      isDeleted: message.isDeleted,
                                    ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(color: Colors.white),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Type message...',
                              filled: true,
                              fillColor: AppTheme.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          onPressed: _isSending ? null : _send,
                          icon: _isSending
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send, color: AppTheme.blue),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
        ),
      ),
    );
  }
}

class OtherMessage extends StatelessWidget {
  final String sender;
  final String message;
  final String time;
  final bool isEdited;
  final bool isDeleted;

  const OtherMessage({
    super.key,
    required this.sender,
    required this.message,
    required this.time,
    this.isEdited = false,
    this.isDeleted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sender, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: isDeleted ? AppTheme.mutedText : AppTheme.darkText,
                fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isEdited ? '$time • edited' : time,
              style: const TextStyle(fontSize: 11, color: AppTheme.mutedText),
            ),
          ],
        ),
      ),
    );
  }
}

class UserMessage extends StatelessWidget {
  final String message;
  final String time;
  final bool isEdited;
  final bool isDeleted;

  const UserMessage({
    super.key,
    required this.message,
    required this.time,
    this.isEdited = false,
    this.isDeleted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.blue, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message,
              style: TextStyle(
                color: Colors.white,
                fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isEdited ? '$time • edited' : time,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
