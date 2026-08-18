import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/company_audit_log_model.dart';

class CompanyAuditLogService {
  final FirebaseFirestore _firestore;

  CompanyAuditLogService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _ref(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.auditLog);
  }

  /// Records one entry. Deliberately doesn't catch its own errors —
  /// callers should wrap this in try/catch so a failed audit write
  /// never blocks the actual action being logged (a role change
  /// succeeding matters more than the log entry about it).
  Future<void> record({
    required String companyId,
    required String actorUserId,
    required String actorName,
    required String action,
    required String targetType,
    required String targetId,
    required String targetName,
    String? oldValue,
    String? newValue,
  }) async {
    await _ref(companyId).add(CompanyAuditEntry.toMapForCreate(
      actorUserId: actorUserId,
      actorName: actorName,
      action: action,
      targetType: targetType,
      targetId: targetId,
      targetName: targetName,
      oldValue: oldValue,
      newValue: newValue,
    ));
  }

  Stream<List<CompanyAuditEntry>> watchLog(String companyId, {int limit = 200}) {
    return _ref(companyId)
        .orderBy(FSFields.createdAt, descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CompanyAuditEntry.fromSnapshot(d)).toList());
  }
}
