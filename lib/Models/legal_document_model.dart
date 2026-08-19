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
/// 3. Set isDraft: false once the text is genuinely ready to bind real
///    users — either attorney-reviewed, or (as with the current V1
///    documents) a deliberate, informed self-drafted decision by the
///    business owner. Fill in effectiveDate either way.
///
/// The current bodies below (see _companyTermsV1, _privacyPolicyV1,
/// _userTermsV1) are real, self-drafted documents, not placeholders —
/// see the NOTE ON THESE DOCUMENTS comment further down for why they're
/// isDraft: false without attorney review.
class LegalDocumentRegistry {
  LegalDocumentRegistry._();

  static final List<LegalDocumentVersion> _allVersions = [
    LegalDocumentVersion(
      documentType: FSLegalDocumentType.companyTerms,
      title: 'Company Terms of Service',
      version: 'COMPANY-TERMS-2026-08-19.v1',
      bodyText: _companyTermsV1,
      effectiveDate: DateTime(2026, 8, 19),
      isDraft: false,
    ),
    LegalDocumentVersion(
      documentType: FSLegalDocumentType.privacyPolicy,
      title: 'Privacy Policy',
      version: 'PRIVACY-2026-08-19.v1',
      bodyText: _privacyPolicyV1,
      effectiveDate: DateTime(2026, 8, 19),
      isDraft: false,
    ),
    LegalDocumentVersion(
      documentType: FSLegalDocumentType.userTerms,
      title: 'User Terms and Acceptable Use Policy',
      version: 'USER-TERMS-2026-08-19.v1',
      bodyText: _userTermsV1,
      effectiveDate: DateTime(2026, 8, 19),
      isDraft: false,
    ),
  ];

  // ==========================================================================
  // NOTE ON THESE DOCUMENTS
  // ==========================================================================
  // Self-drafted by the business owner (with research support, not a
  // licensed attorney) rather than attorney-reviewed — a deliberate,
  // informed choice given the cost of legal review, and a legal one:
  // no state requires a business to hire a lawyer to write its own
  // Terms of Service or Privacy Policy. Wisconsin (BlueJay Technologies'
  // home state) has no comprehensive consumer privacy statute as of
  // this writing, which is part of why isDraft is set to false here
  // rather than left permanently true — that flag was originally scoped
  // to mean "attorney-reviewed," which doesn't fit a knowingly
  // self-drafted document. Treat that as a considered decision, not
  // a shortcut: these documents are real and meant to bind real users,
  // just without a lawyer's sign-off. Revisit with real counsel once
  // the business can afford it, especially before expanding to
  // states with stricter data-privacy statutes (California, Illinois,
  // Colorado, etc.) in a way that starts actually triggering their
  // thresholds.
  // ==========================================================================

