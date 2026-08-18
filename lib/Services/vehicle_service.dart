import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/membership.dart';
import '../Models/vehicle_model.dart';
import 'permission_service.dart';

class VehicleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _vehiclesRef(String companyId) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(FSCompanySub.vehicles);
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

  Future<List<VehicleModel>> getVehiclesByCompany({
    required String companyId,
    bool includeArchived = false,
  }) async {
    Query<Map<String, dynamic>> query = _vehiclesRef(companyId);
    if (!includeArchived) {
      query = query.where(FSFields.isArchived, isEqualTo: false);
    }
    final snapshot = await query.get();
    final vehicles = snapshot.docs.map((d) => VehicleModel.fromSnapshot(d)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return vehicles;
  }

  Stream<List<VehicleModel>> watchVehiclesByCompany({
    required String companyId,
    bool includeArchived = false,
  }) {
    Query<Map<String, dynamic>> query = _vehiclesRef(companyId);
    if (!includeArchived) {
      query = query.where(FSFields.isArchived, isEqualTo: false);
    }
    return query.snapshots().map((snap) {
      final vehicles = snap.docs.map((d) => VehicleModel.fromSnapshot(d)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return vehicles;
    });
  }

  Future<VehicleModel?> getVehicle({required String companyId, required String vehicleId}) async {
    final doc = await _vehiclesRef(companyId).doc(vehicleId).get();
    if (!doc.exists) return null;
    return VehicleModel.fromSnapshot(doc);
  }

  Future<String> createVehicle({
    required String companyId,
    required String actingUserId,
    required String name,
    String? make,
    String? model,
    String? year,
    String? licensePlate,
    String? vin,
    String? assignedEmployeeId,
    String status = VehicleStatus.active,
    int? mileage,
    String? notes,
  }) async {
    await _requirePermission(companyId: companyId, userId: actingUserId, permission: Permission.vehiclesCreate);

    final ref = _vehiclesRef(companyId).doc();
    await ref.set(VehicleModel.toMapForCreate(
      companyId: companyId,
      name: name,
      make: make,
      model: model,
      year: year,
      licensePlate: licensePlate,
      vin: vin,
      assignedEmployeeId: assignedEmployeeId,
      status: status,
      mileage: mileage,
      notes: notes,
    ));
    return ref.id;
  }

  Future<void> updateVehicle({
    required String companyId,
    required String actingUserId,
    required String vehicleId,
    String? name,
    String? make,
    String? model,
    String? year,
    String? licensePlate,
    String? vin,
    String? status,
    int? mileage,
    String? notes,
  }) async {
    await _requirePermission(companyId: companyId, userId: actingUserId, permission: Permission.vehiclesEdit);

    final updates = <String, dynamic>{FSFields.updatedAt: FieldValue.serverTimestamp()};
    if (name != null) updates['name'] = name;
    if (make != null) updates['make'] = make;
    if (model != null) updates['model'] = model;
    if (year != null) updates['year'] = year;
    if (licensePlate != null) updates['licensePlate'] = licensePlate;
    if (vin != null) updates['vin'] = vin;
    if (status != null) updates['status'] = status;
    if (mileage != null) updates['mileage'] = mileage;
    if (notes != null) updates['notes'] = notes;

    await _vehiclesRef(companyId).doc(vehicleId).update(updates);
  }

  /// Vehicle assignment is intentionally decoupled from job assignment
  /// (JobModel.assignedVehicleId): a vehicle can be someone's day-to-day
  /// assigned truck independent of which job they're on today.
  Future<void> assignVehicle({
    required String companyId,
    required String actingUserId,
    required String vehicleId,
    String? employeeId,
  }) async {
    await _requirePermission(companyId: companyId, userId: actingUserId, permission: Permission.vehiclesAssign);

    await _vehiclesRef(companyId).doc(vehicleId).update({
      'assignedEmployeeId': employeeId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  /// Permanently removes this vehicle. Unlike employees, crews, and
  /// jobs elsewhere in the app, vehicles are physical assets rather
  /// than records with compliance/audit weight — deleting one is a
  /// deliberate choice, not something that needs an archive trail.
  /// A job that still references a deleted vehicle will simply show
  /// "Vehicle not found" rather than break (see job details screens).
  Future<void> deleteVehicle({
    required String companyId,
    required String actingUserId,
    required String vehicleId,
  }) async {
    await _requirePermission(companyId: companyId, userId: actingUserId, permission: Permission.vehiclesArchive);

    await _vehiclesRef(companyId).doc(vehicleId).delete();
  }
}
