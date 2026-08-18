import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/support_ticket_model.dart';
import '../Services/auth_service.dart';
import '../Services/support_ticket_service.dart';
import '../theme/app_theme.dart';

class TicketDetailsScreen extends StatefulWidget {
  final String ticketId;

  const TicketDetailsScreen({super.key, required this.ticketId});

  @override
  State<TicketDetailsScreen> createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> {
  final AuthService _authService = AuthService();
  final SupportTicketService _ticketService = SupportTicketService();

  late Future<SupportTicketModel> _ticketFuture;

  @override
  void initState() {
    super.initState();
    _ticketFuture = _loadTicket();
  }

  Future<SupportTicketModel> _loadTicket() async {
    final profile = await _authService.getCurrentUserProfile();
    final ticket = await _ticketService.getTicket(widget.ticketId);

    if (ticket == null) {
      throw Exception('This ticket was not found.');
    }
    // getTicket() itself is a raw fetch-by-ID with no built-in
    // scoping — real enforcement belongs in Firestore security rules
    // (still on the to-do list). This client-side check is
    // defense-in-depth in the meantime, not a substitute for it.
    if (ticket.companyId != profile.activeCompanyId) {
      throw Exception('You do not have access to this ticket.');
    }

    return ticket;
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
        return 'Waiting on You';
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

  String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Ticket Details', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<SupportTicketModel>(
        future: _ticketFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  snapshot.error?.toString() ?? 'Unable to load this ticket.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ),
            );
          }

          final ticket = snapshot.data!;

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
                      Text(ticket.subject, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('${_categoryLabel(ticket.category)} • ${_priorityLabel(ticket.priority)} Priority',
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text('Submitted ${_formatDate(ticket.createdAt)}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard('Status', [Text(_statusLabel(ticket.status), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
              _sectionCard('Your Message', [Text(ticket.description, style: const TextStyle(fontSize: 15, height: 1.5))]),
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
                                child: Image.network(url, width: 90, height: 90, fit: BoxFit.cover),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              if (ticket.resolutionNotes?.trim().isNotEmpty == true)
                _sectionCard('Resolution Notes', [Text(ticket.resolutionNotes!, style: const TextStyle(fontSize: 15, height: 1.5))]),
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
}