  static const _companyTermsV1 = '''
COMPANY TERMS OF SERVICE

Effective Date: August 19, 2026
Version: COMPANY-TERMS-2026-08-19.v1

These Company Terms of Service ("Agreement") are between BlueJay Technologies LLC, a Wisconsin limited liability company ("BlueJay," "we," "us," or "our"), and the moving/field-service company that registers for and uses the BlueField application ("Company," "you," or "your"). This Agreement governs the Company's access to and use of BlueField (the "Service"). By registering a Company account, or by having any authorized representative of the Company accept this Agreement, the Company agrees to be bound by it.

If you do not have authority to bind the Company you represent, do not accept this Agreement.

1. THE SERVICE

BlueField is a workforce-management application that helps field-service companies (such as moving companies) manage employees, schedules, jobs, time tracking, payroll periods, messaging, and related administrative functions. BlueJay may add, change, or remove features of the Service over time.

2. ACCOUNT REGISTRATION AND RESPONSIBILITY

2.1. The Company must provide accurate registration information and keep it current.
2.2. The individual who registers the Company account (the "Owner") is responsible for the Company's use of the Service, including actions taken by Managers and Employees the Owner or a Manager invites into the Company's account.
2.3. The Company is solely responsible for the accuracy of the data it enters into the Service (employee records, pay rates, job details, schedules, and similar business data) and for the lawfulness of decisions it makes using that data.
2.4. The Company is responsible for maintaining the confidentiality of its account credentials and for all activity that occurs under its account.

3. THE COMPANY'S RESPONSIBILITIES AS AN EMPLOYER

3.1. BlueJay provides tools; the Company remains the employer (or otherwise legally responsible party) for its own workforce. The Company is solely responsible for complying with all applicable federal, state, and local employment laws, including wage-and-hour law, overtime rules, meal/rest break requirements, recordkeeping requirements, and any state-specific employee notice or consent requirements — including, where applicable, providing its own employees with any notice or obtaining any consent required before using location tracking or biometric authentication features of the Service.
3.2. The Service's location-based clock-in verification and optional biometric quick sign-in are provided as tools; whether and how the Company enables or requires their use, and whether the Company's own workplace policies satisfy applicable law, is the Company's responsibility.
3.3. The Company is responsible for promptly removing access for any Employee or Manager who is no longer authorized to use the Service (for example, after termination of employment).

4. FEES AND BILLING

4.1. Any subscription fees, billing cycle, and payment terms applicable to the Company's use of the Service will be presented to the Company at signup or through the Service's billing/settings screens. Continued use of the Service after fees take effect constitutes agreement to pay them.
4.2. BlueJay may change its pricing on a going-forward basis with reasonable advance notice to the Company.
4.3. Fees, once paid, are non-refundable except as required by law or as BlueJay otherwise expressly agrees in writing.

5. DATA OWNERSHIP AND USE

5.1. As between BlueJay and the Company, the Company retains ownership of the business data it submits to the Service (employee records, job data, schedules, messages, and similar content) ("Company Data").
5.2. BlueJay may access and process Company Data solely to provide, maintain, secure, and improve the Service, to provide customer support, and as otherwise described in the Privacy Policy.
5.3. BlueJay will not sell Company Data or use it to serve third-party advertising.
5.4. Upon termination of the Company's account, BlueJay will make Company Data available for export for a reasonable period (unless legally prohibited), after which it may be deleted or archived in accordance with BlueJay's data retention practices.

6. ACCEPTABLE USE

The Company will not, and will not permit its Managers or Employees to: (a) use the Service for any unlawful purpose; (b) attempt to gain unauthorized access to any other company's data or to BlueJay's systems; (c) reverse-engineer, decompile, or attempt to extract the source code of the Service except as permitted by law; (d) use the Service to store or transmit malicious code; or (e) interfere with or disrupt the integrity or performance of the Service.

7. SUSPENSION AND TERMINATION

7.1. Either party may terminate this Agreement if the other materially breaches it and fails to cure the breach within a reasonable period after notice.
7.2. BlueJay may suspend or terminate access immediately if the Company's use of the Service poses a security risk, potential legal liability, or violates Section 6 above.
7.3. The Company may stop using the Service and close its account at any time through the Service's settings or by contacting BlueJay.

8. DISCLAIMER OF WARRANTIES

THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING WITHOUT LIMITATION WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT. BLUEJAY DOES NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE. THE COMPANY IS SOLELY RESPONSIBLE FOR VERIFYING THE ACCURACY OF PAYROLL, TIME, AND SCHEDULING OUTPUTS BEFORE RELYING ON THEM FOR PAY OR LEGAL COMPLIANCE PURPOSES.

9. LIMITATION OF LIABILITY

TO THE MAXIMUM EXTENT PERMITTED BY LAW, BLUEJAY'S TOTAL LIABILITY ARISING OUT OF OR RELATED TO THIS AGREEMENT OR THE SERVICE WILL NOT EXCEED THE AMOUNT THE COMPANY PAID BLUEJAY FOR THE SERVICE IN THE THREE (3) MONTHS PRECEDING THE EVENT GIVING RISE TO THE CLAIM. IN NO EVENT WILL BLUEJAY BE LIABLE FOR INDIRECT, INCIDENTAL, CONSEQUENTIAL, SPECIAL, OR PUNITIVE DAMAGES, OR FOR LOST PROFITS, LOST WAGES CLAIMS BROUGHT AGAINST THE COMPANY BY ITS OWN EMPLOYEES, OR LOST DATA, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. THIS SECTION DOES NOT LIMIT LIABILITY WHERE PROHIBITED BY LAW.

10. INDEMNIFICATION

The Company agrees to indemnify and hold BlueJay harmless from third-party claims (including from the Company's own employees) arising out of: (a) the Company's violation of applicable employment law; (b) the Company's Data or its use of the Service in violation of this Agreement; or (c) the Company's failure to provide any notice or obtain any consent required by law before using the Service's location or biometric features with its workforce.

11. GOVERNING LAW AND VENUE

This Agreement is governed by the laws of the State of Wisconsin, without regard to its conflict-of-laws principles. Any dispute arising out of this Agreement will be brought exclusively in the state or federal courts located in Wisconsin, and each party consents to personal jurisdiction there.

12. CHANGES TO THIS AGREEMENT

BlueJay may update this Agreement from time to time. A new version will be published with a new effective date, and continued use of the Service after the new version takes effect constitutes acceptance. Where the Service's clickwrap flow requires re-acceptance, the Company must re-accept before continuing to use the Service.

13. CONTACT

Questions about this Agreement can be sent to caleb.bluejaytech@gmail.com.
''';

