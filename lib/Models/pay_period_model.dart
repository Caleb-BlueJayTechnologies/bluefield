import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// A locked or open pay period. Stored at
/// `companies/{companyId}/payPeriods/{payPeriodId}`.
class PayPeriodModel {
  final String payPeriodId;
  final String companyId;
  final String name;

  final DateTime startDate;
  final DateTime endDate;

  final String cycleType; // weekly / biweekly / semimonthly / monthly / custom
  final int periodLengthDays;

  final String status; // FSPayPeriodStatus.*
  final int entryCount;

  final DateTime? lockedAt;
  final String? lockedByUserId;

  final DateTime? unlockedAt;
  final String? unlockedByUserId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PayPeriodModel({
    required this.payPeriodId,
    required this.companyId,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.cycleType,
    required this.periodLengthDays,
    required this.status,
    this.entryCount = 0,
    this.lockedAt,
    this.lockedByUserId,
    this.unlockedAt,
    this.unlockedByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isLocked => status == FSPayPeriodStatus.locked;
  bool get isOpen => status == FSPayPeriodStatus.open;

  Map<String, dynamic> toMap() {
    return {
      FSFields.companyId: companyId,
      'name': name,
      FSFields.startDate: Timestamp.fromDate(startDate),
      FSFields.endDate: Timestamp.fromDate(endDate),
      'cycleType': cycleType,
      'periodLengthDays': periodLengthDays,
      FSFields.status: status,
      'entryCount': entryCount,
      'lockedAt': lockedAt != null ? Timestamp.fromDate(lockedAt!) : null,
      'lockedByUserId': lockedByUserId,
      'unlockedAt': unlockedAt != null ? Timestamp.fromDate(unlockedAt!) : null,
      'unlockedByUserId': unlockedByUserId,
      FSFields.createdAt: Timestamp.fromDate(createdAt),
      FSFields.updatedAt: Timestamp.fromDate(updatedAt),
    };
  }

  factory PayPeriodModel.fromMap(String payPeriodId, Map<String, dynamic> map) {
    return PayPeriodModel(
      payPeriodId: payPeriodId,
      companyId: map[FSFields.companyId]?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      startDate: FSTimestamp.parseOr(map[FSFields.startDate]),
      endDate: FSTimestamp.parseOr(map[FSFields.endDate]),
      cycleType: map['cycleType']?.toString() ?? 'biweekly',
      periodLengthDays: (map['periodLengthDays'] as num?)?.toInt() ?? 14,
      status: map[FSFields.status]?.toString() ?? FSPayPeriodStatus.open,
      entryCount: (map['entryCount'] as num?)?.toInt() ?? 0,
      lockedAt: FSTimestamp.tryParse(map['lockedAt']),
      lockedByUserId: map['lockedByUserId']?.toString(),
      unlockedAt: FSTimestamp.tryParse(map['unlockedAt']),
      unlockedByUserId: map['unlockedByUserId']?.toString(),
      createdAt: FSTimestamp.parseOr(map[FSFields.createdAt]),
      updatedAt: FSTimestamp.parseOr(map[FSFields.updatedAt]),
    );
  }

  factory PayPeriodModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Pay period document ${doc.id} has no data.');
    }
    return PayPeriodModel.fromMap(doc.id, data);
  }
}
