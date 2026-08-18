import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/audit_log_model.dart';

/// Deliberately has NO dependency on PlatformAdminService — that
/// service's own mutations (grantAdminAccess, updateAdminRole, etc.)
/// need to log here too, and a service depending on something that
/// depends back on it is a construction cycle waiting to happen. The
/// raw adminId is what gets stored; resolving it to a display name
/// happens once in the viewer screen (which needs the full admin list
/// loaded anyway, for filtering), not here.
class AuditLogService {
  final FirebaseFirestore _firestore;

  AuditLogService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _logRef =>
      _firestore.collection(FSCollections.platformAuditLog);

  /// Best-effort by design — logging a failure to write the log entry
  /// itself must never block or roll back the real action it's
  /// recording. This method swallows internally so a logging hiccup
  /// is the worst-case outcome, never a failed suspend/grant/etc.
  Future<void> log({
    required String adminId,
    required String action,
    required String targetType,
    required String targetId,
    required String targetName,
    String? oldValue,
    String? newValue,
  }) async {
    try {
      await _logRef.add(AuditLogEntry.toMapForCreate(
        adminId: adminId,
        adminName: adminId,
        action: action,
        targetType: targetType,
        targetId: targetId,
        targetName: targetName,
        oldValue: oldValue,
        newValue: newValue,
      ));
    } catch (_) {
      // Never let a logging failure surface to the caller — see doc
      // comment above.
    }
  }

  Stream<List<AuditLogEntry>> watchRecentEntries({int limit = 200}) {
    return _logRef
        .orderBy(FSFields.createdAt, descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AuditLogEntry.fromSnapshot(d)).toList());
  }
}
