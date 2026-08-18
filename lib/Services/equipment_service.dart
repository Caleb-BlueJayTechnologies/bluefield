import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/equipment_model.dart';
import '../Models/membership.dart';
import 'permission_service.dart';

class EquipmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _equipmentRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.equipment);
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

  Future<List<EquipmentModel>> getEquipmentByCompany({
    required String companyId,
    bool includeArchived = false,
  }) async {
    Query<Map<String, dynamic>> query = _equipmentRef(companyId);
    if (!includeArchived) {
      query = query.where(FSFields.isArchived, isEqualTo: false);
    }
    final snapshot = await query.get();
    final equipment = snapshot.docs.map((d) => EquipmentModel.fromSnapshot(d)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return equipment;
  }

  Stream<List<EquipmentModel>> watchEquipmentByCompany({
    required String companyId,
    bool includeArchived = false,
  }) {
    Query<Map<String, dynamic>> query = _equipmentRef(companyId);
    if (!includeArchived) {
      query = query.where(FSFields.isArchived, isEqualTo: false);
    }
    return query.snapshots().map((snap) {
      final equipment = snap.docs.map((d) => EquipmentModel.fromSnapshot(d)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return equipment;
    });
  }

  Future<EquipmentModel?> getEquipment({required String companyId, required String equipmentId}) async {
    final doc = await _equipmentRef(companyId).doc(equipmentId).get();
    if (!doc.exists) return null;
    return EquipmentModel.fromSnapshot(doc);
  }

  Future<String> createEquipment({
    required String companyId,
    required String actingUserId,
    required String name,
    String? category,
    String? serialNumber,
    String? assignedEmployeeId,
    String status = EquipmentStatus.active,
    String? notes,
  }) async {
    await _requirePermission(companyId: companyId, userId: actingUserId, permission: Permission.equipmentCreate);

    final ref = _equipmentRef(companyId).doc();
    await ref.set(EquipmentModel.toMapForCreate(
      companyId: companyId,
      name: name,
      category: category,
      serialNumber: serialNumber,
      assignedEmployeeId: assignedEmployeeId,
      status: status,
      notes: notes,
    ));
    return ref.id;
  }

  Future<void> updateEquipment({
    required String companyId,
    required String actingUserId,
    required String equipmentId,
    String? name,
    String? category,
    String? serialNumber,
    String? status,
    String? notes,
  }) async {
    await _requirePermission(companyId: companyId, userId: actingUserId, permission: Permission.equipmentEdit);

    final updates = <String, dynamic>{FSFields.updatedAt: FieldValue.serverTimestamp()};
    if (name != null) updates['name'] = name;
    if (category != null) updates['category'] = category;
    if (serialNumber != null) updates['serialNumber'] = serialNumber;
    if (status != null) updates['status'] = status;
    if (notes != null) updates['notes'] = notes;

    await _equipmentRef(companyId).doc(equipmentId).update(updates);
  }

  /// Same deliberate decoupling as VehicleService.assignVehicle — an
  /// employee's day-to-day assigned equipment is independent of which
  /// job they're on today (see JobModel.assignedEquipmentIds for the
  /// per-job assignment instead).
  Future<void> assignEquipment({
    required String companyId,
    required String actingUserId,
    required String equipmentId,
    String? employeeId,
  }) async {
    await _requirePermission(companyId: companyId, userId: actingUserId, permission: Permission.equipmentAssign);

    await _equipmentRef(companyId).doc(equipmentId).update({
      'assignedEmployeeId': employeeId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  /// Permanently removes this equipment item — see VehicleService's
  /// deleteVehicle for the same reasoning on why this is a real
  /// delete rather than an archive here.
  Future<void> deleteEquipment({
    required String companyId,
    required String actingUserId,
    required String equipmentId,
  }) async {
    await _requirePermission(companyId: companyId, userId: actingUserId, permission: Permission.equipmentArchive);

    await _equipmentRef(companyId).doc(equipmentId).delete();
  }
}
