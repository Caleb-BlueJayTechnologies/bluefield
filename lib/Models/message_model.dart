import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// A single message within a thread. Stored at
/// `companies/{companyId}/messageThreads/{threadId}/messages/{messageId}`.
///
/// companyId and threadId are duplicated onto this doc (not just implied
/// by its path) so a collectionGroup('messages') query can filter/sort
/// without an extra parent lookup per result — useful for things like
/// "all messages I've sent" across threads.
///
/// No per-message read receipts here — see MessageThreadModel.unreadCounts
/// for why unread tracking lives on the thread instead.
class MessageModel {
  final String messageId;
  final String threadId;
  final String companyId;

  final String senderUserId;

  final String body;

  final List<String> attachmentUrls;

  final bool isEdited;
  final DateTime? editedAt;

  /// Soft-deleted messages keep their doc (for thread integrity / other
  /// participants' scrollback) but hide the body behind this flag rather
  /// than being removed outright.
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedByUserId;

  final DateTime createdAt;

  const MessageModel({
    required this.messageId,
    required this.threadId,
    required this.companyId,
    required this.senderUserId,
    required this.body,
    required this.attachmentUrls,
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedByUserId,
    required this.createdAt,
  });

  /// What to display: the real body, or a placeholder if deleted.
  String get displayBody => isDeleted ? 'Message deleted' : body;

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'threadId': threadId,
      'senderUserId': senderUserId,
      'body': body,
      'attachmentUrls': attachmentUrls,
      'isEdited': isEdited,
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'deletedByUserId': deletedByUserId,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String threadId,
    required String companyId,
    required String senderUserId,
    required String body,
    List<String> attachmentUrls = const [],
  }) {
    return {
      FSFields.companyId: companyId,
      'threadId': threadId,
      'senderUserId': senderUserId,
      'body': body,
      'attachmentUrls': attachmentUrls,
      'isEdited': false,
      'editedAt': null,
      'isDeleted': false,
      'deletedAt': null,
      'deletedByUserId': null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
    };
  }

  factory MessageModel.fromMap(String messageId, Map<String, dynamic> map) {
    return MessageModel(
      messageId: messageId,
      threadId: map['threadId']?.toString() ?? '',
      companyId: map[FSFields.companyId]?.toString() ?? '',
      senderUserId: map['senderUserId']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      attachmentUrls: List<String>.from(map['attachmentUrls'] ?? []),
      isEdited: map['isEdited'] == true,
      editedAt: FSTimestamp.tryParse(map['editedAt']),
      isDeleted: map['isDeleted'] == true,
      deletedAt: FSTimestamp.tryParse(map['deletedAt']),
      deletedByUserId: map['deletedByUserId']?.toString(),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
    );
  }

  factory MessageModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Message document ${doc.id} has no data.');
    }
    return MessageModel.fromMap(doc.id, data);
  }

  MessageModel copyWith({
    String? body,
    List<String>? attachmentUrls,
    bool? isEdited,
    DateTime? editedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    String? deletedByUserId,
  }) {
    return MessageModel(
      messageId: messageId,
      threadId: threadId,
      companyId: companyId,
      senderUserId: senderUserId,
      body: body ?? this.body,
      attachmentUrls: attachmentUrls ?? this.attachmentUrls,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedByUserId: deletedByUserId ?? this.deletedByUserId,
      createdAt: createdAt,
    );
  }
}
