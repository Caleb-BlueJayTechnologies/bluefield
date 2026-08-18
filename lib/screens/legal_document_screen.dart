import 'package:flutter/material.dart';

import '../Models/legal_document_model.dart';
import '../theme/app_theme.dart';

/// Renders one LegalDocumentVersion — the "exact agreement version"
/// every checkbox link in the clickwrap flow must open before
/// acceptance (Section 11.1). Generic over documentType so the same
/// screen serves Company Terms, Privacy Policy, User Terms, and any
/// future document type added to LegalDocumentRegistry.
class LegalDocumentScreen extends StatelessWidget {
  final String documentType;

  const LegalDocumentScreen({super.key, required this.documentType});

  String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final document = LegalDocumentRegistry.current(documentType);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: Text(document.title, style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (document.isDraft)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'DRAFT — this document has not been finalized or reviewed by counsel yet.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.darkText),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Version ${document.version}',
                style: const TextStyle(fontSize: 12, color: AppTheme.mutedText, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                document.effectiveDate != null
                    ? 'Effective ${_formatDate(document.effectiveDate!)}'
                    : 'Not yet effective',
                style: const TextStyle(fontSize: 12, color: AppTheme.mutedText),
              ),
              const SizedBox(height: 18),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    document.bodyText,
                    style: const TextStyle(fontSize: 14, height: 1.5, color: AppTheme.darkText),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