  static const _privacyPolicyV1 = '''
PRIVACY POLICY

Effective Date: August 19, 2026
Version: PRIVACY-2026-08-19.v1

This Privacy Policy explains how BlueJay Technologies LLC ("BlueJay," "we," "us," or "our") collects, uses, and shares information through the BlueField application ("Service"). It applies to Company owners, managers, and employees who use the Service ("you").

BlueField is a business tool that a moving/field-service company ("Company") licenses to manage its own workforce. In most cases, the Company — not BlueJay — is the party that decides what employee information is collected and why. If you are an employee using BlueField because your employer requires it, your employer is responsible for the underlying employment decisions; BlueJay is responsible for how the Service itself handles the data.

1. INFORMATION WE COLLECT

Account information: name, email address, and role (owner, manager, or employee) within your Company.

Employment-related information entered by your Company: job title, crew assignment, schedule, time-clock entries, pay-period and payroll data, time-off requests, and similar workforce records.

Location information: BlueField requests location access solely to verify that a clock-in or clock-out is happening at or near the correct job site. Location is checked only at the moment of a clock-in/clock-out action — the Service does not continuously track your location in the background, and does not track your location outside of that specific action.

Photos: only if you choose to attach a screenshot to a support ticket. This is optional and initiated by you.

Messages: content you send through the Service's internal messaging feature, visible to intended recipients within your Company as described in the app.

Device and diagnostic information: app version, device model, and operating system version, collected automatically to help us diagnose problems (for example, when you submit a support ticket).

Biometric authentication — what we do NOT collect: if you enable "Quick Sign-In," BlueField uses your device's own Face ID/fingerprint system (through Apple's or Google's operating-system APIs) to unlock a securely stored sign-in credential on your device. BlueJay never receives, transmits, stores, or has any access to your fingerprint, face scan, or any other biometric identifier — that data never leaves your device and is managed entirely by your device's operating system, not by BlueField or BlueJay's servers.

2. HOW WE USE INFORMATION

We use the information above to: operate and provide the Service's features (scheduling, time tracking, messaging, payroll-period tracking, job management); verify clock-ins occur at the correct location; provide customer/technical support; maintain the security and integrity of the Service; and comply with legal obligations.

We do not sell your personal information, and we do not use it to serve third-party advertising.

3. HOW WE SHARE INFORMATION

Within your Company: information is visible to other users in your Company according to their role — for example, managers and owners can see employee schedules and time records as needed to run the business; employees generally see only their own records, consistent with what's described in the app.

Service providers: we use Google Firebase (Firestore, Authentication, Cloud Storage) to host and operate the Service's backend. These providers process data on our behalf under their own data-processing and security commitments and do not use your data for their own purposes.

Legal requirements: we may disclose information if required by law, subpoena, or other legal process, or to protect the rights, property, or safety of BlueJay, our users, or others.

Business transfers: if BlueJay is involved in a merger, acquisition, or sale of assets, information may be transferred as part of that transaction, subject to this Policy or a successor policy of at least equal protection.

4. DATA RETENTION

We retain information for as long as your Company's account is active, and for a reasonable period afterward to comply with legal obligations (including employment and tax recordkeeping norms), resolve disputes, and enforce our agreements. Support tickets remain visible to your Company for one week after being marked resolved/closed/rejected, and are retained by BlueJay independently of that visibility window for support-history purposes.

5. YOUR CHOICES AND RIGHTS

You may ask us, by contacting caleb.bluejaytech@gmail.com, to provide the personal information we hold about you or to delete it, subject to our and your Company's legitimate business and legal-recordkeeping needs (for example, payroll records your Company may be legally required to retain). Because BlueField is provided to you through your employer's Company account, some requests — such as correcting your job title or pay rate — are more appropriately directed to your Company, since BlueJay does not independently control that underlying employment data.

You can decline to enable Quick Sign-In or location permissions; declining may limit certain convenience features (like faster sign-in or automatic clock-in location checks) but will not prevent you from using the Service's core functions.

6. CHILDREN'S PRIVACY

BlueField is a workplace tool intended for use by working adults and is not directed to, or knowingly used to collect information from, anyone under 18.

7. DATA SECURITY

We use industry-standard measures to protect information, including encryption in transit, Firebase's access-control rules to keep each Company's data isolated from every other Company's, and secure, OS-level credential storage for biometric quick sign-in. No method of transmission or storage is completely secure, and we cannot guarantee absolute security.

8. CHANGES TO THIS POLICY

We may update this Policy from time to time. A new version will be published with a new effective date, and where the Service's clickwrap flow requires re-acceptance, you will be asked to review and accept the updated Policy before continuing to use the Service.

9. CONTACT US

Questions about this Policy, or requests regarding your information, can be sent to caleb.bluejaytech@gmail.com.
''';

