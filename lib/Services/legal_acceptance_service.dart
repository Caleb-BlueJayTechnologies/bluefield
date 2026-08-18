import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/legal_acceptance_event_model.dart';
import '../Models/legal_document_model.dart';

/// Records and queries legal-document acceptance — the checkbox-gated
/// clickwrap flow and its evidence trail (Section 11 of the legal
/// package this was built from). Every write here is append-only: see
/// FSCollections.legalAcceptanceEvents's doc comment and the matching
/// Firestore rule (create-only, no update/delete, ever).
class LegalAcceptanceService {
  final FirebaseFirestore _firestore;

  LegalAcceptanceService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _eventsRef =>
      _firestore.collection(FSCollections.legalAcceptanceEvents);

  /// Best-effort app/platform capture for the evidence record — never
  /// lets a failure here block the actual acceptance from being
  /// recorded, since knowing WHAT was accepted matters far more than
  /// knowing which build the user happened to be on.
  Future<({String? appVersion, String? platform})> _captureEvidence() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final platform = kIsWeb
          ? 'web'
          : (Platform.isAndroid
              ? 'android'
              : Platform.isIOS
                  ? 'ios'
                  : Platform.operatingSystem);
      return (appVersion: '${packageInfo.version}+${packageInfo.buildNumber}', platform: platform);
    } catch (_) {
      return (appVersion: null, platform: null);
    }
  }

  /// Records one acceptance of the CURRENT version of [documentType].
  /// Returns the new acceptance event's ID.
  ///
  /// [capacity] should be FSLegalCapacity.organizationRepresentative
  /// when [userId] is binding a company (pass organizationId/
  /// organizationDisplayedName/role/authorityText too) or
  /// FSLegalCapacity.individual for a personal-only acceptance (e.g. an
  /// invited employee accepting the User Terms).
  ///
  /// [checkboxText] and [buttonText] must be the EXACT strings shown
  /// to the user at the moment they accepted — Section 11.7 requires
  /// preserving presentation, not just which document/version was
  /// involved, so a later dispute can see precisely what the person
  /// read.
  Future<String> recordAcceptance({
    required String documentType,
    required String userId,
    required String verifiedIdentifier,
    required String capacity,
    required String checkboxText,
    required String buttonText,
    String? organizationId,
    String? organizationDisplayedName,
    String? role,
    String? authorityText,
    String? supersedesAcceptanceId,
  }) async {
    final document = LegalDocumentRegistry.current(documentType);
    final evidence = await _captureEvidence();

    final event = LegalAcceptanceEvent(
      acceptanceId: '', // ignored by toMapForCreate; Firestore assigns the real ID
      acceptedAt: DateTime.now(), // ignored by toMapForCreate; server timestamp is authoritative
      userId: userId,
      verifiedIdentifier: verifiedIdentifier,
      organizationId: organizationId,
      organizationDisplayedName: organizationDisplayedName,
      role: role,
      capacity: capacity,
      authorityText: authorityText,
      documentType: document.documentType,
      documentVersion: document.version,
      documentEffectiveDate: document.effectiveDate,
      documentTitle: document.title,
      contentHash: document.contentHash,
      checkboxText: checkboxText,
      buttonText: buttonText,
      appVersion: evidence.appVersion,
      platform: evidence.platform,
      supersedesAcceptanceId: supersedesAcceptanceId,
    );

    final ref = await _eventsRef.add(event.toMapForCreate());
    return ref.id;
  }

  /// Whether [userId] has an acceptance event on file whose
  /// documentVersion matches LegalDocumentRegistry's CURRENT version
  /// of [documentType] — not just "accepted this document type at some
  /// point." A stale acceptance of an old version doesn't count, which
  /// is what makes reacceptance-on-material-change (Section 11.8)
  /// enforceable: bump the registry version and every existing
  /// acceptance for that type stops satisfying this check until the
  /// user accepts again.
  Future<bool> hasAcceptedCurrentVersion({
    required String userId,
    required String documentType,
  }) async {
    final currentVersion = LegalDocumentRegistry.current(documentType).version;
    final snapshot = await _eventsRef
        .where(FSLegalFields.userId, isEqualTo: userId)
        .where(FSLegalFields.documentType, isEqualTo: documentType)
        .where(FSLegalFields.documentVersion, isEqualTo: currentVersion)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// Every acceptance [userId] has on record, most recent first — the
  /// "prior accepted versions" list Section 11.9 requires account
  /// settings to expose.
  Stream<List<LegalAcceptanceEvent>> watchAcceptanceHistory(String userId) {
    return _eventsRef
        .where(FSLegalFields.userId, isEqualTo: userId)
        .orderBy(FSFields.createdAt, descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => LegalAcceptanceEvent.fromSnapshot(d)).toList());
  }
}
