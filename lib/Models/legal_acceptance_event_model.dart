import 'package:cloud_firestore/cloud_firestore.dart';

import '../Firebase/firestore_schema.dart';

/// One immutable record of a single person accepting a single version
/// of a single legal document. Stored at
/// `legalAcceptanceEvents/{acceptanceId}` — see
/// FSCollections.legalAcceptanceEvents's doc comment for why this
/// lives at the root instead of under a company.
///
/// This is deliberately a much smaller field set than Section 11.7's
/// full suggested shape (order snapshot, IP address, device user
/// agent, superseded/reacceptance linkage, delivery confirmation).
/// Those were left out because each depends on something not solid
/// yet — order snapshots need real billing, IP capture needs an
/// explicit justification/disclosure decision Section 11.7 itself
/// flags as conditional, and reacceptance linkage only matters once a
/// second real document version exists to supersede the first. What's
/// here is the part that's solid today: proof of exactly who accepted
/// exactly what text, when, and how it was presented.
class LegalAcceptanceEvent {
  final String acceptanceId;
  final DateTime acceptedAt;

  final String userId;

  /// Email or phone used to identify the accepting user at the time —
  /// captured alongside userId because a UID alone isn't human-
  /// readable evidence years later if an account is ever renamed.
  final String verifiedIdentifier;

  /// Null for an individual acceptance (e.g. an invited employee
  /// accepting the User Terms only for themselves).
  final String? organizationId;
  final String? organizationDisplayedName;

  /// The user's role at acceptance time (owner/manager/employee), or
  /// null if not applicable (no company yet).
  final String? role;

  /// One of FSLegalCapacity.* — whether this accepted on behalf of an
  /// organization or only individually.
  final String capacity;

  /// The exact "I represent that I am authorized to..." text shown
  /// alongside the checkbox, if any (organization acceptances only).
  final String? authorityText;

  final String documentType;
  final String documentVersion;
  final DateTime? documentEffectiveDate;
  final String documentTitle;
  final String contentHash;

  final String checkboxText;
  final String buttonText;
  final String locale;

  final String? appVersion;
  final String? platform;

  /// Links this acceptance to the one it replaces, if this is a
  /// reacceptance of a newer document version. Null for a first-time
  /// acceptance.
  final String? supersedesAcceptanceId;

  const LegalAcceptanceEvent({
    required this.acceptanceId,
    required this.acceptedAt,
    required this.userId,
    required this.verifiedIdentifier,
    this.organizationId,
    this.organizationDisplayedName,
    this.role,
    required this.capacity,
    this.authorityText,
    required this.documentType,
    required this.documentVersion,
    this.documentEffectiveDate,
    required this.documentTitle,
    required this.contentHash,
    required this.checkboxText,
    required this.buttonText,
    this.locale = 'en-US',
    this.appVersion,
    this.platform,
    this.supersedesAcceptanceId,
  });

  /// No acceptedAt/createdAt here — the server timestamp is
  /// authoritative and set by toMapForCreate below, not chosen client-
  /// side, so a device with a wrong clock can't misdate its own
  /// acceptance evidence.
  Map<String, dynamic> toMapForCreate() {
    return {
      FSLegalFields.userId: userId,
      FSLegalFields.verifiedIdentifier: verifiedIdentifier,
      FSLegalFields.organizationId: organizationId,
      FSLegalFields.organizationDisplayedName: organizationDisplayedName,
      FSLegalFields.role: role,
      FSLegalFields.capacity: capacity,
      FSLegalFields.authorityText: authorityText,
      FSLegalFields.documentType: documentType,
      FSLegalFields.documentVersion: documentVersion,
      FSLegalFields.documentEffectiveDate:
          documentEffectiveDate != null ? Timestamp.fromDate(documentEffectiveDate!) : null,
      FSLegalFields.documentTitle: documentTitle,
      FSLegalFields.contentHash: contentHash,
      FSLegalFields.checkboxText: checkboxText,
      FSLegalFields.buttonText: buttonText,
      FSLegalFields.locale: locale,
      FSLegalFields.appVersion: appVersion,
      FSLegalFields.platform: platform,
      FSLegalFields.supersedesAcceptanceId: supersedesAcceptanceId,
      FSFields.createdAt: FieldValue.serverTimestamp(),
    };
  }

  factory LegalAcceptanceEvent.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Legal acceptance event ${doc.id} has no data.');
    }

    DateTime? readDate(dynamic value) => value is Timestamp ? value.toDate() : null;

    return LegalAcceptanceEvent(
      acceptanceId: doc.id,
      acceptedAt: readDate(data[FSFields.createdAt]) ?? DateTime.fromMillisecondsSinceEpoch(0),
      userId: data[FSLegalFields.userId]?.toString() ?? '',
      verifiedIdentifier: data[FSLegalFields.verifiedIdentifier]?.toString() ?? '',
      organizationId: data[FSLegalFields.organizationId]?.toString(),
      organizationDisplayedName: data[FSLegalFields.organizationDisplayedName]?.toString(),
      role: data[FSLegalFields.role]?.toString(),
      capacity: data[FSLegalFields.capacity]?.toString() ?? FSLegalCapacity.individual,
      authorityText: data[FSLegalFields.authorityText]?.toString(),
      documentType: data[FSLegalFields.documentType]?.toString() ?? '',
      documentVersion: data[FSLegalFields.documentVersion]?.toString() ?? '',
      documentEffectiveDate: readDate(data[FSLegalFields.documentEffectiveDate]),
      documentTitle: data[FSLegalFields.documentTitle]?.toString() ?? '',
      contentHash: data[FSLegalFields.contentHash]?.toString() ?? '',
      checkboxText: data[FSLegalFields.checkboxText]?.toString() ?? '',
      buttonText: data[FSLegalFields.buttonText]?.toString() ?? '',
      locale: data[FSLegalFields.locale]?.toString() ?? 'en-US',
      appVersion: data[FSLegalFields.appVersion]?.toString(),
      platform: data[FSLegalFields.platform]?.toString(),
      supersedesAcceptanceId: data[FSLegalFields.supersedesAcceptanceId]?.toString(),
    );
  }
}
