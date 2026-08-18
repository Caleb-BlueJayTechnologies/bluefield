import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

class EquipmentStatus {
  const EquipmentStatus._();
  static const active = 'active';
  static const maintenance = 'maintenance';
  static const inactive = 'inactive';
}

class EquipmentModel {
  final String equipmentId;
  final String companyId;
  final String name;
  final String? category;
  final String? serialNumber;
  final String? assignedEmployeeId;
  final String status;
  final String? notes;
  final bool isArchived;
  final String? archivedByUserId;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EquipmentModel({
    required this.equipmentId,
    required this.companyId,
    required this.name,
    this.category,
    this.serialNumber,
    this.assignedEmployeeId,
    this.status = EquipmentStatus.active,
    this.notes,
    this.isArchived = false,
    this.archivedByUserId,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAssigned => assignedEmployeeId != null;

  static Map<String, dynamic> toMapForCreate({
    required String companyId,
    required String name,
    String? category,
    String? serialNumber,
    String? assignedEmployeeId,
    String status = EquipmentStatus.active,
    String? notes,
  }) {
    return {
      FSFields.companyId: companyId,
      'name': name,
      'category': category,
      'serialNumber': serialNumber,
      'assignedEmployeeId': assignedEmployeeId,
      'status': status,
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
      'category': category,
      'serialNumber': serialNumber,
      'assignedEmployeeId': assignedEmployeeId,
      'status': status,
      'notes': notes,
      FSFields.isArchived: isArchived,
      'archivedByUserId': archivedByUserId,
      FSFields.archivedAt: archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  factory EquipmentModel.fromMap(String equipmentId, Map<String, dynamic> map) {
    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    return EquipmentModel(
      equipmentId: equipmentId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unnamed Equipment',
      category: map['category']?.toString(),
      serialNumber: map['serialNumber']?.toString(),
      assignedEmployeeId: map['assignedEmployeeId']?.toString(),
      status: map['status']?.toString() ?? EquipmentStatus.active,
      notes: map['notes']?.toString(),
      isArchived: map[FSFields.isArchived] == true,
      archivedByUserId: map['archivedByUserId']?.toString(),
      archivedAt: readDate(map[FSFields.archivedAt]),
      createdAt: readDate(map[FSFields.createdAt]) ?? DateTime.now(),
      updatedAt: readDate(map[FSFields.updatedAt]) ?? DateTime.now(),
    );
  }

  factory EquipmentModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return EquipmentModel.fromMap(doc.id, doc.data() ?? {});
  }
}