  static const _userTermsV1 = '''
USER TERMS AND ACCEPTABLE USE POLICY

Effective Date: August 19, 2026
Version: USER-TERMS-2026-08-19.v1

These User Terms apply to you if you use the BlueField application ("Service") as an owner, manager, or employee of a Company that has registered for the Service. They supplement (and, for individual users, work alongside) the Company Terms of Service that governs your employer's or your own Company's relationship with BlueJay Technologies LLC ("BlueJay," "we," "us," or "our").

By creating or using an account, you agree to these Terms and to our Privacy Policy.

1. YOUR RELATIONSHIP TO YOUR COMPANY

If you are using BlueField as an employee or manager, you are doing so under a Company account controlled by your employer or its designated owner/managers. Your employer — not BlueJay — controls decisions like your pay rate, schedule, job assignments, and employment status. Questions or disputes about those matters should go to your employer first; BlueJay operates the software but is not your employer and does not control those decisions.

2. YOUR ACCOUNT

You are responsible for keeping your login credentials confidential and for all activity under your account. Notify your Company's owner/manager or BlueJay promptly if you believe your account has been compromised.

3. LOCATION AND BIOMETRIC FEATURES

If your Company enables location-based clock-in verification, the Service will check your device's location only at the moment you clock in or out, to confirm you're at or near the expected job site. If you choose to enable "Quick Sign-In," your device's own Face ID/fingerprint system is used to unlock a securely stored credential — BlueJay never receives your actual biometric data. See our Privacy Policy for more detail.

4. ACCEPTABLE USE

You agree not to: use the Service to harass, threaten, or abuse coworkers; misrepresent your location, hours worked, or job status; attempt to access another user's account or data you're not authorized to see; upload unlawful, defamatory, or infringing content (including in support-ticket screenshots or messages); or otherwise misuse the Service in a way that violates your Company's policies or applicable law.

5. MESSAGING AND CONTENT

Messages you send through the Service are visible to their intended recipients within your Company, as shown in the app. Don't send anything through the Service you wouldn't want retained as part of your employer's business records — messages, like other Company Data, may be retained and are accessible to your Company's owners/managers as described in the app.

6. TERMINATION OF ACCESS

Your access to the Service can be removed by your Company (for example, upon end of employment) or suspended by BlueJay for violating these Terms. If your Company's own subscription ends, your access ends with it.

7. DISCLAIMER OF WARRANTIES

THE SERVICE IS PROVIDED "AS IS," WITHOUT WARRANTY OF ANY KIND. BLUEJAY DOES NOT GUARANTEE THAT SCHEDULES, TIME ENTRIES, OR OTHER DATA DISPLAYED IN THE SERVICE ARE ERROR-FREE; IF SOMETHING LOOKS WRONG (a pay rate, a schedule, a clock-in record), REPORT IT TO YOUR EMPLOYER PROMPTLY.

8. LIMITATION OF LIABILITY

TO THE MAXIMUM EXTENT PERMITTED BY LAW, BLUEJAY IS NOT LIABLE FOR INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING FROM YOUR USE OF THE SERVICE, INCLUDING DISPUTES BETWEEN YOU AND YOUR EMPLOYER OVER PAY, SCHEDULING, OR EMPLOYMENT DECISIONS — THOSE ARE MATTERS BETWEEN YOU AND YOUR EMPLOYER, NOT BLUEJAY.

9. GOVERNING LAW

These Terms are governed by the laws of the State of Wisconsin, without regard to conflict-of-laws principles.

10. CHANGES TO THESE TERMS

We may update these Terms from time to time. Where the Service's clickwrap flow requires re-acceptance, you will be asked to review and accept the updated Terms before continuing to use the Service.

11. CONTACT US

Questions about these Terms can be sent to caleb.bluejaytech@gmail.com.
''';

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
