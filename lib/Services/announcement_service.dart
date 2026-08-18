import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/announcement_model.dart';
import '../Models/membership.dart';
import '../Models/notification_model.dart';
import 'notification_service.dart';
import 'permission_service.dart';

/// Announcements live at
/// `companies/{companyId}/announcements/{announcementId}`. No service
/// existed for this collection even though announcement_model.dart was
/// fully built — every announcement screen needs the same create/watch/
/// archive logic, so it lives here once instead of four times.
class AnnouncementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  CollectionReference<Map<String, dynamic>> _announcementsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.announcements);
  }

  CollectionReference<Map<String, dynamic>> _employeesRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.employees);
  }

  CollectionReference<Map<String, dynamic>> _membershipsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships);
  }

  /// Every active member a new announcement should notify, mirroring
  /// watchVisibleAnnouncements' own targeting switch so "who gets
  /// notified" never diverges from "who can actually see it." Excludes
  /// [excludeUserId] (the poster) — nobody needs a notification telling
  /// them about their own announcement.
  Future<List<String>> _resolveAudience({
    required String companyId,
    required String targetType,
    required List<String> targetCrewIds,
    required List<String> targetUserIds,
    required String excludeUserId,
  }) async {
    final membershipsSnapshot = await _membershipsRef(companyId)
        .where(FSFields.status, isEqualTo: FSMembershipStatus.active)
        .get();
    final membershipsById = {
      for (final d in membershipsSnapshot.docs) d.id: MembershipModel.fromSnapshot(d),
    };

    List<String> audience;
    switch (targetType) {
      case AnnouncementTargetType.employees:
        audience = targetUserIds.where(membershipsById.containsKey).toList();
        break;

      case AnnouncementTargetType.managersOnly:
        audience = membershipsById.values
            .where((m) => m.role == FSRoles.owner || m.role == FSRoles.manager)
            .map((m) => m.userId)
            .toList();
        break;

      case AnnouncementTargetType.crew:
        if (targetCrewIds.isEmpty) {
          audience = const [];
          break;
        }
        final memberIds = <String>{};
        // arrayContainsAny is capped at 30 values per query.
        for (var i = 0; i < targetCrewIds.length; i += 30) {
          final chunk = targetCrewIds.sublist(i, i + 30 > targetCrewIds.length ? targetCrewIds.length : i + 30);
          final employeesSnapshot =
              await _employeesRef(companyId).where('crewIds', arrayContainsAny: chunk).get();
          memberIds.addAll(employeesSnapshot.docs.map((d) => d.id));
        }
        audience = memberIds.where(membershipsById.containsKey).toList();
        break;

      case AnnouncementTargetType.companyWide:
      default:
        audience = membershipsById.keys.toList();
    }

    return audience.where((id) => id != excludeUserId).toList();
  }

  Future<void> _requirePermission({
    required String companyId,
    required String userId,
    required String permission,
  }) async {
    final membershipDoc = await _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.memberships)
        .doc(userId)
        .get();

    if (!membershipDoc.exists) {
      throw Exception('You do not have access to this company.');
    }

    final membership = MembershipModel.fromSnapshot(membershipDoc);
    if (!PermissionService.roleHasPermission(membership.role, permission)) {
      throw Exception('You do not have permission to do that.');
    }
  }

  Future<String> createAnnouncement({
    required String companyId,
    required String actingUserId,
    required String title,
    required String body,
    String targetType = AnnouncementTargetType.companyWide,
    List<String> targetCrewIds = const [],
    List<String> targetUserIds = const [],
    bool isPinned = false,
    DateTime? expiresAt,
  }) async {
    await _requirePermission(
      companyId: companyId,
      userId: actingUserId,
      permission: Permission.announcementsCreate,
    );

    final ref = _announcementsRef(companyId).doc();
    await ref.set(AnnouncementModel.toMapForCreate(
      companyId: companyId,
      title: title,
      body: body,
      targetType: targetType,
      targetCrewIds: targetCrewIds,
      targetUserIds: targetUserIds,
      isPinned: isPinned,
      createdByUserId: actingUserId,
      expiresAt: expiresAt,
    ));

    // Best-effort — the announcement itself already exists above
    // regardless of whether notifying its audience succeeds. Was
    // previously entirely missing: NotificationService already had a
    // notifyNewAnnouncement-shaped event type wired up, but nothing
    // ever called it, so posting an announcement never produced a
    // notification or unread badge for anyone.
    try {
      final audience = await _resolveAudience(
        companyId: companyId,
        targetType: targetType,
        targetCrewIds: targetCrewIds,
        targetUserIds: targetUserIds,
        excludeUserId: actingUserId,
      );
      if (audience.isNotEmpty) {
        await _notificationService.notifyMultipleUsers(
          companyId: companyId,
          userIds: audience,
          type: NotificationType.newAnnouncement,
          title: 'New announcement',
          body: title,
          relatedId: ref.id,
          deepLinkRoute: '/announcements/detail',
        );
      }
    } catch (_) {
      // Notification fan-out failing shouldn't undo or block the
      // already-created announcement.
    }

    return ref.id;
  }

  Future<void> updateAnnouncement({
    required String companyId,
    required String actingUserId,
    required String announcementId,
    String? title,
    String? body,
    String? targetType,
    List<String>? targetCrewIds,
    List<String>? targetUserIds,
    bool? isPinned,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
  }) async {
    await _requirePermission(
      companyId: companyId,
      userId: actingUserId,
      permission: Permission.announcementsEdit,
    );

    final updates = <String, dynamic>{
      'editedBy': actingUserId,
      'editedAt': FieldValue.serverTimestamp(),
    };
    if (title != null) updates['title'] = title;
    if (body != null) updates['body'] = body;
    if (targetType != null) updates['targetType'] = targetType;
    if (targetCrewIds != null) updates['targetCrewIds'] = targetCrewIds;
    if (targetUserIds != null) updates['targetUserIds'] = targetUserIds;
    if (isPinned != null) updates['isPinned'] = isPinned;
    if (clearExpiresAt) {
      updates['expiresAt'] = null;
    } else if (expiresAt != null) {
      updates['expiresAt'] = Timestamp.fromDate(expiresAt);
    }

    await _announcementsRef(companyId).doc(announcementId).update(updates);
  }

  Future<void> archiveAnnouncement({
    required String companyId,
    required String actingUserId,
    required String announcementId,
  }) async {
    await _requirePermission(
      companyId: companyId,
      userId: actingUserId,
      permission: Permission.announcementsArchive,
    );

    await _announcementsRef(companyId).doc(announcementId).update({
      FSFields.isArchived: true,
      FSFields.archivedAt: FieldValue.serverTimestamp(),
      FSFields.archivedBy: actingUserId,
    });
  }

  Future<AnnouncementModel?> getAnnouncement({
    required String companyId,
    required String announcementId,
  }) async {
    final doc = await _announcementsRef(companyId).doc(announcementId).get();
    if (!doc.exists) return null;
    return AnnouncementModel.fromSnapshot(doc);
  }

  /// All non-archived announcements for the company, regardless of
  /// draft/expiry — the management list view.
  Stream<List<AnnouncementModel>> watchAllAnnouncements(String companyId) {
    return _announcementsRef(companyId)
        .where(FSFields.isArchived, isEqualTo: false)
        .orderBy(FSFields.createdAt, descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AnnouncementModel.fromSnapshot(d)).toList()
          ..sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          }));
  }

  /// Announcements actually visible to one employee: not draft, not
  /// archived, not expired, and targeted at them — companyWide, their
  /// crew, them directly, or managersOnly if they have that permission.
  Stream<List<AnnouncementModel>> watchVisibleAnnouncements({
    required String companyId,
    required String userId,
    List<String> crewIds = const [],
    required String role,
  }) {
    return watchAllAnnouncements(companyId).map((all) {
      final isManager = PermissionService.roleHasPermission(role, Permission.announcementsCreate);
      return all.where((a) {
        if (!a.isVisible) return false;
        switch (a.targetType) {
          case AnnouncementTargetType.companyWide:
            return true;
          case AnnouncementTargetType.crew:
            return crewIds.any((c) => a.targetCrewIds.contains(c));
          case AnnouncementTargetType.employees:
            return a.targetUserIds.contains(userId);
          case AnnouncementTargetType.managersOnly:
            return isManager;
          default:
            return false;
        }
      }).toList();
    });
  }
}
