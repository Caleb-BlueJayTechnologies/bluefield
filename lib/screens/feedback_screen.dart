import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../Firebase/firestore_schema.dart';
import '../Services/auth_service.dart';
import '../Services/company_service.dart';
import '../Services/support_ticket_service.dart';
import '../theme/app_theme.dart';
import 'my_tickets_screen.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final AuthService _authService = AuthService();
  final CompanyService _companyService = CompanyService();
  final SupportTicketService _ticketService = SupportTicketService();
  final ImagePicker _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _category = FSTicketCategory.bugReport;
  String _priority = FSTicketPriority.medium;
  final List<XFile> _selectedScreenshots = [];
  bool _isSubmitting = false;

  late Future<_FeedbackReferenceData> _referenceFuture;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<_FeedbackReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final company = await _companyService.getCompany(profile.activeCompanyId);

    return _FeedbackReferenceData(
      companyId: profile.activeCompanyId,
      companyName: company?.companyName ?? 'Unknown Company',
      userId: profile.uid,
      employeeName: '${profile.firstName} ${profile.lastName}'.trim(),
      employeeRole: profile.role,
    );
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

  Future<void> _pickScreenshot() async {
    if (_selectedScreenshots.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can attach up to 5 screenshots.')),
      );
      return;
    }
    final image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() => _selectedScreenshots.add(image));
    }
  }

  void _removeScreenshot(int index) {
    setState(() => _selectedScreenshots.removeAt(index));
  }

  Future<void> _submit(_FeedbackReferenceData reference) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    String? ticketId;
    try {
      // Ticket is created in Firestore first (source of truth per the
      // spec) — screenshots upload afterward under the real ticketId,
      // then get attached. Email backup is sent server-side by a
      // Cloud Function watching for new ticket docs, not from here.
      ticketId = await _ticketService.submitTicket(
        companyId: reference.companyId,
        companyName: reference.companyName,
        userId: reference.userId,
        employeeName: reference.employeeName,
        employeeRole: reference.employeeRole,
        category: _category,
        priority: _priority,
        subject: _subjectController.text.trim(),
        description: _descriptionController.text.trim(),
      );
    } catch (e) {
      // The ticket itself never got created — this really is a total
      // failure, and it's safe for the user to just try again.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _isSubmitting = false);
      return;
    }

    // From here on, the ticket already exists in Firestore. Anything
    // that goes wrong below is a screenshot problem, not a submission
    // problem — it must never look like total failure, or the user
    // will reasonably retry and create a genuine duplicate ticket
    // (exactly what happened before this fix: a failed screenshot
    // upload threw, the whole thing looked like it failed, and three
    // retries created three real tickets).
    var screenshotWarning = false;
    if (_selectedScreenshots.isNotEmpty) {
      try {
        final urls = <String>[];
        for (final image in _selectedScreenshots) {
          final url = await _ticketService.uploadScreenshot(
            companyId: reference.companyId,
            ticketId: ticketId,
            image: image,
          );
          urls.add(url);
        }
        await _ticketService.attachScreenshots(ticketId: ticketId, screenshotUrls: urls);
      } catch (_) {
        screenshotWarning = true;
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // A dialog instead of just a SnackBar — the immediate page
    // replacement right after this made the old SnackBar easy to miss
    // entirely, and the ticket asked for something that actually reads
    // as "thanks, we've got it" rather than a toast that can vanish
    // mid-transition. Confirming with a tap (rather than the dialog
    // auto-dismissing) also means it's actually seen, not just shown.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, color: AppTheme.blue, size: 36),
        title: const Text('Thanks for letting us know!'),
        content: Text(
          screenshotWarning
              ? 'Your ticket was submitted, but the screenshot couldn\'t be attached. Our support team will still follow up soon.'
              : 'Your ticket has been submitted. Our support team will follow up soon.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MyTicketsScreen()),
    );
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Submit Feedback', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const MyTicketsScreen()));
            },
            child: const Text('My Tickets'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_FeedbackReferenceData>(
          future: _referenceFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Text(
                  snapshot.error?.toString() ?? 'Unable to load your account.',
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              );
            }

            final reference = snapshot.data!;

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                children: [
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            value: _category,
                            decoration: const InputDecoration(labelText: 'Category'),
                            items: [
                              FSTicketCategory.bugReport,
                              FSTicketCategory.featureRequest,
                              FSTicketCategory.question,
                              FSTicketCategory.generalFeedback,
                            ].map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c)))).toList(),
                            onChanged: (value) {
                              if (value != null) setState(() => _category = value);
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: _priority,
                            decoration: const InputDecoration(labelText: 'Priority'),
                            items: [
                              FSTicketPriority.low,
                              FSTicketPriority.medium,
                              FSTicketPriority.high,
                              FSTicketPriority.critical,
                            ].map((p) => DropdownMenuItem(value: p, child: Text(_priorityLabel(p)))).toList(),
                            onChanged: (value) {
                              if (value != null) setState(() => _priority = value);
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _subjectController,
                            decoration: const InputDecoration(labelText: 'Subject'),
                            validator: (v) => _requiredValidator(v, 'Subject'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              alignLabelWithHint: true,
                            ),
                            validator: (v) => _requiredValidator(v, 'Description'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Screenshots (optional)',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                          const SizedBox(height: 10),
                          if (_selectedScreenshots.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(_selectedScreenshots.length, (index) {
                                return Chip(
                                  label: Text(_selectedScreenshots[index].name, overflow: TextOverflow.ellipsis),
                                  onDeleted: () => _removeScreenshot(index),
                                );
                              }),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _pickScreenshot,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('Add Screenshot'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSubmitting ? null : () => _submit(reference),
                      icon: _isSubmitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_outlined),
                      label: Text(_isSubmitting ? 'Submitting...' : 'Submit Feedback'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FeedbackReferenceData {
  final String companyId;
  final String companyName;
  final String userId;
  final String employeeName;
  final String employeeRole;

  const _FeedbackReferenceData({
    required this.companyId,
    required this.companyName,
    required this.userId,
    required this.employeeName,
    required this.employeeRole,
  });
}
