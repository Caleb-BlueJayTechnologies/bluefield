import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../Firebase/firestore_schema.dart';
import '../../Models/support_ticket_model.dart';
import '../../Services/support_ticket_service.dart';
import '../../theme/app_theme.dart';
import 'admin_ticket_detail_screen.dart';

class AdminTicketListScreen extends StatefulWidget {
  const AdminTicketListScreen({super.key});

  @override
  State<AdminTicketListScreen> createState() => _AdminTicketListScreenState();
}

enum _SortMode { newest, oldest, priority, company }

class _AdminTicketListScreenState extends State<AdminTicketListScreen> {
  final SupportTicketService _ticketService = SupportTicketService();
  final TextEditingController _searchController = TextEditingController();

  String _searchText = '';
  String? _statusFilter;
  String? _categoryFilter;
  String? _priorityFilter;
  _SortMode _sortMode = _SortMode.priority;
  // Default view excludes resolved/closed/rejected — those live in
  // the Archive view instead, so "Total Tickets" and the main list
  // both reflect what's actually still open.
  bool _showArchive = false;
  // Updated every time the stream rebuilds — lets the AppBar's Copy
  // All button reach whatever's currently visible (respecting active
  // search/filters) without needing its own separate data fetch.
  List<SupportTicketModel> _visibleTickets = [];

