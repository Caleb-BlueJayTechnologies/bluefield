import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../Firebase/firestore_schema.dart';

/// One published version of a legal document (Company Terms, Privacy
/// Policy, User Terms, etc.).
///
/// A version is never edited in place — see LegalDocumentRegistry's
/// doc comment. This class is the "document" side of the acceptance
/// system; LegalAcceptanceEvent (legal_acceptance_event_model.dart) is
/// the "someone accepted this exact version" side.
class LegalDocumentVersion {
  /// One of FSLegalDocumentType.*.
  final String documentType;

  /// Human-readable name shown in the UI ("Company Terms of Service").
  final String title;

  /// Semantic version string, e.g. 'TOS-2026-08-16.v1'. Bump this any
  /// time bodyText changes at all, even a typo fix — the acceptance
  /// record is only meaningful if the version it names never changes
  /// out from under it.
  final String version;

  /// Null while the document is still a draft that hasn't actually
  /// taken effect for anyone yet (see isDraft). Set this the day the
  /// real, finalized document goes live.
  final DateTime? effectiveDate;

  /// The exact text a user sees and accepts. Whatever is in here is
  /// what gets hashed for contentHash below, so changing so much as a
  /// space changes the hash — which is the point: the hash is the
  /// tamper-evidence that a stored acceptance really matches what was
  /// shown.
  final String bodyText;

  /// True for placeholder content that hasn't been through attorney
  /// review and isn't the real, binding document text yet. The viewer
  /// screen shows a visible banner whenever this is true, and nothing
  /// should treat a draft acceptance as equivalent to accepting the
  /// real thing. Flip to false only when replacing bodyText with
  /// final, reviewed text and bumping version.
  final bool isDraft;

  const LegalDocumentVersion({
    required this.documentType,
    required this.title,
    required this.version,
    required this.bodyText,
    this.effectiveDate,
    this.isDraft = true,
  });

  /// SHA-256 of bodyText, hex-encoded. Stored on every acceptance event
  /// so a later dispute can verify the exact text a user actually saw,
  /// not just trust a version label that could in theory get
  /// reattached to different content by a bug or a bad edit.
  String get contentHash => sha256.convert(utf8.encode(bodyText)).toString();
}

/// The current (and, as more versions are added over time, prior)
/// versions of every legal document this app actually shows and
/// records acceptance for.
///
/// IMPORTANT — how to publish a real update:
/// 1. Add a NEW LegalDocumentVersion with a new `version` string. Never
///    edit an existing entry's bodyText/version — Section 11.8 of the
///    source legal package is explicit that a published version is
///    archived, not overwritten, so old acceptance records stay
///    verifiable against the exact text that was live when they were
///    signed.
/// 2. Move the new entry to the front of that document type's list in
///    _allVersions (current() always returns the first match).
/// 3. Set isDraft: false only once the text is final and
///    attorney-reviewed, and fill in effectiveDate.
///
/// Every body below is intentionally a short placeholder, not the
/// attorney-drafted text from the source legal package — that draft is
/// full of unresolved [BRACKETED] business/legal decisions (entity
/// formation, mailing address, payment processor, founding-tier
/// pricing) that are not yet solid, and copying it in here as if it
/// were live would make an incomplete draft look like a real,
/// accepted agreement. This registry, the hashing, and the acceptance
/// flow are the solid, ready-now part; drop in final text the moment
/// it exists and nothing else about the flow needs to change.
class LegalDocumentRegistry {
  LegalDocumentRegistry._();

  static const _placeholderNotice =
      'BlueJay Technologies has not yet published the final version of this '
      'document. This screen exists so the acceptance, versioning, and '
      'evidence-logging mechanism can be built and tested end-to-end ahead '
      'of the real text. Nothing you accept here should be treated as a '
      'final, attorney-reviewed agreement.';

  static final List<LegalDocumentVersion> _allVersions = [
    LegalDocumentVersion(
      documentType: FSLegalDocumentType.companyTerms,
      title: 'Company Terms of Service',
      version: 'COMPANY-TERMS-DRAFT.v1',
      bodyText: _placeholderNotice,
    ),
    LegalDocumentVersion(
      documentType: FSLegalDocumentType.privacyPolicy,
      title: 'Privacy Policy',
      version: 'PRIVACY-DRAFT.v1',
      bodyText: _placeholderNotice,
    ),
    LegalDocumentVersion(
      documentType: FSLegalDocumentType.userTerms,
      title: 'User Terms and Acceptable Use Policy',
      version: 'USER-TERMS-DRAFT.v1',
      bodyText: _placeholderNotice,
    ),
  ];

  /// The current version of [documentType] — the one shown for
  /// acceptance and checked against by
  /// LegalAcceptanceService.hasAcceptedCurrentVersion. Throws if
  /// documentType isn't one of FSLegalDocumentType.* with a version
  /// registered, since silently returning null here would let a
  /// caller skip requiring acceptance entirely without noticing.
  static LegalDocumentVersion current(String documentType) {
    return _allVersions.firstWhere(
      (v) => v.documentType == documentType,
      orElse: () => throw StateError('No LegalDocumentVersion registered for "$documentType".'),
    );
  }

  /// Every version ever registered for [documentType], most recent
  /// first — the "prior accepted versions" list Section 11.9 requires
  /// account settings to expose. Right now every type only has one
  /// entry; this will naturally grow as real versions are added.
  static List<LegalDocumentVersion> history(String documentType) {
    return _allVersions.where((v) => v.documentType == documentType).toList();
  }
}
