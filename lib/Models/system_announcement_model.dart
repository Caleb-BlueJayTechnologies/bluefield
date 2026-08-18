import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// How urgently a system announcement should be presented — controls
/// the banner's color/prominence in the main app.
class SystemAnnouncementSeverity {
  SystemAnnouncementSeverity._();

  static const info = 'info'; // general notices, feature announcements
  static const warning = 'warning'; // upcoming maintenance
  static const critical = 'critical'; // active outage / urgent issue
}

/// A BlueJay-to-everyone broadcast. Stored at
/// `systemAnnouncements/{announcementId}` — root-level, shown to every
/// company regardless of which one they're in. Distinct from a
/// company's own internal announcements (AnnouncementModel).
class SystemAnnouncementModel {
  final String announcementId;

  final String title;
  final String body;
  final String severity; // SystemAnnouncementSeverity.*

  final bool isActive;

  final String createdByAdminId;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const SystemAnnouncementModel({
    required this.announcementId,
    required this.title,
    required this.body,
    this.severity = SystemAnnouncementSeverity.info,
    this.isActive = true,
    required this.createdByAdminId,
    required this.createdAt,
    this.expiresAt,
  });

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isVisible => isActive && !isExpired;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'severity': severity,
      'isActive': isActive,
      'createdByAdminId': createdByAdminId,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    };
  }

  static Map<String, dynamic> toMapForCreate({
    required String title,
    required String body,
    String severity = SystemAnnouncementSeverity.info,
    required String createdByAdminId,
    DateTime? expiresAt,
  }) {
    return {
      'title': title,
      'body': body,
      'severity': severity,
      'isActive': true,
      'createdByAdminId': createdByAdminId,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
    };
  }

  factory SystemAnnouncementModel.fromMap(String announcementId, Map<String, dynamic> map) {
    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return null;
    }

    return SystemAnnouncementModel(
      announcementId: announcementId,
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      severity: map['severity']?.toString() ?? SystemAnnouncementSeverity.info,
      isActive: map['isActive'] != false,
      createdByAdminId: map['createdByAdminId']?.toString() ?? '',
      createdAt: readDate(map[FSFields.createdAt]) ?? DateTime.now(),
      expiresAt: readDate(map['expiresAt']),
    );
  }

  factory SystemAnnouncementModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('System announcement document ${doc.id} has no data.');
    }
    return SystemAnnouncementModel.fromMap(doc.id, data);
  }
}
