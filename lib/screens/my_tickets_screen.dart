import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/support_ticket_model.dart';
import '../Services/auth_service.dart';
import '../Services/support_ticket_service.dart';
import '../theme/app_theme.dart';
import 'feedback_screen.dart';
import 'ticket_details_screen.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  final AuthService _authService = AuthService();
  final SupportTicketService _ticketService = SupportTicketService();

  late Future<_TicketViewerContext> _viewerFuture;

  @override
  void initState() {
    super.initState();
    _viewerFuture = _authService.getCurrentUserProfile().then(
          (p) => _TicketViewerContext(companyId: p.activeCompanyId, userId: p.uid, role: p.role),
        );
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

  Color _statusColor(String status) {
    switch (status) {
      case FSTicketStatus.resolved:
      case FSTicketStatus.closed:
        return Colors.green;
      case FSTicketStatus.rejected:
        return AppTheme.mutedText;
      case FSTicketStatus.waitingOnCustomer:
        return Colors.orange;
      default:
        return AppTheme.blue;
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
        title: const Text('My Tickets', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<_TicketViewerContext>(
          future: _viewerFuture,
          builder: (context, viewerSnapshot) {
            if (viewerSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (viewerSnapshot.hasError || !viewerSnapshot.hasData) {
              return Center(
                child: Text(viewerSnapshot.error?.toString() ?? 'Unable to load your company.',
                    style: const TextStyle(color: AppTheme.mutedText)),
              );
            }

            final viewer = viewerSnapshot.data!;

            return Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<SupportTicketModel>>(
                    // Strictly scoped to the caller's own company, and
                    // further scoped by role server-side (see
                    // firestore.rules' supportTickets read rule and
                    // watchCompanyTickets' doc comment): an employee
                    // only ever gets their own tickets back here, a
                    // manager gets their own plus every employee's, and
                    // an owner gets the whole company's.
                    stream: _ticketService.watchCompanyTickets(
                      companyId: viewer.companyId,
                      userId: viewer.userId,
                      role: viewer.role,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)),
                        );
                      }

                      final tickets = (snapshot.data ?? []).where((t) => !t.shouldHideFromCompanyView).toList();

                      if (tickets.isEmpty) {
                        return const Center(
                          child: Text('No tickets submitted yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(18),
                        itemCount: tickets.length,
                        itemBuilder: (context, index) {
                          final ticket = tickets[index];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            child: ListTile(
                              title: Text(ticket.subject, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                              subtitle: Text('Submitted ${_formatDate(ticket.createdAt)}',
                                  style: const TextStyle(color: AppTheme.mutedText)),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(ticket.status).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _statusLabel(ticket.status),
                                  style: TextStyle(color: _statusColor(ticket.status), fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TicketDetailsScreen(ticketId: ticket.ticketId),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const FeedbackScreen()));
                      },
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('New Ticket'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TicketViewerContext {
  final String companyId;
  final String userId;
  final String role;

  const _TicketViewerContext({
    required this.companyId,
    required this.userId,
    required this.role,
  });
}
