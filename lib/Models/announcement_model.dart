import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// Who an announcement is aimed at.
class AnnouncementTargetType {
  AnnouncementTargetType._();

  static const companyWide = 'companyWide';
  static const crew = 'crew'; // uses targetCrewIds
  static const employees = 'employees'; // uses targetUserIds
  static const managersOnly = 'managersOnly';
}

/// A company announcement. Stored at
/// `companies/{companyId}/announcements/{announcementId}`.
class AnnouncementModel {
  final String announcementId;
  final String companyId;

  final String title;
  final String body;

  final String targetType; // AnnouncementTargetType.*
  final List<String> targetCrewIds;
  final List<String> targetUserIds;

  final bool isPinned;

  /// Reserved for the future draft/publish workflow (planned but
  /// deferred past v1). Defaults to false — every announcement created
  /// today is effectively published immediately. Included now with a
  /// safe default so this file doesn't need to be reopened just to add
  /// a boolean later.
  final bool isDraft;

  final bool isArchived;
  final DateTime? archivedAt;
  final String? archivedBy;

  final String? editedBy;
  final DateTime? editedAt;

  final String createdByUserId;

  final DateTime createdAt;
  final DateTime? expiresAt;

  const AnnouncementModel({
    required this.announcementId,
    required this.companyId,
    required this.title,
    required this.body,
    required this.targetType,
    required this.targetCrewIds,
    required this.targetUserIds,
    required this.isPinned,
    this.isDraft = false,
    this.isArchived = false,
    this.archivedAt,
    this.archivedBy,
    this.editedBy,
    this.editedAt,
    required this.createdByUserId,
    required this.createdAt,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isVisible => !isDraft && !isArchived && !isExpired;
  bool get isEdited => editedAt != null;

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'title': title,
      'body': body,
      'targetType': targetType,
      'targetCrewIds': targetCrewIds,
      'targetUserIds': targetUserIds,
      'isPinned': isPinned,
      'isDraft': isDraft,
      FSFields.isArchived: isArchived,
      FSFields.archivedAt:
          archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      FSFields.archivedBy: archivedBy,
      'editedBy': editedBy,
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,
      'createdByUserId': createdByUserId,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String title,
    required String body,
    required String targetType,
    List<String> targetCrewIds = const [],
    List<String> targetUserIds = const [],
    bool isPinned = false,
    bool isDraft = false,
    required String createdByUserId,
    DateTime? expiresAt,
  }) {
    return {
      FSFields.companyId: companyId,
      'title': title,
      'body': body,
      'targetType': targetType,
      'targetCrewIds': targetCrewIds,
      'targetUserIds': targetUserIds,
      'isPinned': isPinned,
      'isDraft': isDraft,
      FSFields.isArchived: false,
      FSFields.archivedAt: null,
      FSFields.archivedBy: null,
      'editedBy': null,
      'editedAt': null,
      'createdByUserId': createdByUserId,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
    };
  }

  factory AnnouncementModel.fromMap(
    String announcementId,
    Map<String, dynamic> map,
  ) {
    return AnnouncementModel(
      announcementId: announcementId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      targetType:
          map['targetType']?.toString() ?? AnnouncementTargetType.companyWide,
      targetCrewIds: List<String>.from(map['targetCrewIds'] ?? []),
      targetUserIds: List<String>.from(map['targetUserIds'] ?? []),
      isPinned: map['isPinned'] ?? false,
      isDraft: map['isDraft'] == true,
      isArchived: map[FSFields.isArchived] == true,
      archivedAt: FSTimestamp.tryParse(map[FSFields.archivedAt]),
      archivedBy: map[FSFields.archivedBy]?.toString(),
      editedBy: map['editedBy']?.toString(),
      editedAt: FSTimestamp.tryParse(map['editedAt']),
      createdByUserId: map['createdByUserId']?.toString() ?? '',
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      expiresAt: FSTimestamp.tryParse(map['expiresAt']),
    );
  }

  factory AnnouncementModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Announcement document ${doc.id} has no data.');
    }
    return AnnouncementModel.fromMap(doc.id, data);
  }

  AnnouncementModel copyWith({
    String? title,
    String? body,
    String? targetType,
    List<String>? targetCrewIds,
    List<String>? targetUserIds,
    bool? isPinned,
    bool? isDraft,
    bool? isArchived,
    DateTime? archivedAt,
    String? archivedBy,
    String? editedBy,
    DateTime? editedAt,
    DateTime? expiresAt,
  }) {
    return AnnouncementModel(
      announcementId: announcementId,
      companyId: companyId,
      title: title ?? this.title,
      body: body ?? this.body,
      targetType: targetType ?? this.targetType,
      targetCrewIds: targetCrewIds ?? this.targetCrewIds,
      targetUserIds: targetUserIds ?? this.targetUserIds,
      isPinned: isPinned ?? this.isPinned,
      isDraft: isDraft ?? this.isDraft,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      editedBy: editedBy ?? this.editedBy,
      editedAt: editedAt ?? this.editedAt,
      createdByUserId: createdByUserId,
      createdAt: createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
