import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// What kind of conversation this thread is.
class ThreadType {
  ThreadType._();

  static const direct = 'direct'; // 1:1 or small explicit participant list
  static const crew = 'crew'; // tied to exactly one crew/team
  static const manager = 'manager'; // managers-only conversation
  static const companyWide = 'companyWide'; // all active employees
  static const job = 'job'; // tied to exactly one job

  /// A BlueJay platform admin messaging a company owner directly.
  /// Stored in the SAME per-company messageThreads subcollection as
  /// every other thread type (so it shows up in the owner's normal
  /// Messages screen via watchThreadsForUser without any special-case
  /// UI), but the admin side of this thread has no MembershipModel
  /// doc in that company at all — see MessagingService.sendMessage's
  /// platformSupport branch, which skips the usual company-membership
  /// check for exactly this thread type.
  static const platformSupport = 'platformSupport';

  static const all = [direct, crew, manager, companyWide, job, platformSupport];
}

/// A conversation thread. Stored at
/// `companies/{companyId}/messageThreads/{threadId}`. Messages live in
/// the `messages` subcollection beneath it — see message_model.dart.
///
/// Unread tracking is kept at the THREAD level (unreadCounts, a map of
/// userId -> count) rather than as a readByUserIds list on every single
/// message. A per-message read list means computing "is this unread"
/// requires scanning every message in the thread — the opposite of the
/// lazy-loading/pagination this app needs. Incrementing a thread-level
/// counter on send and zeroing it on open is a single small write
/// either way, regardless of how many messages exist.
class MessageThreadModel {
  final String threadId;
  final String companyId;

  final String type; // ThreadType.*

  /// Optional display title. Direct-message threads typically derive
  /// their displayed name from participants instead of using this.
  final String? title;

  final List<String> participantUserIds;

  /// Set only when type == ThreadType.crew. A crew thread's participant
  /// list should be kept in sync with crew membership by the service
  /// layer whenever an employee's crewId changes.
  final String? crewId;

  /// Set only when type == ThreadType.job.
  final String? jobId;

  /// Users who've archived their OWN view of this thread — not a
  /// global flag. Archiving hides the thread from that person's
  /// message list only; the thread and its full message history stay
  /// completely intact, and anyone still in this list keeps seeing it
  /// normally. A user is automatically removed from this list (i.e.
  /// un-archived) the moment a new message arrives in the thread —
  /// see MessagingService.sendMessage — so a recreated conversation
  /// "just pulls back up" for them instead of staying hidden.
  final List<String> archivedByUserIds;

  bool isArchivedFor(String userId) => archivedByUserIds.contains(userId);

  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;

  /// userId -> unread message count for that user in this thread.
  final Map<String, int> unreadCounts;

  final String createdByUserId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const MessageThreadModel({
    required this.threadId,
    required this.companyId,
    required this.type,
    this.title,
    required this.participantUserIds,
    this.crewId,
    this.jobId,
    this.archivedByUserIds = const [],
    this.lastMessagePreview,
    this.lastMessageAt,
    this.lastMessageSenderId,
    required this.unreadCounts,
    required this.createdByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  int unreadCountFor(String userId) => unreadCounts[userId] ?? 0;

  bool isParticipant(String userId) => participantUserIds.contains(userId);

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'type': type,
      'title': title,
      'participantUserIds': participantUserIds,
      FSFields.crewId: crewId,
      FSFields.jobId: jobId,
      'archivedByUserIds': archivedByUserIds,
      'lastMessagePreview': lastMessagePreview,
      'lastMessageAt':
          lastMessageAt != null ? Timestamp.fromDate(lastMessageAt!) : null,
      'lastMessageSenderId': lastMessageSenderId,
      'unreadCounts': unreadCounts,
      'createdByUserId': createdByUserId,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String type,
    String? title,
    required List<String> participantUserIds,
    String? crewId,
    String? jobId,
    required String createdByUserId,
  }) {
    return {
      FSFields.companyId: companyId,
      'type': type,
      'title': title,
      'participantUserIds': participantUserIds,
      FSFields.crewId: crewId,
      FSFields.jobId: jobId,
      'archivedByUserIds': <String>[],
      'lastMessagePreview': null,
      'lastMessageAt': null,
      'lastMessageSenderId': null,
      'unreadCounts': <String, int>{for (final id in participantUserIds) id: 0},
      'createdByUserId': createdByUserId,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  factory MessageThreadModel.fromMap(
    String threadId,
    Map<String, dynamic> map,
  ) {
    return MessageThreadModel(
      threadId: threadId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      type: map['type']?.toString() ?? ThreadType.direct,
      title: map['title']?.toString(),
      participantUserIds:
          List<String>.from(map['participantUserIds'] ?? []),
      crewId: map[FSFields.crewId]?.toString(),
      jobId: map[FSFields.jobId]?.toString(),
      archivedByUserIds: List<String>.from(map['archivedByUserIds'] ?? []),
      lastMessagePreview: map['lastMessagePreview']?.toString(),
      lastMessageAt: FSTimestamp.tryParse(map['lastMessageAt']),
      lastMessageSenderId: map['lastMessageSenderId']?.toString(),
      unreadCounts: Map<String, int>.from(
        (map['unreadCounts'] as Map<dynamic, dynamic>?)?.map(
              (key, value) => MapEntry(key.toString(), (value as num).toInt()),
            ) ??
            {},
      ),
      createdByUserId: map['createdByUserId']?.toString() ?? '',
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory MessageThreadModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Message thread document ${doc.id} has no data.');
    }
    return MessageThreadModel.fromMap(doc.id, data);
  }

  MessageThreadModel copyWith({
    String? type,
    String? title,
    List<String>? participantUserIds,
    String? crewId,
    String? jobId,
    List<String>? archivedByUserIds,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    Map<String, int>? unreadCounts,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MessageThreadModel(
      threadId: threadId,
      companyId: companyId,
      type: type ?? this.type,
      title: title ?? this.title,
      participantUserIds: participantUserIds ?? this.participantUserIds,
      crewId: crewId ?? this.crewId,
      jobId: jobId ?? this.jobId,
      archivedByUserIds: archivedByUserIds ?? this.archivedByUserIds,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      createdByUserId: createdByUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
