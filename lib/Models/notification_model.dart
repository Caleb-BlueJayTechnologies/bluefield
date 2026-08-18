import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// Every event type that can generate an in-app/push notification.
/// notification_service uses this to decide the deep-link route and
/// icon/copy for each notification — keep this list in sync with
/// Section 13 of the product plan when new event types are added.
class NotificationType {
  NotificationType._();

  static const scheduleAssignment = 'scheduleAssignment';
  static const scheduleChange = 'scheduleChange';
  static const jobAssignment = 'jobAssignment';
  static const jobCancellation = 'jobCancellation';
  static const newMessage = 'newMessage';
  static const newAnnouncement = 'newAnnouncement';
  static const timeOffDecision = 'timeOffDecision';
  static const correctionDecision = 'correctionDecision';
  static const pendingApproval = 'pendingApproval'; // for managers/owners
  static const employeeInvitation = 'employeeInvitation';
  static const companyAlert = 'companyAlert';
}

/// A single in-app notification for one user. Stored at
/// `companies/{companyId}/notifications/{notificationId}`.
///
/// To avoid duplicate notifications for the same event (e.g. a job
/// getting saved twice in quick succession), notification_service
/// should derive [dedupeKey] deterministically from the event
/// (e.g. "jobAssignment:{jobId}:{userId}") and use it as the document
/// ID, or query for an existing doc with that key before writing —
/// either approach makes the create idempotent.
class NotificationModel {
  final String notificationId;
  final String companyId;
  final String userId;

  final String type; // NotificationType.*
  final String title;
  final String body;

  /// ID of the related document (jobId, scheduleId, threadId,
  /// timeOffRequestId, etc.) — meaning depends on [type].
  final String? relatedId;

  /// Named app route to push when the notification is tapped, e.g.
  /// '/jobs/detail'. Populated by notification_service based on [type]
  /// so screens don't need their own type-to-route mapping logic.
  final String? deepLinkRoute;

  /// Idempotency key — see class doc above.
  final String? dedupeKey;

  final bool isRead;
  final DateTime? readAt;

  final bool isArchived;
  final DateTime? archivedAt;

  final DateTime createdAt;

  const NotificationModel({
    required this.notificationId,
    required this.companyId,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.relatedId,
    this.deepLinkRoute,
    this.dedupeKey,
    required this.isRead,
    this.readAt,
    this.isArchived = false,
    this.archivedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      FSFields.userId: userId,
      'type': type,
      'title': title,
      'body': body,
      'relatedId': relatedId,
      'deepLinkRoute': deepLinkRoute,
      'dedupeKey': dedupeKey,
      'isRead': isRead,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      FSFields.isArchived: isArchived,
      FSFields.archivedAt:
          archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String userId,
    required String type,
    required String title,
    required String body,
    String? relatedId,
    String? deepLinkRoute,
    String? dedupeKey,
  }) {
    return {
      FSFields.companyId: companyId,
      FSFields.userId: userId,
      'type': type,
      'title': title,
      'body': body,
      'relatedId': relatedId,
      'deepLinkRoute': deepLinkRoute,
      'dedupeKey': dedupeKey,
      'isRead': false,
      'readAt': null,
      FSFields.isArchived: false,
      FSFields.archivedAt: null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
    };
  }

  factory NotificationModel.fromMap(
    String notificationId,
    Map<String, dynamic> map,
  ) {
    return NotificationModel(
      notificationId: notificationId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      userId: map[FSFields.userId]?.toString() ?? '',
      type: map['type']?.toString() ?? NotificationType.companyAlert,
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      relatedId: map['relatedId']?.toString(),
      deepLinkRoute: map['deepLinkRoute']?.toString(),
      dedupeKey: map['dedupeKey']?.toString(),
      isRead: map['isRead'] ?? false,
      readAt: FSTimestamp.tryParse(map['readAt']),
      isArchived: map[FSFields.isArchived] == true,
      archivedAt: FSTimestamp.tryParse(map[FSFields.archivedAt]),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
    );
  }

  factory NotificationModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Notification document ${doc.id} has no data.');
    }
    return NotificationModel.fromMap(doc.id, data);
  }

  NotificationModel copyWith({
    bool? isRead,
    DateTime? readAt,
    bool? isArchived,
    DateTime? archivedAt,
  }) {
    return NotificationModel(
      notificationId: notificationId,
      companyId: companyId,
      userId: userId,
      type: type,
      title: title,
      body: body,
      relatedId: relatedId,
      deepLinkRoute: deepLinkRoute,
      dedupeKey: dedupeKey,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt,
    );
  }
}
