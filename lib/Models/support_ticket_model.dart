import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// Device/app metadata automatically attached to every ticket — the
/// submitting user never enters any of this by hand.
class TicketMetadata {
  final String appVersion;
  final String buildNumber;
  final String platform;
  final String? deviceModel;
  final String? osVersion;

  const TicketMetadata({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    this.deviceModel,
    this.osVersion,
  });

  Map<String, dynamic> toMap() {
    return {
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'platform': platform,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
    };
  }

  factory TicketMetadata.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const TicketMetadata(appVersion: 'unknown', buildNumber: 'unknown', platform: 'unknown');
    }
    return TicketMetadata(
      appVersion: map['appVersion']?.toString() ?? 'unknown',
      buildNumber: map['buildNumber']?.toString() ?? 'unknown',
      platform: map['platform']?.toString() ?? 'unknown',
      deviceModel: map['deviceModel']?.toString(),
      osVersion: map['osVersion']?.toString(),
    );
  }
}

/// A support ticket / feedback submission. Stored at the ROOT
/// collection `supportTickets/{ticketId}` — deliberately NOT nested
/// under a company, because this is a company-to-BlueJay relationship,
/// not a within-company one. A company's own in-app messaging system
/// (MessageThreadModel) is a completely different, per-company-scoped
/// concept; this ticket system is the only place a company talks to
/// BlueJay itself.
///
/// Every ticket carries companyId/companyName/userId/employeeName
/// denormalized directly onto the doc (not just referenced) so the
/// Admin Panel's ticket list, search, and filters never need a second
/// round-trip lookup per ticket — this collection is read far more
/// often by admins scanning many tickets at once than it's written.
class SupportTicketModel {
  final String ticketId;
  final String companyId;
  final String companyName;
  final String userId;
  final String employeeName;
  final String employeeRole;
  final String category;
  final String priority;
  final String subject;
  final String description;
  final List<String> screenshotUrls;
  final String status;
  final String? assignedAdminId;
  final String? resolutionNotes;
  final TicketMetadata metadata;
  final bool emailSent;
  final DateTime? emailSentAt;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SupportTicketModel({
    required this.ticketId,
    required this.companyId,
    required this.companyName,
    required this.userId,
    required this.employeeName,
    required this.employeeRole,
    required this.category,
    required this.priority,
    required this.subject,
    required this.description,
    this.screenshotUrls = const [],
    this.status = FSTicketStatus.newTicket,
    this.assignedAdminId,
    this.resolutionNotes,
    required this.metadata,
    this.emailSent = false,
    this.emailSentAt,
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOpen => status != FSTicketStatus.resolved &&
      status != FSTicketStatus.closed &&
      status != FSTicketStatus.rejected;

  bool get isCritical => priority == FSTicketPriority.critical;

  /// The company-facing "My Tickets" list only. A ticket the admin has
  /// closed out — resolved, closed, or rejected, i.e. any status that
  /// isn't still active/in-flight — stays visible there for 1 week
  /// after that final status lands, then drops out of that default
  /// view. The admin's own ticket list (and Firestore itself) still
  /// has the full record forever; this only affects what the
  /// SUBMITTING COMPANY sees by default. Any status still in progress
  /// (new/reviewing/planned/inProgress/waitingOnCustomer) always stays
  /// visible regardless of age — only a truly finished ticket ages out.
  bool get shouldHideFromCompanyView {
    final isFinal = status == FSTicketStatus.resolved ||
        status == FSTicketStatus.closed ||
        status == FSTicketStatus.rejected;
    if (!isFinal || resolvedAt == null) return false;
    return DateTime.now().difference(resolvedAt!) > const Duration(days: 7);
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String companyName,
    required String userId,
    required String employeeName,
    required String employeeRole,
    required String category,
    required String priority,
    required String subject,
    required String description,
    List<String> screenshotUrls = const [],
    required TicketMetadata metadata,
  }) {
    return {
      FSFields.companyId: companyId,
      'companyName': companyName,
      FSFields.userId: userId,
      'employeeName': employeeName,
      'employeeRole': employeeRole,
      'category': category,
      'priority': priority,
      'subject': subject,
      'description': description,
      'screenshotUrls': screenshotUrls,
      FSFields.status: FSTicketStatus.newTicket,
      'assignedAdminId': null,
      'resolutionNotes': null,
      'metadata': metadata.toMap(),
      'emailSent': false,
      'emailSentAt': null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory SupportTicketModel.fromMap(String ticketId, Map<String, dynamic> map) {
    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    DateTime? readOptionalDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return null;
    }

    return SupportTicketModel(
      ticketId: ticketId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      companyName: map['companyName']?.toString() ?? 'Unknown Company',
      userId: map[FSFields.userId]?.toString() ?? '',
      employeeName: map['employeeName']?.toString() ?? 'Unknown',
      employeeRole: map['employeeRole']?.toString() ?? '',
      category: map['category']?.toString() ?? FSTicketCategory.generalFeedback,
      priority: map['priority']?.toString() ?? FSTicketPriority.medium,
      subject: map['subject']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      screenshotUrls: List<String>.from(map['screenshotUrls'] ?? const []),
      status: map[FSFields.status]?.toString() ?? FSTicketStatus.newTicket,
      assignedAdminId: map['assignedAdminId']?.toString(),
      resolutionNotes: map['resolutionNotes']?.toString(),
      metadata: TicketMetadata.fromMap(map['metadata'] as Map<String, dynamic>?),
      emailSent: map['emailSent'] == true,
      emailSentAt: readOptionalDate(map['emailSentAt']),
      resolvedAt: readOptionalDate(map['resolvedAt']),
      createdAt: readDate(map[FSFields.createdAt]),
      updatedAt: readDate(map[FSFields.updatedAt]),
    );
  }

  factory SupportTicketModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return SupportTicketModel.fromMap(doc.id, doc.data() ?? {});
  }
}
