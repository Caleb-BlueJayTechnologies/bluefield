import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/membership.dart';
import '../Models/message_model.dart';
import '../Models/message_thread_model.dart';
import '../Models/notification_model.dart';
import 'kill_switch_service.dart';
import 'notification_service.dart';
import 'permission_service.dart';

/// Pairs a parsed MessageModel with its raw Firestore doc, so a screen
/// doing real pagination (Messenger-style: newest page live, older
/// history paged in as you scroll up) can use the doc as a cursor for
/// [MessagingService.getOlderMessages] without needing a second,
/// parallel list of raw snapshots.
class MessageWithDoc {
  final MessageModel message;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const MessageWithDoc({required this.message, required this.doc});
}

/// Messaging (Section 11). Two deliberate performance choices worth
/// knowing before calling into this:
///
/// 1. Only [watchLatestMessages] opens a live listener — it's capped at
///    a small page size. Scrolling up to see older history uses
///    [getOlderMessages], a one-time paginated fetch with a cursor, NOT
///    another listener. "Limit active listeners" from Section 11 means
///    exactly this: one live subscription per open thread, not one per
///    page of history.
/// 2. Unread counts live on the thread doc (see message_thread_model.dart)
///    rather than being computed by scanning messages, so opening a
///    thread with 10,000 messages costs the same as one with 10.
class MessagingService {
  final FirebaseFirestore _firestore;
  final NotificationService _notificationService;
  final KillSwitchService _killSwitchService;

  MessagingService({
    FirebaseFirestore? firestore,
    NotificationService? notificationService,
    KillSwitchService? killSwitchService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationService = notificationService ?? NotificationService(),
        _killSwitchService = killSwitchService ?? KillSwitchService();

  CollectionReference<Map<String, dynamic>> _threadsRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.messageThreads);
  }

