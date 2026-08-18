import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/notification_model.dart';

/// In-app notifications (Section 13).
///
/// Scope note on PUSH notifications: this service maintains the device
/// token registry (registerDeviceToken/unregisterDeviceToken) that a
/// Cloud Function would read to actually send a push via FCM — but
/// sending the push itself has to happen server-side (a Cloud Function
/// triggered on notification creation), which is infrastructure/config
/// work, not something a Dart client service can do. That Cloud
/// Function is covered under Section 20 and isn't built here.
class NotificationService {
  final FirebaseFirestore _firestore;

  NotificationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _notificationsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.notifications);
  }

  CollectionReference<Map<String, dynamic>> _devicesRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.devices);
  }

  /// Sanitizes a dedupe key into a valid Firestore document ID (no
  /// slashes) so it can be used directly as the doc ID for idempotent
  /// creation — writing to the same ID twice just overwrites rather
  /// than creating a duplicate notification.
  String _sanitizeDocId(String key) => key.replaceAll('/', '_');

  // --- Read ---

  Future<List<NotificationModel>> getNotifications({
    required String companyId,
    required String userId,
    int limit = 50,
    bool includeArchived = false,
  }) async {
    Query<Map<String, dynamic>> query = _notificationsRef(companyId)
        .where(FSFields.userId, isEqualTo: userId);
    if (!includeArchived) {
      query = query.where(FSFields.isArchived, isEqualTo: false);
    }
    query = query.orderBy(FSFields.createdAt, descending: true).limit(limit);

    final snapshot = await query.get();
    return snapshot.docs.map((d) => NotificationModel.fromSnapshot(d)).toList();
  }

  Stream<List<NotificationModel>> watchNotifications({
    required String companyId,
    required String userId,
    int limit = 50,
    bool includeArchived = false,
  }) {
    Query<Map<String, dynamic>> query = _notificationsRef(companyId)
        .where(FSFields.userId, isEqualTo: userId);
    if (!includeArchived) {
      query = query.where(FSFields.isArchived, isEqualTo: false);
    }
    query = query.orderBy(FSFields.createdAt, descending: true).limit(limit);

    return query.snapshots().map(
        (snap) => snap.docs.map((d) => NotificationModel.fromSnapshot(d)).toList());
  }

  /// Live unread badge count. Capped at 200 for the count query itself —
  /// realistically no one has more than a couple hundred unread
  /// notifications at once, and this avoids an unbounded scan.
  Stream<int> watchUnreadCount({
    required String companyId,
    required String userId,
  }) {
    return _notificationsRef(companyId)
        .where(FSFields.userId, isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .where(FSFields.isArchived, isEqualTo: false)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // --- Mark read / archive ---

  Future<void> markAsRead({
    required String companyId,
    required String notificationId,
  }) async {
    await _notificationsRef(companyId).doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks every unread notification for [userId] as read, in batches of
  /// 500 (Firestore's per-batch write limit).
  Future<void> markAllAsRead({
    required String companyId,
    required String userId,
  }) async {
    final snapshot = await _notificationsRef(companyId)
        .where(FSFields.userId, isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    await _batchedUpdate(snapshot.docs, {
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archiveNotification({
    required String companyId,
    required String notificationId,
  }) async {
    await _notificationsRef(companyId).doc(notificationId).update({
      FSFields.isArchived: true,
      FSFields.archivedAt: FieldValue.serverTimestamp(),
    });
  }

  /// Bulk-archives notifications older than [olderThanDays] for
  /// housekeeping — call periodically (e.g. from a settings screen
  /// action or a future scheduled Cloud Function).
  Future<int> archiveNotificationsOlderThan({
    required String companyId,
    required String userId,
    int olderThanDays = 90,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    final snapshot = await _notificationsRef(companyId)
        .where(FSFields.userId, isEqualTo: userId)
        .where(FSFields.createdAt, isLessThan: Timestamp.fromDate(cutoff))
        .where(FSFields.isArchived, isEqualTo: false)
        .get();

    await _batchedUpdate(snapshot.docs, {
      FSFields.isArchived: true,
      FSFields.archivedAt: FieldValue.serverTimestamp(),
    });

    return snapshot.docs.length;
  }

  Future<void> _batchedUpdate(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, dynamic> updates,
  ) async {
    const chunkSize = 500;
    for (var i = 0; i < docs.length; i += chunkSize) {
      final chunk = docs.skip(i).take(chunkSize);
      final batch = _firestore.batch();
      for (final doc in chunk) {
        batch.update(doc.reference, updates);
      }
      await batch.commit();
    }
  }

  // --- Creation ---

  /// Core creator. If [dedupeKey] is provided, it's used as the
  /// document ID so re-triggering the same event (e.g. saving a job
  /// assignment twice) overwrites the existing notification instead of
  /// creating a duplicate. Leave it null for events that legitimately
  /// repeat (e.g. newMessage — each message should get its own
  /// notification).
  Future<void> createNotification({
    required String companyId,
    required String userId,
    required String type,
    required String title,
    required String body,
    String? relatedId,
    String? deepLinkRoute,
    String? dedupeKey,
  }) async {
    final data = NotificationModel.toMapForCreate(
      companyId: companyId,
      userId: userId,
      type: type,
      title: title,
      body: body,
      relatedId: relatedId,
      deepLinkRoute: deepLinkRoute,
      dedupeKey: dedupeKey,
    );

    if (dedupeKey != null && dedupeKey.trim().isNotEmpty) {
      await _notificationsRef(companyId).doc(_sanitizeDocId(dedupeKey)).set(data);
    } else {
      await _notificationsRef(companyId).doc().set(data);
    }
  }

  Future<void> notifyMultipleUsers({
    required String companyId,
    required List<String> userIds,
    required String type,
    required String title,
    required String body,
    String? relatedId,
    String? deepLinkRoute,
  }) async {
    const chunkSize = 500;
    for (var i = 0; i < userIds.length; i += chunkSize) {
      final chunk = userIds.skip(i).take(chunkSize);
      final batch = _firestore.batch();
      for (final userId in chunk) {
        final ref = _notificationsRef(companyId).doc();
        batch.set(
            ref,
            NotificationModel.toMapForCreate(
              companyId: companyId,
              userId: userId,
              type: type,
              title: title,
              body: body,
              relatedId: relatedId,
              deepLinkRoute: deepLinkRoute,
            ));
      }
      await batch.commit();
    }
  }

  // --- Event-specific convenience creators ---

  Future<void> notifyScheduleAssignment({
    required String companyId,
    required String userId,
    required String scheduleId,
    required String scheduleTitle,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.scheduleAssignment,
      title: 'New schedule assignment',
      body: 'You\'ve been scheduled for "$scheduleTitle".',
      relatedId: scheduleId,
      deepLinkRoute: '/schedule/detail',
      dedupeKey: '${NotificationType.scheduleAssignment}:$scheduleId:$userId',
    );
  }

  Future<void> notifyScheduleChange({
    required String companyId,
    required String userId,
    required String scheduleId,
    required String scheduleTitle,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.scheduleChange,
      title: 'Schedule updated',
      body: '"$scheduleTitle" was changed.',
      relatedId: scheduleId,
      deepLinkRoute: '/schedule/detail',
    );
  }

  Future<void> notifyJobAssignment({
    required String companyId,
    required String userId,
    required String jobId,
    required String jobTitle,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.jobAssignment,
      title: 'New job assignment',
      body: 'You\'ve been assigned to "$jobTitle".',
      relatedId: jobId,
      deepLinkRoute: '/jobs/detail',
      dedupeKey: '${NotificationType.jobAssignment}:$jobId:$userId',
    );
  }

  Future<void> notifyJobCancellation({
    required String companyId,
    required String userId,
    required String jobId,
    required String jobTitle,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.jobCancellation,
      title: 'Job cancelled',
      body: '"$jobTitle" was cancelled.',
      relatedId: jobId,
      deepLinkRoute: '/jobs/detail',
    );
  }

  Future<void> notifyNewMessage({
    required String companyId,
    required String userId,
    required String threadId,
    required String senderName,
    required String preview,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.newMessage,
      title: senderName,
      body: preview,
      relatedId: threadId,
      deepLinkRoute: '/messages/conversation',
      // No dedupeKey — every message is its own notification.
    );
  }

  Future<void> notifyNewAnnouncement({
    required String companyId,
    required String userId,
    required String announcementId,
    required String announcementTitle,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.newAnnouncement,
      title: 'New announcement',
      body: announcementTitle,
      relatedId: announcementId,
      deepLinkRoute: '/announcements/detail',
      dedupeKey: '${NotificationType.newAnnouncement}:$announcementId:$userId',
    );
  }

  Future<void> notifyTimeOffDecision({
    required String companyId,
    required String userId,
    required String requestId,
    required bool approved,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.timeOffDecision,
      title: 'Time off request ${approved ? 'approved' : 'rejected'}',
      body: approved
          ? 'Your time off request was approved.'
          : 'Your time off request was not approved.',
      relatedId: requestId,
      deepLinkRoute: '/time-off/detail',
      dedupeKey: '${NotificationType.timeOffDecision}:$requestId:$userId',
    );
  }

  Future<void> notifyCorrectionDecision({
    required String companyId,
    required String userId,
    required String requestId,
    required bool approved,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.correctionDecision,
      title: 'Time correction ${approved ? 'approved' : 'rejected'}',
      body: approved
          ? 'Your correction request was approved.'
          : 'Your correction request was not approved.',
      relatedId: requestId,
      deepLinkRoute: '/time/corrections',
      dedupeKey: '${NotificationType.correctionDecision}:$requestId:$userId',
    );
  }

  Future<void> notifyPendingApproval({
    required String companyId,
    required String managerUserId,
    required String relatedId,
    required String description,
    required String deepLinkRoute,
  }) {
    return createNotification(
      companyId: companyId,
      userId: managerUserId,
      type: NotificationType.pendingApproval,
      title: 'Approval needed',
      body: description,
      relatedId: relatedId,
      deepLinkRoute: deepLinkRoute,
    );
  }

  Future<void> notifyEmployeeInvitation({
    required String companyId,
    required String userId,
    required String companyName,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.employeeInvitation,
      title: 'You\'ve been invited',
      body: 'You\'ve been invited to join $companyName on BlueField.',
      deepLinkRoute: '/invitations',
    );
  }

  Future<void> notifyCompanyAlert({
    required String companyId,
    required String userId,
    required String title,
    required String body,
  }) {
    return createNotification(
      companyId: companyId,
      userId: userId,
      type: NotificationType.companyAlert,
      title: title,
      body: body,
    );
  }

  // --- Device token registry (feeds a future push-sending Cloud Function) ---

  Future<void> registerDeviceToken({
    required String companyId,
    required String userId,
    required String token,
    required String platform, // 'ios' | 'android' | 'web'
  }) async {
    await _devicesRef(companyId).doc(_sanitizeDocId(token)).set({
      FSFields.userId: userId,
      'platform': platform,
      'registeredAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unregisterDeviceToken({
    required String companyId,
    required String token,
  }) async {
    await _devicesRef(companyId).doc(_sanitizeDocId(token)).delete();
  }

  Future<List<String>> getDeviceTokensForUser({
    required String companyId,
    required String userId,
  }) async {
    final snapshot =
        await _devicesRef(companyId).where(FSFields.userId, isEqualTo: userId).get();
    return snapshot.docs.map((d) => d.id).toList();
  }
}
