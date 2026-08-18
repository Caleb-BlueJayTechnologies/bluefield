import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

class VehicleStatus {
  const VehicleStatus._();
  static const active = 'active';
  static const maintenance = 'maintenance';
  static const inactive = 'inactive';
}

class VehicleModel {
  final String vehicleId;
  final String companyId;
  final String name;
  final String? make;
  final String? model;
  final String? year;
  final String? licensePlate;
  final String? vin;
  final String? assignedEmployeeId;
  final String status;
  final int? mileage;
  final String? notes;
  final bool isArchived;
  final String? archivedByUserId;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VehicleModel({
    required this.vehicleId,
    required this.companyId,
    required this.name,
    this.make,
    this.model,
    this.year,
    this.licensePlate,
    this.vin,
    this.assignedEmployeeId,
    this.status = VehicleStatus.active,
    this.mileage,
    this.notes,
    this.isArchived = false,
    this.archivedByUserId,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAssigned => assignedEmployeeId != null;

  String get displaySpec {
    final parts = [if (year != null) year!, if (make != null) make!, if (model != null) model!];
    return parts.isEmpty ? '' : parts.join(' ');
  }

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
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
  }) {
    return {
      FSFields.companyId: companyId,
      'name': name,
      'make': make,
      'model': model,
      'year': year,
      'licensePlate': licensePlate,
      'vin': vin,
      'assignedEmployeeId': assignedEmployeeId,
      'status': status,
      'mileage': mileage,
      'notes': notes,
      FSFields.isArchived: false,
      'archivedByUserId': null,
      FSFields.archivedAt: null,
      FSFields.createdAt: FieldValue.serverTimestamp(),
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'name': name,
      'make': make,
      'model': model,
      'year': year,
      'licensePlate': licensePlate,
      'vin': vin,
      'assignedEmployeeId': assignedEmployeeId,
      'status': status,
      'mileage': mileage,
      'notes': notes,
      FSFields.isArchived: isArchived,
      'archivedByUserId': archivedByUserId,
      FSFields.archivedAt: archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  factory VehicleModel.fromMap(String vehicleId, Map<String, dynamic> map) {
    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    return VehicleModel(
      vehicleId: vehicleId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unnamed Vehicle',
      make: map['make']?.toString(),
      model: map['model']?.toString(),
      year: map['year']?.toString(),
      licensePlate: map['licensePlate']?.toString(),
      vin: map['vin']?.toString(),
      assignedEmployeeId: map['assignedEmployeeId']?.toString(),
      status: map['status']?.toString() ?? VehicleStatus.active,
      mileage: map['mileage'] is int ? map['mileage'] as int : int.tryParse(map['mileage']?.toString() ?? ''),
      notes: map['notes']?.toString(),
      isArchived: map[FSFields.isArchived] == true,
      archivedByUserId: map['archivedByUserId']?.toString(),
      archivedAt: readDate(map[FSFields.archivedAt]),
      createdAt: readDate(map[FSFields.createdAt]) ?? DateTime.now(),
      updatedAt: readDate(map[FSFields.updatedAt]) ?? DateTime.now(),
    );
  }

  factory VehicleModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return VehicleModel.fromMap(doc.id, doc.data() ?? {});
  }
}
