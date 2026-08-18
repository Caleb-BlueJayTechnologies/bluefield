import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Models/legal_acceptance_event_model.dart';
import '../Services/legal_acceptance_service.dart';
import '../theme/app_theme.dart';

/// Every legal-document acceptance on file for the signed-in user —
/// Section 11.9's requirement that account settings always expose
/// prior accepted versions and acceptance dates. Read-only: these
/// events are immutable by design (see FSCollections.legalAcceptanceEvents).
class LegalAcceptanceHistoryScreen extends StatefulWidget {
  const LegalAcceptanceHistoryScreen({super.key});

  @override
  State<LegalAcceptanceHistoryScreen> createState() => _LegalAcceptanceHistoryScreenState();
}

class _LegalAcceptanceHistoryScreenState extends State<LegalAcceptanceHistoryScreen> {
  final LegalAcceptanceService _service = LegalAcceptanceService();
  late final Stream<List<LegalAcceptanceEvent>> _historyStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _historyStream = _service.watchAcceptanceHistory(uid);
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.month}/${value.day}/${value.year} • $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('My Acceptance History', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: StreamBuilder<List<LegalAcceptanceEvent>>(
          stream: _historyStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)),
              );
            }

            final events = snapshot.data ?? [];
            if (events.isEmpty) {
              return const Center(
                child: Text('No acceptance records yet.', style: TextStyle(color: AppTheme.mutedText)),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.verified_outlined, color: AppTheme.blue),
                    title: Text(event.documentTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Version ${event.documentVersion} • Accepted ${_formatDateTime(event.acceptedAt)}',
                      style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