  CollectionReference<Map<String, dynamic>> _messagesRef(
    String companyId,
    String threadId,
  ) {
    return _threadsRef(companyId).doc(threadId).collection(FSThreadSub.messages);
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

  Future<MembershipModel> _requireActiveMembership({
    required String companyId,
    required String userId,
  }) async {
    final doc = await _membershipsRef(companyId).doc(userId).get();
    if (!doc.exists) {
      throw Exception('You do not have access to this company.');
    }
    final membership = MembershipModel.fromSnapshot(doc);
    if (!membership.grantsAccess) {
      throw Exception('Your access to this company is not active.');
    }
    return membership;
  }

  Future<void> _requireThreadParticipant({
    required String companyId,
    required String threadId,
    required String userId,
  }) async {
    final threadDoc = await _threadsRef(companyId).doc(threadId).get();
    if (!threadDoc.exists) {
      throw Exception('Conversation was not found.');
    }
    final thread = MessageThreadModel.fromSnapshot(threadDoc);
    if (!thread.isParticipant(userId)) {
      throw Exception('You do not have access to this conversation.');
    }
  }

  String _sendPermissionForType(String threadType) {
    switch (threadType) {
      case ThreadType.crew:
        return Permission.messagingSendCrew;
      case ThreadType.companyWide:
        return Permission.messagingSendCompanyWide;
      case ThreadType.direct:
      case ThreadType.manager:
      case ThreadType.job:
      default:
        return Permission.messagingSendDirect;
    }
  }

  // --- Thread creation ---

  /// Returns an existing direct thread between exactly these two users
  /// if one exists, otherwise creates it — avoids spawning duplicate DM
  /// threads for the same pair of people.
  Future<String> getOrCreateDirectThread({
    required String companyId,
    required String userA,
    required String userB,
  }) async {
    await _requireActiveMembership(companyId: companyId, userId: userA);

    final existing = await _threadsRef(companyId)
        .where('type', isEqualTo: ThreadType.direct)
        .where('participantUserIds', arrayContains: userA)
        .get();

    for (final doc in existing.docs) {
      final thread = MessageThreadModel.fromSnapshot(doc);
      if (thread.participantUserIds.length == 2 &&
          thread.participantUserIds.contains(userB)) {
        return thread.threadId;
      }
    }

    final threadRef = _threadsRef(companyId).doc();
    await threadRef.set(MessageThreadModel.toMapForCreate(
      companyId: companyId,
      type: ThreadType.direct,
      participantUserIds: [userA, userB],
      createdByUserId: userA,
    ));
    return threadRef.id;
  }

  /// A BlueJay admin messaging a company owner directly — created
  /// under the SAME per-company messageThreads subcollection as every
  /// other thread type, so it appears in the owner's normal Messages
  /// screen with zero special-case UI on their end. Doesn't re-verify
  /// [adminUserId]'s platform-admin status itself; the admin panel
  /// screen calling this has already gated access via
  /// PlatformAdminService/AdminGateScreen before ever reaching here,
  /// same as other thread-creation methods in this file not
  /// re-checking every possible permission on every call.
  Future<String> getOrCreatePlatformSupportThread({
    required String companyId,
    required String adminUserId,
    required String ownerUserId,
  }) async {
    final existing = await _threadsRef(companyId)
        .where('type', isEqualTo: ThreadType.platformSupport)
        .where('participantUserIds', arrayContains: adminUserId)
        .get();

    for (final doc in existing.docs) {
      final thread = MessageThreadModel.fromSnapshot(doc);
      if (thread.participantUserIds.length == 2 &&
          thread.participantUserIds.contains(ownerUserId)) {
        return thread.threadId;
      }
    }

    final threadRef = _threadsRef(companyId).doc();
    await threadRef.set(MessageThreadModel.toMapForCreate(
      companyId: companyId,
      type: ThreadType.platformSupport,
      title: 'BlueJay Support',
      participantUserIds: [adminUserId, ownerUserId],
      createdByUserId: adminUserId,
    ));
    return threadRef.id;
  }

  /// One thread per crew. If it already exists, its participant list is
  /// refreshed to match current active crew membership rather than
  /// creating a second thread.
  /// Finds an existing crew thread's ID without creating one — used
  /// when crew membership changes (CrewService.addMemberToCrew /
  /// removeMemberFromCrew) to proactively keep an already-existing
  /// thread's participant list in sync. Returns null for a crew that's
  /// never had its chat opened, since there's nothing to sync yet and
  /// creating one just because membership changed would spawn chats
  /// nobody asked for.
  Future<String?> findCrewThreadId({
    required String companyId,
    required String crewId,
  }) async {
    final existing = await _threadsRef(companyId)
        .where('type', isEqualTo: ThreadType.crew)
        .where(FSFields.crewId, isEqualTo: crewId)
        .limit(1)
        .get();
    return existing.docs.isEmpty ? null : existing.docs.first.id;
  }

  Future<String> getOrCreateCrewThread({
    required String companyId,
    required String actingUserId,
    required String crewId,
    required String crewName,
  }) async {
    final existing = await _threadsRef(companyId)
        .where('type', isEqualTo: ThreadType.crew)
        .where(FSFields.crewId, isEqualTo: crewId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final threadId = existing.docs.first.id;
      await syncCrewThreadParticipants(companyId: companyId, threadId: threadId, crewId: crewId);
      return threadId;
    }

    final memberIds = await _activeCrewMemberIds(companyId, crewId);

    final threadRef = _threadsRef(companyId).doc();
    await threadRef.set(MessageThreadModel.toMapForCreate(
      companyId: companyId,
      type: ThreadType.crew,
      title: crewName,
      participantUserIds: memberIds,
      crewId: crewId,
      createdByUserId: actingUserId,
    ));
    return threadRef.id;
  }

  /// Crew members plus every owner/manager — leadership overseeing all
  /// internal communication is a reasonable expectation, and without
  /// this, an owner not personally assigned to a given crew would be
  /// silently excluded from both creating AND reading that crew's
  /// thread (Firestore rules key entirely off literal participant
  /// membership — there's no role-based bypass at the rules layer, so
  /// this has to be solved by making them a real participant).
  Future<List<String>> _activeCrewMemberIds(String companyId, String crewId) async {
    // FSFields.crewId is the legacy single-crew scalar field — new
    // employee docs only ever write the crewIds array (see
    // employee_model.dart). Querying the legacy field here meant this
    // always returned zero real crew members (only the leadership
    // fallback below ever populated), silently locking crew members
    // out of their own crew chat / job threads. crew_service.dart's
    // getActiveMembers already queries correctly — match it.
    final employeesSnapshot = await _employeesRef(companyId)
        .where('crewIds', arrayContains: crewId)
        .get();

    final membershipsSnapshot = await _membershipsRef(companyId)
        .where(FSFields.status, isEqualTo: FSMembershipStatus.active)
        .get();
    final membershipsById = {
      for (final d in membershipsSnapshot.docs) d.id: MembershipModel.fromSnapshot(d),
    };

    final crewMemberIds = employeesSnapshot.docs.map((d) => d.id).where(membershipsById.containsKey).toSet();

    final leadershipIds = membershipsById.entries
        .where((e) => e.value.role == FSRoles.owner || e.value.role == FSRoles.manager)
        .map((e) => e.key);

    return {...crewMemberIds, ...leadershipIds}.toList();
  }

  /// Call whenever crew membership changes (an employee's crewId is
  /// assigned/cleared) so the crew's chat participant list — and
  /// therefore who can read/send in it — stays correct. New joiners
  /// start at 0 unread; existing participants' counts are preserved.
  Future<void> syncCrewThreadParticipants({
    required String companyId,
    required String threadId,
    required String crewId,
  }) async {
    final memberIds = await _activeCrewMemberIds(companyId, crewId);
    final threadRef = _threadsRef(companyId).doc(threadId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(threadRef);
      if (!doc.exists) return;
      final thread = MessageThreadModel.fromSnapshot(doc);

      final updatedCounts = <String, int>{
        for (final id in memberIds) id: thread.unreadCounts[id] ?? 0,
      };

      transaction.update(threadRef, {
        'participantUserIds': memberIds,
        'unreadCounts': updatedCounts,
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  /// Job threads had no equivalent of syncCrewThreadParticipants until
  /// now — if a job's message thread was already created (e.g. the
  /// owner opened "Message" first) and someone was assigned to the
  /// job AFTERWARD, they were silently never added as a participant,
  /// since neither createJobThread caller only builds the list once,
  /// at creation time. This keeps an existing thread's participants in
  /// sync with the job's current assignments whenever they change.
  Future<void> syncJobThreadParticipants({
    required String companyId,
    required String threadId,
    required List<String> assignedEmployeeIds,
    required List<String> assignedCrewIds,
  }) async {
    final crewMemberIds = <String>{};
    // Independent per-crew lookups — fired concurrently instead of
    // awaited one at a time.
    final crewMemberIdLists = await Future.wait(
      assignedCrewIds.map((crewId) => _activeCrewMemberIds(companyId, crewId)),
    );
    for (final ids in crewMemberIdLists) {
      crewMemberIds.addAll(ids);
    }
    final participantIds = {...assignedEmployeeIds, ...crewMemberIds}.toList();

    final threadRef = _threadsRef(companyId).doc(threadId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(threadRef);
      if (!doc.exists) return;
      final thread = MessageThreadModel.fromSnapshot(doc);

      final updatedCounts = <String, int>{
        for (final id in participantIds) id: thread.unreadCounts[id] ?? 0,
      };

      transaction.update(threadRef, {
        'participantUserIds': participantIds,
        'unreadCounts': updatedCounts,
        FSFields.updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  Future<String> createJobThread({
    required String companyId,
    required String actingUserId,
    required String jobId,
    required String jobTitle,
    required List<String> participantUserIds,
  }) async {
    final threadRef = _threadsRef(companyId).doc();
    await threadRef.set(MessageThreadModel.toMapForCreate(
      companyId: companyId,
      type: ThreadType.job,
      title: jobTitle,
      participantUserIds: participantUserIds,
      jobId: jobId,
      createdByUserId: actingUserId,
    ));
    return threadRef.id;
  }

  Future<String> createCompanyWideThread({
    required String companyId,
    required String actingUserId,
    required List<String> allActiveUserIds,
  }) async {
    final membership =
        await _requireActiveMembership(companyId: companyId, userId: actingUserId);
    if (!PermissionService.roleHasPermission(
        membership.role, Permission.messagingSendCompanyWide)) {
      throw Exception('You do not have permission to start a company-wide conversation.');
    }

    final threadRef = _threadsRef(companyId).doc();
    await threadRef.set(MessageThreadModel.toMapForCreate(
      companyId: companyId,
      type: ThreadType.companyWide,
      title: 'Company-wide',
      participantUserIds: allActiveUserIds,
      createdByUserId: actingUserId,
    ));
    return threadRef.id;
  }

  // --- Thread reads ---

  Future<List<MessageThreadModel>> getThreadsForUser({
    required String companyId,
    required String userId,
  }) async {
    final snapshot = await _threadsRef(companyId)
        .where('participantUserIds', arrayContains: userId)
        .get();
    final threads = snapshot.docs
        .map((d) => MessageThreadModel.fromSnapshot(d))
        .where((t) => !t.isArchivedFor(userId))
        .toList()
      ..sort((a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));
    return threads;
  }

  Stream<List<MessageThreadModel>> watchThreadsForUser({
    required String companyId,
    required String userId,
  }) {
    return _threadsRef(companyId)
        .where('participantUserIds', arrayContains: userId)
        .snapshots()
        .map((snap) {
      final threads = snap.docs
          .map((d) => MessageThreadModel.fromSnapshot(d))
          .where((t) => !t.isArchivedFor(userId))
          .toList()
        ..sort((a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));
      return threads;
    });
  }

  /// Threads the user has archived — for the Archived view, so nothing
  /// is ever actually lost, just hidden from the default list.
  Stream<List<MessageThreadModel>> watchArchivedThreadsForUser({
    required String companyId,
    required String userId,
  }) {
    return _threadsRef(companyId)
        .where('participantUserIds', arrayContains: userId)
        .snapshots()
        .map((snap) {
      final threads = snap.docs
          .map((d) => MessageThreadModel.fromSnapshot(d))
          .where((t) => t.isArchivedFor(userId))
          .toList()
        ..sort((a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));
      return threads;
    });
  }

  Future<void> archiveThreadForUser({
    required String companyId,
    required String threadId,
    required String userId,
  }) async {
    await _threadsRef(companyId).doc(threadId).update({
      'archivedByUserIds': FieldValue.arrayUnion([userId]),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> unarchiveThreadForUser({
    required String companyId,
    required String threadId,
    required String userId,
  }) async {
    await _threadsRef(companyId).doc(threadId).update({
      'archivedByUserIds': FieldValue.arrayRemove([userId]),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  Stream<MessageThreadModel?> watchThread({
    required String companyId,
    required String threadId,
  }) {
    return _threadsRef(companyId)
        .doc(threadId)
        .snapshots()
        .map((doc) => doc.exists ? MessageThreadModel.fromSnapshot(doc) : null);
  }

  // --- Messages: live newest page + paginated older history ---

  /// The ONLY listener a message screen should open — the newest
  /// [limit] messages, live. Older history comes from [getOlderMessages]
  /// instead of extending this listener's page size.
  Stream<List<MessageWithDoc>> watchLatestMessages({
    required String companyId,
    required String threadId,
    int limit = 30,
  }) {
    return _messagesRef(companyId, threadId)
        .orderBy(FSFields.createdAt, descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => MessageWithDoc(message: MessageModel.fromSnapshot(d), doc: d)).toList());
  }

  /// One-time fetch of the page of messages older than [beforeDoc] (pass
  /// the last DocumentSnapshot from the previous page — screens should
  /// keep the raw QueryDocumentSnapshot around for this, not just the
  /// parsed model). No listener is attached.
  Future<List<MessageWithDoc>> getOlderMessages({
    required String companyId,
    required String threadId,
    required DocumentSnapshot<Map<String, dynamic>> beforeDoc,
    int limit = 30,
  }) async {
    final snapshot = await _messagesRef(companyId, threadId)
        .orderBy(FSFields.createdAt, descending: true)
        .startAfterDocument(beforeDoc)
        .limit(limit)
        .get();
    return snapshot.docs.map((d) => MessageWithDoc(message: MessageModel.fromSnapshot(d), doc: d)).toList();
  }

  // --- Sending / editing / deleting ---

  Future<void> sendMessage({
    required String companyId,
    required String threadId,
    required String senderUserId,
    required String body,
    List<String> attachmentUrls = const [],
  }) async {
    // Platform-wide emergency switch — lets a platform admin instantly
    // stop new messages being sent for every company at once during an
    // incident, without a deploy. See KillSwitchModel's doc comment.
    // Reading existing threads/messages is deliberately left alone —
    // this only blocks sending new ones.
    if (await _killSwitchService.isKilled('messaging')) {
      throw Exception('Messaging is temporarily disabled. Please try again shortly.');
    }

    final threadRef = _threadsRef(companyId).doc(threadId);
    final threadDoc = await threadRef.get();
    if (!threadDoc.exists) throw Exception('Conversation was not found.');
    var thread = MessageThreadModel.fromSnapshot(threadDoc);

    // platformSupport threads are the one exception to the usual
    // company-membership + role-permission check below: a BlueJay
    // admin has no MembershipModel doc in the company they're
    // messaging into at all. Their authorization already happened at
    // thread-creation time (PlatformAdminService.canManageTickets),
    // and being a verified thread participant here is sufficient —
    // the owner's side of the same thread is a normal company member
    // and doesn't need any special-casing.
    MembershipModel? membership;
    if (thread.type != ThreadType.platformSupport) {
      membership = await _requireActiveMembership(companyId: companyId, userId: senderUserId);
    }
    final isOwner = membership?.role == FSRoles.owner;

    if (!thread.isParticipant(senderUserId)) {
      // A company owner should never be structurally locked out of
      // their own company's internal communication — this is the
      // same case the crew-thread participant fix and the rules'
      // owner fallback both address, just at the send step. Auto-heal
      // the thread by adding them as a REAL participant here rather
      // than special-casing "owner" forever at every read/write site.
      if (isOwner) {
        await threadRef.update({
          'participantUserIds': FieldValue.arrayUnion([senderUserId]),
          'unreadCounts.$senderUserId': 0,
        });
        final refreshed = await threadRef.get();
        thread = MessageThreadModel.fromSnapshot(refreshed);
      } else {
        throw Exception('You do not have access to this conversation.');
      }
    }

    if (thread.type != ThreadType.platformSupport && membership != null) {
      if (!PermissionService.roleHasPermission(
          membership.role, _sendPermissionForType(thread.type))) {
        throw Exception('You do not have permission to send in this conversation.');
      }
    }

    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty && attachmentUrls.isEmpty) {
      throw Exception('Message cannot be empty.');
    }

    final messageRef = _messagesRef(companyId, threadId).doc();
    final preview =
        trimmedBody.length > 120 ? '${trimmedBody.substring(0, 117)}...' : trimmedBody;

    final batch = _firestore.batch();

    batch.set(
        messageRef,
        MessageModel.toMapForCreate(
          threadId: threadId,
          companyId: companyId,
          senderUserId: senderUserId,
          body: trimmedBody,
          attachmentUrls: attachmentUrls,
        ));

    final updatedCounts = <String, int>{...thread.unreadCounts};
    for (final participantId in thread.participantUserIds) {
      if (participantId == senderUserId) continue;
      updatedCounts[participantId] = (updatedCounts[participantId] ?? 0) + 1;
    }

    batch.update(threadRef, {
      'lastMessagePreview': preview.isEmpty ? '[Attachment]' : preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderUserId,
      'unreadCounts': updatedCounts,
      // A new message un-archives the thread for EVERY participant,
      // not just whoever archived it — this is what makes a
      // recreated conversation "just pull back up as if nothing
      // happened" instead of staying silently hidden for someone who
      // archived it earlier.
      'archivedByUserIds': <String>[],
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Notify every other participant — best-effort, never blocks the
    // message itself, which has already sent successfully above.
    try {
      final recipients = thread.participantUserIds.where((id) => id != senderUserId).toList();
      if (recipients.isNotEmpty) {
        await _notificationService.notifyMultipleUsers(
          companyId: companyId,
          userIds: recipients,
          type: NotificationType.newMessage,
          title: thread.title?.trim().isNotEmpty == true ? thread.title! : 'New Message',
          body: preview.isEmpty ? '[Attachment]' : preview,
          relatedId: threadId,
        );
      }
    } catch (_) {
      // Non-fatal — the message itself is already sent.
    }
  }

  Future<void> editMessage({
    required String companyId,
    required String threadId,
    required String messageId,
    required String actingUserId,
    required String newBody,
  }) async {
    await _requireThreadParticipant(
        companyId: companyId, threadId: threadId, userId: actingUserId);

    final messageRef = _messagesRef(companyId, threadId).doc(messageId);
    final doc = await messageRef.get();
    if (!doc.exists) throw Exception('Message was not found.');
    final message = MessageModel.fromSnapshot(doc);

    final membership =
        await _requireActiveMembership(companyId: companyId, userId: actingUserId);
    final isModerator =
        PermissionService.roleHasPermission(membership.role, Permission.messagingModerate);

    if (message.senderUserId != actingUserId && !isModerator) {
      throw Exception('You can only edit your own messages.');
    }

    final trimmed = newBody.trim();
    if (trimmed.isEmpty) throw Exception('Message cannot be empty.');

    await messageRef.update({
      'body': trimmed,
      'isEdited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessage({
    required String companyId,
    required String threadId,
    required String messageId,
    required String actingUserId,
  }) async {
    await _requireThreadParticipant(
        companyId: companyId, threadId: threadId, userId: actingUserId);

    final messageRef = _messagesRef(companyId, threadId).doc(messageId);
    final doc = await messageRef.get();
    if (!doc.exists) throw Exception('Message was not found.');
    final message = MessageModel.fromSnapshot(doc);

    final membership =
        await _requireActiveMembership(companyId: companyId, userId: actingUserId);
    final isModerator =
        PermissionService.roleHasPermission(membership.role, Permission.messagingModerate);

    if (message.senderUserId != actingUserId && !isModerator) {
      throw Exception('You can only delete your own messages.');
    }

    await messageRef.update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedByUserId': actingUserId,
    });
  }

  // --- Read tracking ---

  Future<void> markThreadRead({
    required String companyId,
    required String threadId,
    required String userId,
  }) async {
    await _threadsRef(companyId).doc(threadId).update({
      'unreadCounts.$userId': 0,
    });
  }
}
