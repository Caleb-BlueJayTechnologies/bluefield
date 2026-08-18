import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../Firebase/firestore_schema.dart';
import '../../Models/support_ticket_model.dart';
import '../../Services/support_ticket_service.dart';
import '../../theme/app_theme.dart';

class AdminTicketDetailScreen extends StatefulWidget {
  final String ticketId;

  const AdminTicketDetailScreen({super.key, required this.ticketId});

  @override
  State<AdminTicketDetailScreen> createState() => _AdminTicketDetailScreenState();
}

class _AdminTicketDetailScreenState extends State<AdminTicketDetailScreen> {
  final SupportTicketService _ticketService = SupportTicketService();
  final TextEditingController _resolutionController = TextEditingController();

  late Stream<SupportTicketModel?> _ticketStream;
  bool _isSaving = false;
  String? _selectedStatus;
  // Form fields (_selectedStatus, resolution notes) only ever
  // populate from the FIRST snapshot — after that the stream keeps
  // the rest of the ticket display live (status badge, timestamps,
  // etc.) without overwriting whatever the admin is actively typing,
  // which a naive "repopulate on every snapshot" would do any time
  // the doc changes — including from the admin's own save completing.
  bool _hasInitializedFields = false;

  @override
  void initState() {
    super.initState();
    _ticketStream = _ticketService.watchTicket(widget.ticketId);
  }

  @override
  void dispose() {
    _resolutionController.dispose();
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

  String _formatDateTime(DateTime value) {
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.month}/${value.day}/${value.year} • $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Every field on the ticket, in a plain-text block meant to paste
  /// cleanly into an email, doc, or chat — not just the fields shown
  /// on screen.
  String _ticketToText(SupportTicketModel t) {
    final buffer = StringBuffer()
      ..writeln('Ticket ID: ${t.ticketId}')
      ..writeln('Subject: ${t.subject}')
      ..writeln('Company: ${t.companyName} (${t.companyId})')
      ..writeln('Submitted by: ${t.employeeName} (${t.employeeRole})')
      ..writeln('Category: ${_categoryLabel(t.category)}')
      ..writeln('Priority: ${_priorityLabel(t.priority)}')
      ..writeln('Status: ${_statusLabel(t.status)}')
      ..writeln('Submitted: ${_formatDateTime(t.createdAt)}')
      ..writeln('Last Updated: ${_formatDateTime(t.updatedAt)}')
      ..writeln()
      ..writeln('Description:')
      ..writeln(t.description)
      ..writeln();
    if (t.resolutionNotes?.trim().isNotEmpty == true) {
      buffer
        ..writeln('Resolution Notes:')
        ..writeln(t.resolutionNotes)
        ..writeln();
    }
    if (t.screenshotUrls.isNotEmpty) {
      buffer
        ..writeln('Screenshots:')
        ..writeln(t.screenshotUrls.join('\n'))
        ..writeln();
    }
    buffer
      ..writeln('App Version: ${t.metadata.appVersion} (build ${t.metadata.buildNumber})')
      ..writeln('Platform: ${t.metadata.platform}');
    if (t.metadata.deviceModel != null) buffer.writeln('Device: ${t.metadata.deviceModel}');
    if (t.metadata.osVersion != null) buffer.writeln('OS Version: ${t.metadata.osVersion}');
    buffer.writeln('Email Backup Sent: ${t.emailSent ? 'Yes' : 'No'}');

    return buffer.toString();
  }

  Future<void> _saveChanges() async {
    final adminId = FirebaseAuth.instance.currentUser?.uid;
    if (adminId == null || _selectedStatus == null) return;

    setState(() => _isSaving = true);

    try {
      await _ticketService.updateTicketStatus(
        actingAdminId: adminId,
        ticketId: widget.ticketId,
        newStatus: _selectedStatus!,
        resolutionNotes: _resolutionController.text.trim().isEmpty ? null : _resolutionController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
        title: const Text('Ticket Detail', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
        actions: [
          StreamBuilder<SupportTicketModel?>(
            stream: _ticketStream,
            builder: (context, snapshot) {
              final ticket = snapshot.data;
              if (ticket == null) return const SizedBox.shrink();

              return IconButton(
                tooltip: 'Copy Ticket Details',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _ticketToText(ticket)));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket copied to clipboard.')));
                },
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<SupportTicketModel?>(
        stream: _ticketStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  snapshot.error?.toString() ?? 'This ticket was not found.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ),
            );
          }

          final ticket = snapshot.data!;
          if (!_hasInitializedFields) {
            _hasInitializedFields = true;
            _selectedStatus = ticket.status;
            _resolutionController.text = ticket.resolutionNotes ?? '';
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
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
                      Text(ticket.subject, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('${ticket.companyName} • ${ticket.employeeName} (${ticket.employeeRole})',
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text('${_categoryLabel(ticket.category)} • ${_priorityLabel(ticket.priority)} Priority',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard('Description', [Text(ticket.description, style: const TextStyle(fontSize: 15, height: 1.5))]),
              if (ticket.screenshotUrls.isNotEmpty)
                _sectionCard(
                  'Screenshots',
                  [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ticket.screenshotUrls
                          .map((url) => ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(url, width: 100, height: 100, fit: BoxFit.cover),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              _sectionCard('Metadata', [
                _infoRow('Submitted', _formatDateTime(ticket.createdAt)),
                _infoRow('App Version', '${ticket.metadata.appVersion} (build ${ticket.metadata.buildNumber})'),
                _infoRow('Platform', ticket.metadata.platform),
                if (ticket.metadata.deviceModel != null) _infoRow('Device', ticket.metadata.deviceModel!),
                if (ticket.metadata.osVersion != null) _infoRow('OS Version', ticket.metadata.osVersion!),
                _infoRow('Email Backup Sent', ticket.emailSent ? 'Yes' : 'No'),
              ]),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Manage Ticket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          FSTicketStatus.newTicket,
                          FSTicketStatus.reviewing,
                          FSTicketStatus.planned,
                          FSTicketStatus.inProgress,
                          FSTicketStatus.waitingOnCustomer,
                          FSTicketStatus.resolved,
                          FSTicketStatus.closed,
                          FSTicketStatus.rejected,
                        ].map((s) => DropdownMenuItem(value: s, child: Text(_statusLabel(s)))).toList(),
                        onChanged: (value) => setState(() => _selectedStatus = value),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _resolutionController,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Resolution Notes', alignLabelWithHint: true),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _saveChanges,
                          icon: _isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