  // Cached and keyed only by the params that actually affect the
  // underlying query (status/category/priority filters) — search text,
  // sort mode, and the archive toggle are all applied client-side in
  // _applySearchAndSort, so they shouldn't force a Firestore
  // resubscribe. Without this, every keystroke in the search box would
  // call watchAllTickets(...) again, handing StreamBuilder a brand-new
  // Stream object and flashing the whole list to a loading state.
  String? _ticketsStreamKey;
  Stream<List<SupportTicketModel>>? _ticketsStream;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }

  Stream<List<SupportTicketModel>> _ensureTicketsStream() {
    final key = '$_statusFilter::$_categoryFilter::$_priorityFilter';
    if (_ticketsStreamKey != key || _ticketsStream == null) {
      _ticketsStreamKey = key;
      _ticketsStream = _ticketService.watchAllTickets(
        statusFilter: _statusFilter,
        categoryFilter: _categoryFilter,
        priorityFilter: _priorityFilter,
      );
    }
    return _ticketsStream!;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    switch (status) {
      case FSTicketStatus.newTicket:
        return 'New';
      case FSTicketStatus.reviewing:
        return 'Reviewing';
      case FSTicketStatus.planned:
        return 'Planned';
      case FSTicketStatus.inProgress:
        return 'In Progress';
      case FSTicketStatus.waitingOnCustomer:
        return 'Waiting on Customer';
      case FSTicketStatus.resolved:
        return 'Resolved';
      case FSTicketStatus.closed:
        return 'Closed';
      case FSTicketStatus.rejected:
        return 'Rejected';
      default:
        return status;
    }
  }

  String _categoryLabel(String value) {
    switch (value) {
      case FSTicketCategory.bugReport:
        return 'Bug Report';
      case FSTicketCategory.featureRequest:
        return 'Feature Request';
      case FSTicketCategory.question:
        return 'Question';
      default:
        return 'General Feedback';
    }
  }

  String _priorityLabel(String value) {
    switch (value) {
      case FSTicketPriority.low:
        return 'Low';
      case FSTicketPriority.high:
        return 'High';
      case FSTicketPriority.critical:
        return 'Critical';
      default:
        return 'Medium';
    }
  }

  int _priorityWeight(String value) {
    switch (value) {
      case FSTicketPriority.critical:
        return 3;
      case FSTicketPriority.high:
        return 2;
      case FSTicketPriority.medium:
        return 1;
      default:
        return 0;
    }
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.month}/${value.day}/${value.year} • $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Every field of every currently-visible ticket (respecting active
  /// search/filters), separated clearly per ticket — meant to paste
  /// into a spreadsheet, doc, or email thread in one go.
  String _allTicketsToText(List<SupportTicketModel> tickets) {
    final buffer = StringBuffer();
    buffer.writeln('${tickets.length} Ticket(s) — Exported ${_formatDateTime(DateTime.now())}');
    buffer.writeln('=' * 60);

    for (final t in tickets) {
      buffer
        ..writeln()
        ..writeln('Ticket ID: ${t.ticketId}')
        ..writeln('Subject: ${t.subject}')
        ..writeln('Company: ${t.companyName} (${t.companyId})')
        ..writeln('Submitted by: ${t.employeeName} (${t.employeeRole})')
        ..writeln('Category: ${_categoryLabel(t.category)}')
        ..writeln('Priority: ${_priorityLabel(t.priority)}')
        ..writeln('Status: ${_statusLabel(t.status)}')
        ..writeln('Submitted: ${_formatDateTime(t.createdAt)}')
        ..writeln('Last Updated: ${_formatDateTime(t.updatedAt)}')
        ..writeln('Description: ${t.description}');
      if (t.resolutionNotes?.trim().isNotEmpty == true) {
        buffer.writeln('Resolution Notes: ${t.resolutionNotes}');
      }
      if (t.screenshotUrls.isNotEmpty) {
        buffer.writeln('Screenshots: ${t.screenshotUrls.join(', ')}');
      }
      buffer
        ..writeln('App Version: ${t.metadata.appVersion} (build ${t.metadata.buildNumber})')
        ..writeln('Platform: ${t.metadata.platform}');
      if (t.metadata.deviceModel != null) buffer.writeln('Device: ${t.metadata.deviceModel}');
      if (t.metadata.osVersion != null) buffer.writeln('OS Version: ${t.metadata.osVersion}');
      buffer
        ..writeln('Email Backup Sent: ${t.emailSent ? 'Yes' : 'No'}')
        ..writeln('-' * 60);
    }

    return buffer.toString();
  }

  Color _priorityColor(String value) {
    switch (value) {
      case FSTicketPriority.critical:
        return Colors.red;
      case FSTicketPriority.high:
        return Colors.orange;
      case FSTicketPriority.low:
        return AppTheme.mutedText;
      default:
        return AppTheme.blue;
    }
  }

  List<SupportTicketModel> _applySearchAndSort(List<SupportTicketModel> tickets) {
    var result = tickets.where((t) => _showArchive ? !t.isOpen : t.isOpen).toList();

    if (_searchText.isNotEmpty) {
      result = result
          .where((t) =>
              t.companyName.toLowerCase().contains(_searchText) ||
              t.employeeName.toLowerCase().contains(_searchText) ||
              t.subject.toLowerCase().contains(_searchText))
          .toList();
    }

    result = List.of(result);
    switch (_sortMode) {
      case _SortMode.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SortMode.oldest:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _SortMode.priority:
        result.sort((a, b) {
          final priorityCompare = _priorityWeight(b.priority).compareTo(_priorityWeight(a.priority));
          if (priorityCompare != 0) return priorityCompare;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case _SortMode.company:
        result.sort((a, b) => a.companyName.toLowerCase().compareTo(b.companyName.toLowerCase()));
        break;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: Text(_showArchive ? 'Archived Tickets' : 'Active Tickets', style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Copy All Visible Tickets',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              if (_visibleTickets.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No tickets to copy.')));
                return;
              }
              await Clipboard.setData(ClipboardData(text: _allTicketsToText(_visibleTickets)));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied ${_visibleTickets.length} ticket(s) to clipboard.')),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
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
                  hintText: 'Search company, employee, subject...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Active'), icon: Icon(Icons.pending_actions_outlined)),
                  ButtonSegment(value: true, label: Text('Archive'), icon: Icon(Icons.archive_outlined)),
                ],
                selected: {_showArchive},
                onSelectionChanged: (selection) => setState(() => _showArchive = selection.first),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _dropdownChip<String?>(
                      label: 'Status',
                      value: _statusFilter,
                      items: {
                        null: 'All Statuses',
                        FSTicketStatus.newTicket: 'New',
                        FSTicketStatus.reviewing: 'Reviewing',
                        FSTicketStatus.planned: 'Planned',
                        FSTicketStatus.inProgress: 'In Progress',
                        FSTicketStatus.waitingOnCustomer: 'Waiting on Customer',
                        FSTicketStatus.resolved: 'Resolved',
                        FSTicketStatus.closed: 'Closed',
                        FSTicketStatus.rejected: 'Rejected',
                      },
                      onChanged: (v) => setState(() => _statusFilter = v),
                    ),
                    const SizedBox(width: 8),
                    _dropdownChip<String?>(
                      label: 'Category',
                      value: _categoryFilter,
                      items: {
                        null: 'All Categories',
                        FSTicketCategory.bugReport: 'Bug Report',
                        FSTicketCategory.featureRequest: 'Feature Request',
                        FSTicketCategory.question: 'Question',
                        FSTicketCategory.generalFeedback: 'General Feedback',
                      },
                      onChanged: (v) => setState(() => _categoryFilter = v),
                    ),
                    const SizedBox(width: 8),
                    _dropdownChip<String?>(
                      label: 'Priority',
                      value: _priorityFilter,
                      items: {
                        null: 'All Priorities',
                        FSTicketPriority.low: 'Low',
                        FSTicketPriority.medium: 'Medium',
                        FSTicketPriority.high: 'High',
                        FSTicketPriority.critical: 'Critical',
                      },
                      onChanged: (v) => setState(() => _priorityFilter = v),
                    ),
                    const SizedBox(width: 8),
                    _dropdownChip<_SortMode>(
                      label: 'Sort',
                      value: _sortMode,
                      items: const {
                        _SortMode.newest: 'Newest',
                        _SortMode.oldest: 'Oldest',
                        _SortMode.priority: 'Priority',
                        _SortMode.company: 'Company',
                      },
                      onChanged: (v) => setState(() => _sortMode = v ?? _SortMode.newest),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: StreamBuilder<List<SupportTicketModel>>(
                  stream: _ensureTicketsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                    }

                    final tickets = _applySearchAndSort(snapshot.data ?? []);
                    // Deliberately assigned during build rather than
                    // via setState — this is a passive cache for the
                    // Copy All button, not something that should
                    // itself trigger a rebuild.
                    _visibleTickets = tickets;

                    if (tickets.isEmpty) {
                      return Center(
                        child: Text(
                          _showArchive ? 'No archived tickets match these filters.' : 'No active tickets match these filters.',
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: tickets.length,
                      itemBuilder: (context, index) {
                        final ticket = tickets[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(color: _priorityColor(ticket.priority), shape: BoxShape.circle),
                            ),
                            title: Text(ticket.subject, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '${ticket.companyName} • ${ticket.employeeName} • ${_categoryLabel(ticket.category)}',
                              style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
                            ),
                            trailing: Text(_statusLabel(ticket.status),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.blue)),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => AdminTicketDetailScreen(ticketId: ticket.ticketId)),
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

  Widget _dropdownChip<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      items: items.entries.map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value))).toList(),
      onChanged: onChanged,
    );
  }
}
