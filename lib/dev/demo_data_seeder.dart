import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/message_thread_model.dart';
import '../Services/company_settings_service.dart';
import '../Services/pay_period_service.dart';
import '../firebase_options.dart';
import 'demo_constants.dart';

/// One-time demo-data generator for the GenericMoversDemo@gmail.com
/// sales-demo account. Writes directly to Firestore (bypassing the
/// service layer for anything that would otherwise force
/// FieldValue.serverTimestamp(), since a demo needs backdated history)
/// while matching every model's toMap()/toMapForCreate() shape exactly,
/// so everything this writes reads back through the app's normal
/// screens with no special-casing.
///
/// Hard-gated to one account by email (see [run]) so this can never be
/// accidentally pointed at a real customer's company. Not wired into
/// any normal navigation flow — only reachable from
/// lib/dev/demo_data_seed_screen.dart, which is itself only visible
/// when signed in as the demo account.
///
/// Every run wipes out whatever this account generated last time before
/// writing fresh data (see [_wipeDemoData]) — Firestore rules normally
/// block hard-deletes everywhere (soft delete only, via status/isArchived
/// flags), but firestore.rules carries a narrow, hardcoded-email bypass
/// (isDemoAccountOwner()) that lets ONLY this one account's owner hard-
/// delete its own seeded data. That never touches anything a real
/// customer's data could hit. The 7 employees' Firebase Auth accounts
/// themselves are NOT deleted/recreated on a re-run — same emails sign
/// back in each time — only their Firestore documents and everything
/// else this file generates get wiped and rebuilt.
class DemoDataSeeder {
  static const allowedEmail = 'genericmoversdemo@gmail.com';

  /// The 7 fake employees' names — used both to mint/reuse their real
  /// Firebase Auth accounts up front in [run], and inside
  /// [_seedEmployeesAndCrews] to build their full HR profile specs
  /// (job title, crew, role) once crew IDs exist.
  static const _employeeNames = <({String firstName, String lastName})>[
    (firstName: 'Jordan', lastName: 'Bennett'),
    (firstName: 'Marcus', lastName: 'Webb'),
    (firstName: 'Diego', lastName: 'Alvarez'),
    (firstName: 'Trevor', lastName: 'James'),
    (firstName: 'Sam', lastName: 'Whitfield'),
    (firstName: 'Casey', lastName: 'Nguyen'),
    (firstName: 'Riley', lastName: 'Foster'),
  ];

  final FirebaseFirestore _firestore;
  final CompanySettingsService _settingsService;
  final PayPeriodService _payPeriodService;
  final Random _rng = Random();

  DemoDataSeeder({
    FirebaseFirestore? firestore,
    CompanySettingsService? settingsService,
    PayPeriodService? payPeriodService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _settingsService = settingsService ?? CompanySettingsService(),
        _payPeriodService = payPeriodService ?? PayPeriodService();

  CollectionReference<Map<String, dynamic>> _companySub(String companyId, String sub) {
    return _firestore
        .collection(FSCollections.companies)
        .doc(companyId)
        .collection(sub);
  }

  /// Entry point. [signedInEmail] is checked against [allowedEmail]
  /// before anything is written, as a backstop against this ever being
  /// run against a real customer's company by mistake.
  Future<void> run({
    required String companyId,
    required String ownerId,
    required String signedInEmail,
    required void Function(String message) onProgress,
  }) async {
    if (signedInEmail.trim().toLowerCase() != allowedEmail) {
      throw Exception(
        'Demo data seeding is only allowed for the $allowedEmail account.',
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final approxYearStart = today.subtract(const Duration(days: 365));
    // Align to the Monday on/before that date so weekly/pay-period
    // grouping throughout the app lines up on clean week boundaries.
    final dataStart = approxYearStart.subtract(Duration(days: approxYearStart.weekday - 1));
    final scheduleEnd = today.add(const Duration(days: 28));

    // Auth accounts first, before anything else — their UIDs are
    // deterministic (same email every run, sign-in-instead-of-create on
    // a repeat), so this is what makes the wipe step below able to
    // find and remove exactly last run's 7 employee docs by ID rather
    // than guessing.
    onProgress('Preparing employee accounts...');
    final employeeUidByName = await _createEmployeeAuthAccounts(_employeeNames);

    onProgress('Clearing previous demo data...');
    await _wipeDemoData(companyId: companyId, ownerId: ownerId, employeeUidByName: employeeUidByName);

    onProgress('Setting up company profile & settings...');
    await _seedCompanyProfile(companyId);

    onProgress('Creating employees & crews...');
    final roster = await _seedEmployeesAndCrews(
      companyId: companyId,
      ownerId: ownerId,
      employeeUidByName: employeeUidByName,
    );

    onProgress('Adding vehicles & equipment...');
    final fleet = await _seedFleet(companyId: companyId, roster: roster);

    onProgress('Setting the payroll schedule...');
    await _payPeriodService.saveCycleAnchor(
      companyId: companyId,
      actingUserId: ownerId,
      firstPeriodStart: dataStart,
      overtimeThresholdHours: 40,
    );

    onProgress('Generating a year of time-off history...');
    final timeOffDays = await _seedTimeOff(
      companyId: companyId,
      roster: roster,
      dataStart: dataStart,
      today: today,
      ownerId: ownerId,
    );

    onProgress('Generating jobs — completed, scheduled, and a few cancelled...');
    await _seedJobs(
      companyId: companyId,
      roster: roster,
      fleet: fleet,
      ownerId: ownerId,
      dataStart: dataStart,
      today: today,
      scheduleEnd: scheduleEnd,
    );

    onProgress('Generating a year of time-clock history (this is the big one)...');
    await _seedTimeEntries(
      companyId: companyId,
      roster: roster,
      dataStart: dataStart,
      today: today,
      timeOffDays: timeOffDays,
    );

    onProgress('Generating message history (crew chats, DMs, announcements)...');
    await _seedMessages(
      companyId: companyId,
      roster: roster,
      dataStart: dataStart,
      today: today,
    );

    onProgress('Locking historical pay periods...');
    await _lockHistoricalPayPeriods(
      companyId: companyId,
      ownerId: ownerId,
      dataStart: dataStart,
      today: today,
    );

    onProgress('Done. Demo data is live.');
  }

  // ---------------------------------------------------------------
  // Wipe — clears out everything a previous run of this seeder wrote,
  // so re-running always starts from a clean slate instead of piling
  // up duplicate jobs/time entries/messages on top of last time's.
  // Relies on firestore.rules' isDemoAccountOwner() bypass, which is
  // pinned to this one hardcoded account email and can never affect a
  // real customer's data (see the class doc comment above).
  // ---------------------------------------------------------------

  Future<void> _wipeDemoData({
    required String companyId,
    required String ownerId,
    required Map<String, String> employeeUidByName,
  }) async {
    final writer = _BatchWriter(_firestore);

    // Collections that only ever contain data this seeder generated —
    // safe to wipe entirely.
    const wholeCollections = [
      FSCompanySub.jobs,
      FSCompanySub.schedules,
      FSCompanySub.timeEntries,
      FSCompanySub.timeOffRequests,
      FSCompanySub.payPeriods,
      FSCompanySub.crews,
      FSCompanySub.vehicles,
      FSCompanySub.equipment,
    ];
    for (final sub in wholeCollections) {
      final snapshot = await _companySub(companyId, sub).get();
      for (final doc in snapshot.docs) {
        await writer.delete(doc.reference);
      }
    }

    // messageThreads' messages subcollection has to be cleared out
    // doc-by-doc BEFORE the parent thread doc — deleting a Firestore
    // doc never recursively deletes its subcollections on its own.
    final threadsSnapshot = await _companySub(companyId, FSCompanySub.messageThreads).get();
    for (final threadDoc in threadsSnapshot.docs) {
      final messagesSnapshot = await threadDoc.reference.collection(FSThreadSub.messages).get();
      for (final messageDoc in messagesSnapshot.docs) {
        await writer.delete(messageDoc.reference);
      }
      await writer.delete(threadDoc.reference);
    }

    // Only the 7 seeded employees, by their known (deterministic) UIDs
    // — never touches the Owner's own employees/memberships/users doc,
    // which this seeder only ever merges, never generates from scratch.
    final employeesRef = _companySub(companyId, FSCompanySub.employees);
    final membershipsRef = _companySub(companyId, FSCompanySub.memberships);
    final usersRef = _firestore.collection(FSCollections.users);
    for (final uid in employeeUidByName.values) {
      await writer.delete(employeesRef.doc(uid));
      await writer.delete(membershipsRef.doc(uid));
      await writer.delete(usersRef.doc(uid));
    }

    // Full sweep: delete any employee OR membership doc that isn't the
    // Owner's own or one of the 7 current, deterministic-UID employees.
    // This replaces an earlier "no matching employee doc" check that
    // only caught HALF the possible cruft. Older iterations of this
    // seeder (before it switched to email-derived deterministic UIDs)
    // could leave behind a full, matched employee+membership PAIR under
    // a random old UID that's no longer one of the 7 current names —
    // that pair looks completely legitimate to a "does it have a
    // matching employee doc" check, since both docs exist and match
    // each other. It only stands out by not belonging to the current
    // roster, which is why comparing against employeeUidByName (the
    // actual source of truth for "who is a seeded employee right now")
    // catches it, where comparing memberships against employees did
    // not. This was letting re-runs silently accumulate "ghost" active
    // employees over time — e.g. the admin panel's headcount (and any
    // tier-upgrade threshold that reads it) showing 10 active when only
    // 8 people (7 employees + Owner) actually exist.
    final currentEmployeeIds = employeeUidByName.values.toSet();
    final employeesSnapshot = await employeesRef.get();
    for (final doc in employeesSnapshot.docs) {
      if (doc.id == ownerId || currentEmployeeIds.contains(doc.id)) continue;
      await writer.delete(doc.reference);
    }
    final membershipsSnapshot = await membershipsRef.get();
    for (final doc in membershipsSnapshot.docs) {
      if (doc.id == ownerId || currentEmployeeIds.contains(doc.id)) continue;
      await writer.delete(doc.reference);
    }

    await writer.finish();
  }

  // ---------------------------------------------------------------
  // Company profile / settings
  // ---------------------------------------------------------------

  Future<void> _seedCompanyProfile(String companyId) async {
    final settings = await _settingsService.getCompanySettings(companyId);
    final updated = settings.copyWith(
      companyInfo: {
        ...settings.companyInfo,
        'companyName': 'Generic Movers Co.',
        'businessEmail': 'GenericMoversDemo@gmail.com',
        'phone': '(920) 555-0148',
        'address': '1420 Freight Ave, Green Bay, WI 54301',
        'timezone': 'America/Chicago',
        'weekStartDay': 'monday',
        'crewTerminology': 'crew',
        'industryType': 'Moving & Relocation Services',
      },
      timeOff: {
        ...settings.timeOff,
        'bereavement': true,
        'juryDuty': true,
      },
      teamTime: {
        ...settings.teamTime,
        'breaksEnabled': true,
        'roundingRule': '15 minutes',
        'correctionRequests': true,
      },
      payroll: {
        ...settings.payroll,
        'payPeriodType': 'biweekly',
      },
      vehicles: {
        ...settings.vehicles,
        'enabled': true,
      },
    );
    await _settingsService.saveCompanySettings(updated);
  }

  // ---------------------------------------------------------------
  // Employees, memberships, crews
  // ---------------------------------------------------------------

  /// Mints one real Firebase Auth account per fake employee, keyed by
  /// "First Last" so callers can look up the resulting UID. Runs on a
  /// secondary, separately-named FirebaseApp/FirebaseAuth instance —
  /// creating a user signs that instance in as them, and if this ran on
  /// the PRIMARY instance it would silently kick the Owner running the
  /// seeder out of their own session. Re-running the seeder against an
  /// account that already exists (e.g. after a partial failure) signs
  /// into it instead of erroring, so the same UID comes back rather
  /// than aborting the whole run.
  Future<Map<String, String>> _createEmployeeAuthAccounts(
    List<({String firstName, String lastName})> specs,
  ) async {
    final secondaryApp = await _secondaryApp();
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

    final uidByName = <String, String>{};
    for (final spec in specs) {
      final email = demoEmployeeEmail(spec.firstName, spec.lastName);
      UserCredential credential;
      try {
        credential = await secondaryAuth.createUserWithEmailAndPassword(
          email: email,
          password: kDemoEmployeePassword,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          credential = await secondaryAuth.signInWithEmailAndPassword(
            email: email,
            password: kDemoEmployeePassword,
          );
        } else {
          rethrow;
        }
      }
      final uid = credential.user?.uid;
      if (uid == null) {
        throw Exception('Failed to create/sign in demo account for $email.');
      }
      uidByName['${spec.firstName} ${spec.lastName}'] = uid;
    }

    // Leave the secondary instance signed out — nothing else on this
    // app instance should stay authenticated once seeding is done.
    await secondaryAuth.signOut();
    return uidByName;
  }

  /// The secondary FirebaseApp used to mint/sign into fake employees'
  /// Auth accounts without ever touching the Owner's own signed-in
  /// session on the primary (default) FirebaseApp. Reused by both
  /// account creation and by [_asEmployee] for message seeding.
  Future<FirebaseApp> _secondaryApp() async {
    try {
      return Firebase.app('demoEmployeeCreation');
    } catch (_) {
      return Firebase.initializeApp(
        name: 'demoEmployeeCreation',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  /// Runs [action] with a Firestore instance authenticated as the given
  /// employee, via the secondary Auth/Firestore pair — so writes that
  /// must satisfy "sender/creator == request.auth.uid" security rules
  /// (like sending a message, or creating a thread you're part of)
  /// pass as that real employee instead of the Owner. Always signs back
  /// out of the secondary instance when done, even if [action] throws.
  Future<T> _asEmployee<T>(
    String firstName,
    String lastName,
    Future<T> Function(FirebaseFirestore firestore) action,
  ) async {
    final secondaryApp = await _secondaryApp();
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    final secondaryFirestore = FirebaseFirestore.instanceFor(app: secondaryApp);
    await secondaryAuth.signInWithEmailAndPassword(
      email: demoEmployeeEmail(firstName, lastName),
      password: kDemoEmployeePassword,
    );
    try {
      return await action(secondaryFirestore);
    } finally {
      await secondaryAuth.signOut();
    }
  }

  Future<_SeedRoster> _seedEmployeesAndCrews({
    required String companyId,
    required String ownerId,
    required Map<String, String> employeeUidByName,
  }) async {
    final employeesRef = _companySub(companyId, FSCompanySub.employees);
    final membershipsRef = _companySub(companyId, FSCompanySub.memberships);
    final crewsRef = _companySub(companyId, FSCompanySub.crews);
    final usersRef = _firestore.collection(FSCollections.users);

    // Pre-allocate crew IDs up front so crews and employees can
    // reference each other (leaderId <-> crewIds) in a single pass.
    final crewAId = crewsRef.doc().id;
    final crewBId = crewsRef.doc().id;

    final specs = <List<String?>>[
      ['Jordan', 'Bennett', FSRoles.manager, 'Operations Manager', null],
      ['Marcus', 'Webb', FSRoles.employee, 'Crew Lead / Mover', crewAId],
      ['Diego', 'Alvarez', FSRoles.employee, 'Mover', crewAId],
      ['Trevor', 'James', FSRoles.employee, 'Mover / Driver', crewAId],
      ['Sam', 'Whitfield', FSRoles.employee, 'Crew Lead / Mover', crewBId],
      ['Casey', 'Nguyen', FSRoles.employee, 'Mover', crewBId],
      ['Riley', 'Foster', FSRoles.employee, 'Mover / Driver', crewBId],
    ];

    // Real Firebase Auth accounts (not synthetic Firestore IDs) for each
    // employee, so "View As" (view_as_screen.dart) can genuinely sign
    // in as them and get the exact same app everyone else sees — reads,
    // writes, and all — with zero extra plumbing anywhere else in the
    // app. Minted (or reused, on a re-run) up in run(), before the wipe
    // step, so a wipe-and-regenerate targets the SAME 7 accounts every
    // time instead of orphaning old ones.
    final employees = <_SeedEmployee>[];
    for (final spec in specs) {
      final id = employeeUidByName['${spec[0]} ${spec[1]}']!;
      employees.add(_SeedEmployee(
        id: id,
        firstName: spec[0]!,
        lastName: spec[1]!,
        role: spec[2]!,
        jobTitle: spec[3]!,
        crewId: spec[4],
      ));
    }

    final marcusId = employees[1].id;
    final samId = employees[4].id;

    final writer = _BatchWriter(_firestore);
    final now = DateTime.now();
    final orgFoundedAt = now.subtract(const Duration(days: 900));

    var hireCursor = now.subtract(const Duration(days: 820));
    for (final emp in employees) {
      hireCursor = hireCursor.add(Duration(days: 30 + _rng.nextInt(70)));
      final hireDate = hireCursor.isBefore(now)
          ? hireCursor
          : now.subtract(Duration(days: 60 + _rng.nextInt(300)));
      final email = demoEmployeeEmail(emp.firstName, emp.lastName);

      await writer.set(employeesRef.doc(emp.id), {
        FSFields.companyId: companyId,
        'firstName': emp.firstName,
        'lastName': emp.lastName,
        'preferredName': null,
        'jobTitle': emp.jobTitle,
        'crewIds': emp.crewId != null ? [emp.crewId] : <String>[],
        'phone': _fakePhone(),
        'loginEmail': email,
        'requiresPasswordChange': false,
        'hireDate': Timestamp.fromDate(hireDate),
        'employmentType': 'fullTime',
        'employeeNumber': null,
        'notes': null,
        'clockInRequirementOverride': 'useCompanyDefault',
        'managerApprovalOverride': 'useCompanyDefault',
        FSFields.createdAt: Timestamp.fromDate(hireDate),
        FSFields.updatedAt: Timestamp.fromDate(hireDate),
      });

      await writer.set(membershipsRef.doc(emp.id), {
        'userId': emp.id,
        'companyId': companyId,
        'role': emp.role,
        'status': FSMembershipStatus.active,
        'invitedBy': ownerId,
        'invitedAt': Timestamp.fromDate(hireDate),
        'joinedAt': Timestamp.fromDate(hireDate),
        'archivedAt': null,
        'archivedBy': null,
        'archiveReason': null,
        'roleChangedBy': null,
        'roleChangedAt': null,
        FSFields.createdAt: Timestamp.fromDate(hireDate),
        FSFields.updatedAt: Timestamp.fromDate(hireDate),
      });

      // users/{uid} doc to match the real Firebase Auth account just
      // created (or reused) for them — onboardingComplete: true so
      // signing in as them (view_as_screen.dart) lands straight on
      // their dashboard instead of an onboarding flow meant for
      // brand-new signups. Always a genuine create at this point: the
      // wipe step in run() already deleted any prior version of this
      // doc, so there's nothing here for the update-only self-write
      // rule on users/{uid} to conflict with.
      await writer.merge(usersRef.doc(emp.id), {
        'email': email,
        'firstName': emp.firstName,
        'lastName': emp.lastName,
        'preferredName': null,
        'phone': null,
        'activeCompanyId': companyId,
        'emailVerified': true,
        'requiresPasswordChange': false,
        'onboardingComplete': true,
        FSFields.createdAt: Timestamp.fromDate(hireDate),
        FSFields.updatedAt: Timestamp.fromDate(hireDate),
      });
    }

    await writer.set(crewsRef.doc(crewAId), {
      FSFields.companyId: companyId,
      'crewName': 'Crew A',
      'description': 'Residential moves — north side routes',
      'leaderId': marcusId,
      'color': '#2196F3',
      FSFields.isArchived: false,
      'archivedAt': null,
      'archivedBy': null,
      'archiveReason': null,
      'createdBy': ownerId,
      FSFields.createdAt: Timestamp.fromDate(orgFoundedAt),
      FSFields.updatedAt: Timestamp.fromDate(orgFoundedAt),
    });

    await writer.set(crewsRef.doc(crewBId), {
      FSFields.companyId: companyId,
      'crewName': 'Crew B',
      'description': 'Residential & commercial moves — south side routes',
      'leaderId': samId,
      'color': '#43A047',
      FSFields.isArchived: false,
      'archivedAt': null,
      'archivedBy': null,
      'archiveReason': null,
      'createdBy': ownerId,
      FSFields.createdAt: Timestamp.fromDate(orgFoundedAt),
      FSFields.updatedAt: Timestamp.fromDate(orgFoundedAt),
    });

    // Give the owner's own employee profile a matching job title
    // without touching their name — they set that during their own
    // signup. Uses a merge-set rather than update(): this write is
    // batched together with every other employee/crew write below, and
    // WriteBatch.update() throws (aborting the WHOLE batch) if the doc
    // doesn't exist. A merge-set can't fail that way — it creates the
    // doc if it's somehow missing instead of taking the rest of the
    // batch down with it.
    await writer.merge(employeesRef.doc(ownerId), {
      'jobTitle': 'Owner / General Manager',
      FSFields.updatedAt: Timestamp.fromDate(now),
    });

    await writer.finish();

    return _SeedRoster(
      ownerId: ownerId,
      employees: employees,
      crewAId: crewAId,
      crewBId: crewBId,
    );
  }

  // ---------------------------------------------------------------
  // Vehicles & equipment
  // ---------------------------------------------------------------

  Future<_SeedFleet> _seedFleet({
    required String companyId,
    required _SeedRoster roster,
  }) async {
    final vehiclesRef = _companySub(companyId, FSCompanySub.vehicles);
    final equipmentRef = _companySub(companyId, FSCompanySub.equipment);
    final now = DateTime.now();
    final purchasedAt = now.subtract(const Duration(days: 800));

    final marcusId = _crewLeaderId(roster, roster.crewAId);
    final samId = _crewLeaderId(roster, roster.crewBId);

    final writer = _BatchWriter(_firestore);

    final van1Id = vehiclesRef.doc().id;
    final van2Id = vehiclesRef.doc().id;
    final van3Id = vehiclesRef.doc().id;

    final vans = <Map<String, dynamic>>[
      {
        'id': van1Id, 'name': 'Van 1', 'make': 'Ford', 'model': 'Transit 250',
        'year': '2021', 'plate': 'MOV-1021', 'mileage': 46200, 'assigned': marcusId,
        'notes': 'Primary Crew A vehicle, 15ft cargo box.',
      },
      {
        'id': van2Id, 'name': 'Van 2', 'make': 'Mercedes-Benz', 'model': 'Sprinter 2500',
        'year': '2022', 'plate': 'MOV-2022', 'mileage': 28750, 'assigned': samId,
        'notes': 'Primary Crew B vehicle, 17ft cargo box.',
      },
      {
        'id': van3Id, 'name': 'Van 3', 'make': 'Ford', 'model': 'Transit 350',
        'year': '2019', 'plate': 'MOV-3019', 'mileage': 81400, 'assigned': null,
        'notes': 'Spare/backup van for big jobs and overflow.',
      },
    ];

    for (final v in vans) {
      await writer.set(vehiclesRef.doc(v['id'] as String), {
        FSFields.companyId: companyId,
        'name': v['name'],
        'make': v['make'],
        'model': v['model'],
        'year': v['year'],
        'licensePlate': v['plate'],
        'vin': _fakeVin(),
        'assignedEmployeeId': v['assigned'],
        'status': 'active',
        'mileage': v['mileage'],
        'notes': v['notes'],
        FSFields.isArchived: false,
        'archivedByUserId': null,
        FSFields.archivedAt: null,
        FSFields.createdAt: Timestamp.fromDate(purchasedAt),
        FSFields.updatedAt: Timestamp.fromDate(purchasedAt),
      });
    }

    const equipmentSpecs = <List<String>>[
      ['4-Wheel Dolly #1', 'Dolly'],
      ['4-Wheel Dolly #2', 'Dolly'],
      ['4-Wheel Dolly #3', 'Dolly'],
      ['Appliance Hand Truck #1', 'Hand Truck'],
      ['Appliance Hand Truck #2', 'Hand Truck'],
      ['Moving Blanket Set A', 'Blankets'],
      ['Moving Blanket Set B', 'Blankets'],
      ['Moving Blanket Set C', 'Blankets'],
      ['Ratchet Strap Set #1', 'Straps'],
      ['Ratchet Strap Set #2', 'Straps'],
      ['Shrink Wrap Dispenser', 'Supplies'],
      ['Furniture Slider Kit', 'Supplies'],
    ];

    final equipmentIds = <String>[];
    for (final spec in equipmentSpecs) {
      final id = equipmentRef.doc().id;
      equipmentIds.add(id);
      await writer.set(equipmentRef.doc(id), {
        FSFields.companyId: companyId,
        'name': spec[0],
        'category': spec[1],
        'serialNumber': _fakeSerial(),
        'assignedEmployeeId': null,
        'status': 'active',
        'notes': null,
        FSFields.isArchived: false,
        'archivedByUserId': null,
        FSFields.archivedAt: null,
        FSFields.createdAt: Timestamp.fromDate(purchasedAt),
        FSFields.updatedAt: Timestamp.fromDate(purchasedAt),
      });
    }

    await writer.finish();

    return _SeedFleet(
      vanIdByCrew: {roster.crewAId: van1Id, roster.crewBId: van2Id},
      spareVanId: van3Id,
      equipmentIds: equipmentIds,
    );
  }

  // ---------------------------------------------------------------
  // Time off
  // ---------------------------------------------------------------

  static const _leaveTypes = ['pto', 'sick', 'unpaid', 'bereavement', 'juryDuty'];

  Future<Map<String, Set<String>>> _seedTimeOff({
    required String companyId,
    required _SeedRoster roster,
    required DateTime dataStart,
    required DateTime today,
    required String ownerId,
  }) async {
    final timeOffRef = _companySub(companyId, FSCompanySub.timeOffRequests);
    final writer = _BatchWriter(_firestore);
    final offDaysByEmployee = <String, Set<String>>{};

    final totalSpanDays = today.difference(dataStart).inDays;

    for (final emp in roster.employees) {
      offDaysByEmployee[emp.id] = <String>{};

      final requestCount = 3 + _rng.nextInt(3); // 3-5 requests per employee across the year
      for (var i = 0; i < requestCount; i++) {
        final leaveType = i == 0 ? 'pto' : _pick(_leaveTypes);
        final lengthDays = leaveType == 'pto' ? 2 + _rng.nextInt(4) : 1 + _rng.nextInt(2);

        final maxOffset = max(totalSpanDays - 20, 1);
        var start = dataStart.add(Duration(days: 10 + _rng.nextInt(maxOffset)));
        // Nudge onto a Monday so multi-day PTO reads as a normal week off.
        start = start.subtract(Duration(days: start.weekday - 1));
        final end = start.add(Duration(days: lengthDays - 1));
        if (!end.isBefore(today)) continue; // keep all of these in the past

        final totalHours = lengthDays * 8.0;
        final createdAt = start.subtract(Duration(days: 5 + _rng.nextInt(9)));
        final reviewedAt = createdAt.add(Duration(days: 1 + _rng.nextInt(2)));

        final id = timeOffRef.doc().id;
        await writer.set(timeOffRef.doc(id), {
          FSFields.companyId: companyId,
          FSFields.employeeId: emp.id,
          'leaveTypeId': leaveType,
          'isFullDay': true,
          FSFields.startDate: Timestamp.fromDate(start),
          FSFields.endDate: Timestamp.fromDate(end),
          'totalHours': totalHours,
          'reason': _timeOffReason(leaveType),
          'notes': null,
          FSFields.status: FSTimeOffStatus.approved,
          'reviewedByUserId': ownerId,
          FSFields.reviewedAt: Timestamp.fromDate(reviewedAt),
          'reviewNotes': null,
          'cancelledByUserId': null,
          'cancelledAt': null,
          'cancellationReason': null,
          'scheduleConflictAcknowledged': false,
          FSFields.createdAt: Timestamp.fromDate(createdAt),
          FSFields.updatedAt: Timestamp.fromDate(reviewedAt),
        });

        for (var d = 0; d < lengthDays; d++) {
          offDaysByEmployee[emp.id]!.add(_dateKey(start.add(Duration(days: d))));
        }
      }
    }

    // One upcoming pending request so Time Off has something awaiting
    // review too, not just a wall of already-approved history.
    final requester = _pick(roster.employees);
    final pendingStart = today.add(Duration(days: 10 + _rng.nextInt(15)));
    final pendingEnd = pendingStart.add(const Duration(days: 2));
    final pendingId = timeOffRef.doc().id;
    await writer.set(timeOffRef.doc(pendingId), {
      FSFields.companyId: companyId,
      FSFields.employeeId: requester.id,
      'leaveTypeId': 'pto',
      'isFullDay': true,
      FSFields.startDate: Timestamp.fromDate(pendingStart),
      FSFields.endDate: Timestamp.fromDate(pendingEnd),
      'totalHours': 24.0,
      'reason': 'Family trip',
      'notes': null,
      FSFields.status: FSTimeOffStatus.pending,
      'reviewedByUserId': null,
      FSFields.reviewedAt: null,
      'reviewNotes': null,
      'cancelledByUserId': null,
      'cancelledAt': null,
      'cancellationReason': null,
      'scheduleConflictAcknowledged': false,
      FSFields.createdAt: Timestamp.fromDate(today.subtract(const Duration(days: 2))),
      FSFields.updatedAt: Timestamp.fromDate(today.subtract(const Duration(days: 2))),
    });

    await writer.finish();
    return offDaysByEmployee;
  }

  String _timeOffReason(String leaveType) {
    switch (leaveType) {
      case 'pto':
        return 'Vacation';
      case 'sick':
        return 'Feeling under the weather';
      case 'unpaid':
        return 'Personal time';
      case 'bereavement':
        return 'Family bereavement';
      case 'juryDuty':
        return 'Jury duty summons';
      default:
        return '';
    }
  }

  // ---------------------------------------------------------------
  // Jobs (+ matching schedule entries for future/active ones)
  // ---------------------------------------------------------------

  static const _jobTemplates = <Map<String, Object>>[
    {'title': 'Studio Apartment Move', 'hours': 3, 'crewSize': '2 movers', 'price': 420},
    {'title': '1BR Apartment Move', 'hours': 4, 'crewSize': '2 movers', 'price': 560},
    {'title': '2BR Apartment Move', 'hours': 5, 'crewSize': '3 movers', 'price': 780},
    {'title': '3BR House Move', 'hours': 7, 'crewSize': '3 movers', 'price': 1180},
    {'title': '4BR House Move', 'hours': 8, 'crewSize': '3 movers', 'price': 1450},
    {'title': 'Senior Downsizing Move', 'hours': 5, 'crewSize': '3 movers', 'price': 820},
    {'title': 'Office Relocation', 'hours': 6, 'crewSize': '3 movers', 'price': 1600},
    {'title': 'Retail Storefront Move', 'hours': 6, 'crewSize': '3 movers', 'price': 1350},
    {'title': 'College Dorm Move-Out', 'hours': 2, 'crewSize': '2 movers', 'price': 260},
    {'title': 'Piano & Furniture Move', 'hours': 3, 'crewSize': '3 movers', 'price': 540},
    {'title': 'Long-Distance Prep — Load Only', 'hours': 4, 'crewSize': '3 movers', 'price': 690},
    {'title': 'Storage Unit Move', 'hours': 3, 'crewSize': '2 movers', 'price': 380},
  ];

  static const _cancellationReasons = [
    'Customer rescheduled to a later date.',
    'Customer cancelled — found another mover.',
    'Weather delay, could not be rebooked in time.',
    "Customer's closing date fell through.",
  ];

  static const _customerFirstNames = [
    'James', 'Mary', 'Robert', 'Patricia', 'John', 'Jennifer', 'Michael', 'Linda',
    'David', 'Barbara', 'William', 'Elizabeth', 'Richard', 'Susan', 'Joseph', 'Jessica',
    'Thomas', 'Sarah', 'Charles', 'Karen', 'Daniel', 'Nancy', 'Matthew', 'Lisa',
    'Anthony', 'Betty', 'Mark', 'Margaret', 'Paul', 'Sandra',
  ];

  static const _customerLastNames = [
    'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis',
    'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson',
    'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin', 'Lee', 'Perez', 'Thompson',
    'White', 'Harris', 'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson',
  ];

  static const _streetNames = [
    'Maple St', 'Oak Ave', 'Cedar Ln', 'Elm St', 'Pine Rd', 'Birch Dr', 'Willow Way',
    'Chestnut Ct', 'Sycamore St', 'Magnolia Ave', 'Hickory Ln', 'Aspen Dr',
    'Riverside Dr', 'Lakeview Ave', 'Highland Rd', 'Sunset Blvd', 'Meadow Ln',
    'Prairie Ave', 'Franklin St', 'Jefferson Ave', 'Bay Settlement Rd', 'Shawano Ave',
    'Velp Ave', 'Lombardi Ave', 'Fox River Dr',
  ];

  // Northeast Wisconsin (Green Bay / Fox Valley) cities + matching ZIPs, so
  // every generated address stays local to the demo company's home region.
  static const _neWisconsinCities = [
    {'city': 'Green Bay', 'zip': '54301'},
    {'city': 'Green Bay', 'zip': '54302'},
    {'city': 'Green Bay', 'zip': '54303'},
    {'city': 'Ashwaubenon', 'zip': '54304'},
    {'city': 'De Pere', 'zip': '54115'},
    {'city': 'Howard', 'zip': '54313'},
    {'city': 'Suamico', 'zip': '54173'},
    {'city': 'Appleton', 'zip': '54911'},
    {'city': 'Appleton', 'zip': '54914'},
    {'city': 'Neenah', 'zip': '54956'},
    {'city': 'Menasha', 'zip': '54952'},
    {'city': 'Oshkosh', 'zip': '54901'},
    {'city': 'Kaukauna', 'zip': '54130'},
    {'city': 'Fond du Lac', 'zip': '54935'},
  ];

  Future<void> _seedJobs({
    required String companyId,
    required _SeedRoster roster,
    required _SeedFleet fleet,
    required String ownerId,
    required DateTime dataStart,
    required DateTime today,
    required DateTime scheduleEnd,
  }) async {
    final jobsRef = _companySub(companyId, FSCompanySub.jobs);
    final schedulesRef = _companySub(companyId, FSCompanySub.schedules);
    final writer = _BatchWriter(_firestore);

    final crewIds = [roster.crewAId, roster.crewBId];
    var crewTurn = 0;

    var cursor = dataStart;
    while (!cursor.isAfter(scheduleEnd)) {
      final weekday = cursor.weekday; // 1=Mon..7=Sun
      final isPast = cursor.isBefore(today);
      final isToday = cursor.year == today.year && cursor.month == today.month && cursor.day == today.day;

      if (weekday != DateTime.sunday) {
        final worksSaturday = weekday != DateTime.saturday || _rng.nextDouble() < 0.25;
        if (worksSaturday) {
          final jobsToday = weekday == DateTime.saturday
              ? 1
              : (_rng.nextDouble() < 0.35 ? 2 : 1);

          for (var j = 0; j < jobsToday; j++) {
            final crewId = crewIds[crewTurn % crewIds.length];
            crewTurn++;
            final template = _pick(_jobTemplates);
            final vanId = fleet.vanIdByCrew[crewId]!;
            final useSpare = _rng.nextDouble() < 0.12;
            final vehicleIds = useSpare ? [vanId, fleet.spareVanId] : [vanId];
            final equipmentIds = _pickEquipment(fleet.equipmentIds);

            final startHour = 8 + _rng.nextInt(2);
            final startTime = DateTime(
              cursor.year, cursor.month, cursor.day, startHour, _rng.nextInt(4) * 15,
            );
            final durationHours = template['hours'] as int;
            final endTime = startTime.add(
              Duration(hours: durationHours, minutes: _rng.nextInt(4) * 15),
            );

            final custFirst = _pick(_customerFirstNames);
            final custLast = _pick(_customerLastNames);
            final pickupAddr = _fakeAddress();
            final dropoffAddr = _fakeAddress();

            final jobId = jobsRef.doc().id;
            final createdAt = cursor.subtract(Duration(days: 3 + _rng.nextInt(10)));

            var status = FSJobStatus.scheduled;
            DateTime? completedAt;
            String? completedBy;
            String? cancellationReason;
            String? cancelledBy;
            DateTime? cancelledAt;

            if (isPast) {
              final cancelled = _rng.nextDouble() < 0.02;
              if (cancelled) {
                status = FSJobStatus.cancelled;
                cancelledAt = startTime.subtract(const Duration(hours: 20));
                cancelledBy = ownerId;
                cancellationReason = _pick(_cancellationReasons);
              } else {
                status = FSJobStatus.completed;
                completedAt = endTime.add(Duration(minutes: _rng.nextInt(30)));
                completedBy = _crewLeaderId(roster, crewId);
              }
            } else if (isToday) {
              status = _rng.nextDouble() < 0.4 ? FSJobStatus.inProgress : FSJobStatus.scheduled;
            } else {
              status = FSJobStatus.scheduled;
            }

            final notes =
                '${template['crewSize']}, ~${template['hours']} hrs estimated. Quote: \$${template['price']}.';
            final title = '${template['title']} — $custLast Family';
            final statusChangedAt = completedAt ?? cancelledAt ?? createdAt;

            await writer.set(jobsRef.doc(jobId), {
              FSFields.companyId: companyId,
              'title': title,
              'description': null,
              'notes': notes,
              'customerName': '$custFirst $custLast',
              'customerPhone': _fakePhone(),
              'customerEmail': null,
              'customerAddress': pickupAddr,
              'jobLocation': pickupAddr,
              'additionalJobLocations': [dropoffAddr],
              FSFields.startDate: Timestamp.fromDate(DateTime(cursor.year, cursor.month, cursor.day)),
              FSFields.endDate: Timestamp.fromDate(DateTime(cursor.year, cursor.month, cursor.day)),
              'startTime': Timestamp.fromDate(startTime),
              'endTime': Timestamp.fromDate(endTime),
              'assignedCrewIds': [crewId],
              'assignedEmployeeIds': <String>[],
              'assignedVehicleIds': vehicleIds,
              'assignedEquipmentIds': equipmentIds,
              FSFields.status: status,
              FSFields.statusChangedAt: Timestamp.fromDate(statusChangedAt),
              FSFields.statusChangedBy: ownerId,
              'cancellationReason': cancellationReason,
              'cancelledBy': cancelledBy,
              'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt) : null,
              'completedBy': completedBy,
              'completedAt': completedAt != null ? Timestamp.fromDate(completedAt) : null,
              'reopenedBy': null,
              'reopenedAt': null,
              'templateId': null,
              'conversationThreadId': null,
              'createdByUserId': ownerId,
              FSFields.createdAt: Timestamp.fromDate(createdAt),
              FSFields.updatedAt: Timestamp.fromDate(statusChangedAt),
            });

            // Only non-terminal (scheduled/inProgress) jobs get a
            // matching schedule entry — production removes it once a
            // job completes or cancels (JobService.completeJob/
            // cancelJob), so seeded completed/cancelled jobs never had
            // one either.
            if (status == FSJobStatus.scheduled || status == FSJobStatus.inProgress) {
              await writer.set(schedulesRef.doc(), {
                FSFields.companyId: companyId,
                'title': title,
                'description': null,
                'isAllDay': false,
                FSFields.startAt: Timestamp.fromDate(startTime),
                FSFields.endAt: Timestamp.fromDate(endTime),
                'type': 'job',
                FSFields.jobId: jobId,
                'crewIds': [crewId],
                'employeeIds': <String>[],
                FSFields.status: 'published',
                'publishedAt': Timestamp.fromDate(createdAt),
                'publishedBy': ownerId,
                'conflictOverrideAcknowledged': false,
                'createdByUserId': ownerId,
                'lastEditedByUserId': null,
                FSFields.createdAt: Timestamp.fromDate(createdAt),
                FSFields.updatedAt: Timestamp.fromDate(createdAt),
              });
            }
          }
        }
      }

      cursor = cursor.add(const Duration(days: 1));
    }

    await writer.finish();
  }

  List<String> _pickEquipment(List<String> pool) {
    final shuffled = List<String>.from(pool)..shuffle(_rng);
    final count = 2 + _rng.nextInt(2);
    return shuffled.take(count).toList();
  }

  String _fakeAddress() {
    final number = 100 + _rng.nextInt(9800);
    final street = _pick(_streetNames);
    final place = _pick(_neWisconsinCities);
    return '$number $street, ${place['city']}, WI ${place['zip']}';
  }

  String _crewLeaderId(_SeedRoster roster, String crewId) {
    final crewMembers = roster.employees.where((e) => e.crewId == crewId);
    final leader = crewMembers.firstWhere(
      (e) => e.jobTitle.contains('Lead'),
      orElse: () => crewMembers.first,
    );
    return leader.id;
  }

  // ---------------------------------------------------------------
  // Time entries (clock in/out history + breaks)
  // ---------------------------------------------------------------

  Future<void> _seedTimeEntries({
    required String companyId,
    required _SeedRoster roster,
    required DateTime dataStart,
    required DateTime today,
    required Map<String, Set<String>> timeOffDays,
  }) async {
    final timeEntriesRef = _companySub(companyId, FSCompanySub.timeEntries);
    final writer = _BatchWriter(_firestore);
    final rightNow = DateTime.now();

    // Pick 1-2 employees to still be actively clocked in as of right
    // now — a nice live touch for the dashboard, rather than everyone
    // being neatly clocked out. Only worth doing if it's actually
    // plausible: shifts clock in around 7-9am, so if it's earlier than
    // that right now, a "still clocked in" entry would have a clock-in
    // time in the future. Skip the flourish entirely in that case.
    final stillClockedIn = <String>{};
    if (rightNow.hour >= 9) {
      final shuffledTracked = List<_SeedEmployee>.from(roster.employees)..shuffle(_rng);
      for (final e in shuffledTracked.take(1 + _rng.nextInt(2))) {
        stillClockedIn.add(e.id);
      }
    }

    for (final emp in roster.employees) {
      // A handful of extra-long weeks per employee to exercise overtime
      // math — keyed by the Monday that starts the week.
      final overtimeWeeks = <String>{};
      var weekCursor = dataStart;
      while (!weekCursor.isAfter(today)) {
        if (_rng.nextDouble() < 0.08) {
          overtimeWeeks.add(_dateKey(weekCursor));
        }
        weekCursor = weekCursor.add(const Duration(days: 7));
      }

      var day = dataStart;
      while (!day.isAfter(today)) {
        final weekday = day.weekday;
        final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
        final dayKey = _dateKey(day);
        final weekStart = day.subtract(Duration(days: weekday - 1));
        final onOvertimeWeek = overtimeWeeks.contains(_dateKey(weekStart));

        final offToday = timeOffDays[emp.id]?.contains(dayKey) == true;
        final worksSaturday = weekday == DateTime.saturday && _rng.nextDouble() < 0.2;
        final isWorkday = !offToday &&
            weekday != DateTime.sunday &&
            (weekday != DateTime.saturday || worksSaturday);

        if (isWorkday) {
          final baseHour = 7 + _rng.nextInt(2);
          final clockIn = DateTime(day.year, day.month, day.day, baseHour, _rng.nextInt(4) * 5);

          final baseShiftHours = onOvertimeWeek ? 9.5 : 8.0;
          final jitterMinutes = _rng.nextInt(31) - 10; // -10..+20 min
          final shiftMinutes = (baseShiftHours * 60).round() + jitterMinutes;

          final isCurrentlyClockedIn = isToday && stillClockedIn.contains(emp.id);

          final breaks = <Map<String, dynamic>>[];
          if (_rng.nextDouble() < 0.85) {
            final breakStart = clockIn.add(Duration(minutes: (shiftMinutes ~/ 2) - 15));
            final breakEnd = breakStart.add(Duration(minutes: 30 + _rng.nextInt(16)));
            if (!isCurrentlyClockedIn || breakEnd.isBefore(rightNow)) {
              breaks.add({
                'startedAt': Timestamp.fromDate(breakStart),
                'endedAt': Timestamp.fromDate(breakEnd),
                'isPaid': false,
              });
            }
          }
          if (_rng.nextDouble() < 0.3) {
            final breakStart = clockIn.add(Duration(minutes: shiftMinutes ~/ 4));
            final breakEnd = breakStart.add(const Duration(minutes: 15));
            if (!isCurrentlyClockedIn || breakEnd.isBefore(rightNow)) {
              breaks.add({
                'startedAt': Timestamp.fromDate(breakStart),
                'endedAt': Timestamp.fromDate(breakEnd),
                'isPaid': true,
              });
            }
          }

          DateTime? clockOut;
          if (!isCurrentlyClockedIn) {
            clockOut = clockIn.add(Duration(minutes: shiftMinutes));
            if (clockOut.isAfter(rightNow)) {
              clockOut = rightNow.subtract(const Duration(minutes: 5));
            }
          }

          final isEdited = !isCurrentlyClockedIn && clockOut != null && _rng.nextDouble() < 0.04;
          DateTime? originalClockInAt;
          DateTime? editedAt;
          String? editedBy;
          String? editReason;
          if (isEdited) {
            originalClockInAt = clockIn.subtract(Duration(minutes: 10 + _rng.nextInt(15)));
            editedAt = clockOut.add(const Duration(hours: 20));
            editedBy = roster.ownerId;
            editReason = 'Forgot to clock in on time — adjusted after the fact.';
          }

          final entryId = timeEntriesRef.doc().id;
          await writer.set(timeEntriesRef.doc(entryId), {
            FSFields.companyId: companyId,
            FSFields.employeeId: emp.id,
            FSFields.jobId: null,
            FSFields.crewId: emp.crewId,
            FSFields.clockInAt: Timestamp.fromDate(clockIn),
            FSFields.clockOutAt: clockOut != null ? Timestamp.fromDate(clockOut) : null,
            'clockInLocation': null,
            'clockOutLocation': null,
            'isBreak': false,
            'isOutsideGeofenceAtClockIn': false,
            'isOutsideGeofenceAtClockOut': false,
            'notes': null,
            'source': 'clock',
            'editedBy': editedBy,
            'editedAt': editedAt != null ? Timestamp.fromDate(editedAt) : null,
            'editReason': editReason,
            FSFields.originalValue: originalClockInAt != null ? Timestamp.fromDate(originalClockInAt) : null,
            'originalClockOutAt': null,
            'hasPendingCorrectionRequest': false,
            'payPeriodId': null,
            'isLocked': false,
            'breaks': breaks,
            FSFields.createdAt: Timestamp.fromDate(clockIn),
            FSFields.updatedAt: Timestamp.fromDate(clockOut ?? clockIn),
          });
        }

        day = day.add(const Duration(days: 1));
      }
    }

    await writer.finish();
  }

  // ---------------------------------------------------------------
  // Message history — crew group chats, a company-wide thread, and a
  // handful of DMs. Every thread create/message send below runs
  // authenticated AS the real participant sending it (via the same
  // secondary Firebase Auth instance used to mint the employees'
  // accounts), so this satisfies messageThreads/messages' security
  // rules exactly as written — no rules changes needed, since those
  // rules already allow any listed participant to create/send, and
  // already give the company owner an unconditional read/update
  // bypass for finalizing each thread's denormalized preview fields
  // afterward.
  // ---------------------------------------------------------------

  Future<void> _seedMessages({
    required String companyId,
    required _SeedRoster roster,
    required DateTime dataStart,
    required DateTime today,
  }) async {
    final threadsRef = _companySub(companyId, FSCompanySub.messageThreads);
    final employeesById = {for (final e in roster.employees) e.id: e};

    final crewALeader = _crewLeaderId(roster, roster.crewAId);
    final crewBLeader = _crewLeaderId(roster, roster.crewBId);
    final crewAMemberIds = roster.employees.where((e) => e.crewId == roster.crewAId).map((e) => e.id).toList();
    final crewBMemberIds = roster.employees.where((e) => e.crewId == roster.crewBId).map((e) => e.id).toList();
    final manager = roster.employees.firstWhere((e) => e.role == FSRoles.manager);
    final allEmployeeIds = roster.employees.map((e) => e.id).toList();
    final crewAOther = crewAMemberIds.firstWhere((id) => id != crewALeader);
    final crewBOther = crewBMemberIds.firstWhere((id) => id != crewBLeader);

    final threadDefs = <_ThreadSeed>[
      _ThreadSeed(
        id: threadsRef.doc().id,
        type: ThreadType.crew,
        title: 'Crew A',
        crewId: roster.crewAId,
        participantIds: {...crewAMemberIds, manager.id, roster.ownerId}.toList(),
        creatorId: crewALeader,
        senderWeights: {for (final id in crewAMemberIds) id: 3, manager.id: 1, roster.ownerId: 1},
      ),
      _ThreadSeed(
        id: threadsRef.doc().id,
        type: ThreadType.crew,
        title: 'Crew B',
        crewId: roster.crewBId,
        participantIds: {...crewBMemberIds, manager.id, roster.ownerId}.toList(),
        creatorId: crewBLeader,
        senderWeights: {for (final id in crewBMemberIds) id: 3, manager.id: 1, roster.ownerId: 1},
      ),
      _ThreadSeed(
        id: threadsRef.doc().id,
        type: ThreadType.companyWide,
        title: 'Company-wide',
        participantIds: {...allEmployeeIds, roster.ownerId}.toList(),
        creatorId: roster.ownerId,
        senderWeights: {
          roster.ownerId: 4,
          manager.id: 3,
          for (final id in allEmployeeIds) id: 1,
        },
      ),
      _ThreadSeed(
        id: threadsRef.doc().id,
        type: ThreadType.direct,
        participantIds: [crewALeader, roster.ownerId],
        creatorId: crewALeader,
        senderWeights: {crewALeader: 1, roster.ownerId: 1},
      ),
      _ThreadSeed(
        id: threadsRef.doc().id,
        type: ThreadType.manager,
        participantIds: [manager.id, crewBLeader],
        creatorId: manager.id,
        senderWeights: {manager.id: 1, crewBLeader: 1},
      ),
      _ThreadSeed(
        id: threadsRef.doc().id,
        type: ThreadType.direct,
        participantIds: [crewAOther, crewALeader],
        creatorId: crewAOther,
        senderWeights: {crewAOther: 1, crewALeader: 1},
      ),
      _ThreadSeed(
        id: threadsRef.doc().id,
        type: ThreadType.direct,
        participantIds: [crewBOther, roster.ownerId],
        creatorId: crewBOther,
        senderWeights: {crewBOther: 1, roster.ownerId: 1},
      ),
    ];

    // --- Create every thread doc, authenticated as its creator ---
    final threadCreatedAt = <String, DateTime>{};
    for (final t in threadDefs) {
      final createdAt = dataStart.add(Duration(days: _rng.nextInt(14)));
      threadCreatedAt[t.id] = createdAt;
      final map = {
        FSFields.companyId: companyId,
        'type': t.type,
        'title': t.title,
        'participantUserIds': t.participantIds,
        FSFields.crewId: t.crewId,
        FSFields.jobId: null,
        'archivedByUserIds': <String>[],
        'lastMessagePreview': null,
        'lastMessageAt': null,
        'lastMessageSenderId': null,
        'unreadCounts': <String, int>{for (final id in t.participantIds) id: 0},
        'createdByUserId': t.creatorId,
        FSFields.createdAt: Timestamp.fromDate(createdAt),
        FSFields.updatedAt: Timestamp.fromDate(createdAt),
      };

      if (t.creatorId == roster.ownerId) {
        await threadsRef.doc(t.id).set(map);
      } else {
        final creator = employeesById[t.creatorId]!;
        await _asEmployee(creator.firstName, creator.lastName, (fs) async {
          await fs
              .collection(FSCollections.companies)
              .doc(companyId)
              .collection(FSCompanySub.messageThreads)
              .doc(t.id)
              .set(map);
        });
      }
    }

    // --- Build the full message schedule in memory before writing
    // anything, so it can be grouped by sender afterward. ---
    final scheduled = <_ScheduledMessage>[];
    for (final t in threadDefs) {
      final messagesRef = threadsRef.doc(t.id).collection(FSThreadSub.messages);
      final pool = t.type == ThreadType.crew
          ? _crewChatLines
          : t.type == ThreadType.companyWide
              ? _announcementLines
              : _dmLines;
      final weightedSenders = <String>[
        for (final entry in t.senderWeights.entries)
          for (var i = 0; i < entry.value; i++) entry.key,
      ];
      final messageCount = switch (t.type) {
        ThreadType.crew => 45 + _rng.nextInt(40),
        ThreadType.companyWide => 14 + _rng.nextInt(12),
        _ => 8 + _rng.nextInt(14),
      };

      var cursor = threadCreatedAt[t.id]!.add(Duration(hours: 2 + _rng.nextInt(20)));
      for (var i = 0; i < messageCount; i++) {
        if (cursor.isAfter(today)) break;
        // Skip nights/very early mornings so the timeline reads like a
        // real workday conversation.
        if (cursor.hour < 6 || cursor.hour > 21) {
          cursor = cursor.add(Duration(hours: 6 + _rng.nextInt(6)));
          continue;
        }
        scheduled.add(_ScheduledMessage(
          threadId: t.id,
          messageId: messagesRef.doc().id,
          senderId: _pick(weightedSenders),
          body: _pick(pool),
          sentAt: cursor,
        ));
        cursor = cursor.add(Duration(
          hours: _rng.nextInt(30),
          minutes: _rng.nextInt(60),
        ));
      }
    }

    // --- Write messages grouped by sender, authenticated as each one ---
    final byOwner = scheduled.where((m) => m.senderId == roster.ownerId).toList();
    final ownerWriter = _BatchWriter(_firestore);
    for (final m in byOwner) {
      await ownerWriter.set(
        threadsRef.doc(m.threadId).collection(FSThreadSub.messages).doc(m.messageId),
        _messageMap(companyId: companyId, threadId: m.threadId, senderId: m.senderId, body: m.body, sentAt: m.sentAt),
      );
    }
    await ownerWriter.finish();

    for (final emp in roster.employees) {
      final byEmployee = scheduled.where((m) => m.senderId == emp.id).toList();
      if (byEmployee.isEmpty) continue;
      await _asEmployee(emp.firstName, emp.lastName, (fs) async {
        final writer = _BatchWriter(fs);
        for (final m in byEmployee) {
          await writer.set(
            fs
                .collection(FSCollections.companies)
                .doc(companyId)
                .collection(FSCompanySub.messageThreads)
                .doc(m.threadId)
                .collection(FSThreadSub.messages)
                .doc(m.messageId),
            _messageMap(companyId: companyId, threadId: m.threadId, senderId: m.senderId, body: m.body, sentAt: m.sentAt),
          );
        }
        await writer.finish();
      });
    }

    // --- Finalize each thread's denormalized preview fields — done as
    // the owner, who has an unconditional update bypass on every
    // thread regardless of literal participation. ---
    final finalizeWriter = _BatchWriter(_firestore);
    for (final t in threadDefs) {
      final threadMessages = scheduled.where((m) => m.threadId == t.id).toList()
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      if (threadMessages.isEmpty) continue;
      final last = threadMessages.last;
      final preview = last.body.length > 120 ? '${last.body.substring(0, 117)}...' : last.body;

      final unreadCounts = <String, int>{
        for (final id in t.participantIds) id: id == last.senderId ? 0 : (_rng.nextDouble() < 0.3 ? 1 + _rng.nextInt(3) : 0),
      };

      await finalizeWriter.merge(threadsRef.doc(t.id), {
        'lastMessagePreview': preview,
        'lastMessageAt': Timestamp.fromDate(last.sentAt),
        'lastMessageSenderId': last.senderId,
        'unreadCounts': unreadCounts,
      });
    }
    await finalizeWriter.finish();
  }

  Map<String, dynamic> _messageMap({
    required String companyId,
    required String threadId,
    required String senderId,
    required String body,
    required DateTime sentAt,
  }) {
    return {
      FSFields.companyId: companyId,
      'threadId': threadId,
      'senderUserId': senderId,
      'body': body,
      'attachmentUrls': <String>[],
      'isEdited': false,
      'editedAt': null,
      'isDeleted': false,
      'deletedAt': null,
      'deletedByUserId': null,
      FSFields.createdAt: Timestamp.fromDate(sentAt),
    };
  }

  static const _crewChatLines = [
    'Running about 15 minutes behind, traffic backed up by the Fox River bridge.',
    'Anyone grab extra moving blankets before this afternoon?',
    'Nice work today team, that storage unit was a tight fit.',
    'Reminder — inspect the van before heading out tomorrow.',
    "Can someone cover the 9am pickup, I've got a dentist appt.",
    "Got it, I'll swap with you.",
    'Thanks for the help finishing early today.',
    "Watch the driveway on this next job, it's steep and icy.",
    'Bringing extra hand trucks just in case.',
    'Customer tipped the whole crew, appreciate it everyone.',
    'Heads up, cold snap coming — dress warm this week.',
    'Van is due for an oil change soon, remind me to schedule it.',
    'Great job wrapping that piano, no scratches.',
    'See everyone at the shop at 7:30 tomorrow.',
    'Anyone know where the extra furniture pads went?',
    'Found them, they were in the spare van.',
    'Running a little long on this one, might need 30 more minutes.',
    'No problem, take your time.',
    'Reminder: submit your hours by Friday for payroll.',
    'Will do.',
    'Thanks for covering my shift last week.',
    'Anytime.',
    'New pickup just got added for Saturday.',
    'I can take that one.',
    'Nice, thanks.',
    'Watch out, ice on the ramp this morning — Green Bay roads are rough.',
    'Got some great feedback from the customer today.',
    'Love to hear it.',
    'Can we get another dolly, one wheel is squeaking.',
    "I'll grab one from the shop.",
    'Lake effect snow is supposed to hit us tonight, plan for a slow start tomorrow.',
    'Good call, thanks for the heads up.',
    'Anyone else stuck in Packers game traffic on 41 right now?',
    'Yep, same here. Adding 20 minutes to the ETA.',
    'Truck is loaded, heading out now.',
    'Confirmed address with the customer, we are good to go.',
    'That was a heavy one — good teamwork getting the sectional up those stairs.',
    'Appreciate everyone hustling this week, busy stretch.',
    'Equipment check done, everything is accounted for.',
    'See you at the next stop.',
  ];

  static const _announcementLines = [
    'Reminder: time off requests for next month are due by the 25th.',
    'Great job hitting our numbers this month, everyone.',
    'New safety checklist is posted in the shop — please review.',
    'Payroll will be processed a day early next week due to the holiday.',
    'Welcome our newest addition to the team, glad to have you aboard!',
    'Shop will be closed for the holiday, see everyone the following week.',
    'Nice work everyone — busiest stretch yet and zero complaints.',
    'Quick reminder to log your hours daily, not just at the end of the week.',
    'Winter weather policy is posted — check in with dispatch before heading out if roads look bad.',
    'Thanks for a great year, team. Proud of the work we did across the Fox Valley this year.',
    'Sounds good, thanks for the update.',
    'Appreciate you letting us know.',
    'Got it, thank you.',
    'New job board postings are up for next week, take a look when you get a chance.',
    'Reminder that Van 3 is the spare — check it out with dispatch before taking it.',
    'Great teamwork this month, thank you all.',
  ];

  static const _dmLines = [
    'Hey, do you have a minute to talk about next week\'s schedule?',
    'Sure, what\'s up?',
    'Could you lead the crew on Thursday, I\'ll be out.',
    'Yeah, I can do that.',
    'Appreciate it, thanks.',
    'No problem.',
    'Wanted to check in on how the new hire is settling in.',
    'Doing great so far, picking things up quickly.',
    'Good to hear.',
    'Can we push my time off request up a day if possible?',
    'Let me check the schedule and get back to you.',
    'Sounds good, thanks.',
    'Just approved it, you\'re all set.',
    'Awesome, thank you!',
    'Got a customer asking about an add-on job for the same day, are you free?',
    'Should be, send me the details.',
    'On it.',
    'Thanks for stepping up this week, noticed the extra effort.',
    'Appreciate you saying that.',
    'Let me know if you need anything for Saturday\'s job.',
    'Will do, thanks.',
  ];

  // ---------------------------------------------------------------
  // Pay period locking (reuses the real PayPeriodService so the exact
  // same batching/audit-log/entry-stamping logic production uses is
  // what runs here too).
  // ---------------------------------------------------------------

  Future<void> _lockHistoricalPayPeriods({
    required String companyId,
    required String ownerId,
    required DateTime dataStart,
    required DateTime today,
  }) async {
    const periodLengthDays = 14;
    var periodStart = dataStart;
    // Leave the last full period plus whatever's in progress open, so
    // the view/copy-before-locking flow has something live to show,
    // and so today's still-clocked-in entries never end up inside a
    // locked period.
    final lockCutoff = today.subtract(const Duration(days: periodLengthDays));

    while (true) {
      final periodEnd = periodStart.add(const Duration(days: periodLengthDays - 1));
      if (periodEnd.isAfter(lockCutoff)) break;

      final name = _payPeriodService.defaultPeriodName(periodStart, periodEnd);
      try {
        await _payPeriodService.lockPayPeriod(
          companyId: companyId,
          actingUserId: ownerId,
          startDate: periodStart,
          endDate: periodEnd,
          name: name,
        );
      } catch (_) {
        // Already locked, or nothing in range — fine to skip and keep
        // going through the rest of the year's periods.
      }

      periodStart = periodStart.add(const Duration(days: periodLengthDays));
    }
  }

  // ---------------------------------------------------------------
  // Small shared helpers
  // ---------------------------------------------------------------

  T _pick<T>(List<T> list) => list[_rng.nextInt(list.length)];

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  String _fakePhone() {
    final exchange = 200 + _rng.nextInt(800);
    final line = _rng.nextInt(10000);
    return '(920) $exchange-${line.toString().padLeft(4, '0')}';
  }

  String _fakeVin() {
    const chars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789';
    return List.generate(17, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  String _fakeSerial() {
    const chars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789';
    return 'SN-${List.generate(8, (_) => chars[_rng.nextInt(chars.length)]).join()}';
  }
}

class _SeedEmployee {
  final String id;
  final String firstName;
  final String lastName;
  final String role;
  final String jobTitle;
  final String? crewId;

  const _SeedEmployee({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.jobTitle,
    this.crewId,
  });
}

class _SeedRoster {
  final String ownerId;
  final List<_SeedEmployee> employees;
  final String crewAId;
  final String crewBId;

  const _SeedRoster({
    required this.ownerId,
    required this.employees,
    required this.crewAId,
    required this.crewBId,
  });
}

class _SeedFleet {
  final Map<String, String> vanIdByCrew;
  final String spareVanId;
  final List<String> equipmentIds;

  const _SeedFleet({
    required this.vanIdByCrew,
    required this.spareVanId,
    required this.equipmentIds,
  });
}

class _ThreadSeed {
  final String id;
  final String type;
  final String? title;
  final String? crewId;
  final List<String> participantIds;
  final String creatorId;
  final Map<String, int> senderWeights;

  const _ThreadSeed({
    required this.id,
    required this.type,
    this.title,
    this.crewId,
    required this.participantIds,
    required this.creatorId,
    required this.senderWeights,
  });
}

class _ScheduledMessage {
  final String threadId;
  final String messageId;
  final String senderId;
  final String body;
  final DateTime sentAt;

  const _ScheduledMessage({
    required this.threadId,
    required this.messageId,
    required this.senderId,
    required this.body,
    required this.sentAt,
  });
}

/// Batches writes at a safe margin under Firestore's 500-ops-per-batch
/// limit, auto-committing and starting a fresh batch as it fills up.
class _BatchWriter {
  final FirebaseFirestore firestore;
  WriteBatch _batch;
  int _pending = 0;
  static const _maxOpsPerBatch = 400;

  _BatchWriter(this.firestore) : _batch = firestore.batch();

  Future<void> set(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    _batch.set(ref, data);
    _pending++;
    if (_pending >= _maxOpsPerBatch) {
      await _flush();
    }
  }

  Future<void> merge(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    _batch.set(ref, data, SetOptions(merge: true));
    _pending++;
    if (_pending >= _maxOpsPerBatch) {
      await _flush();
    }
  }

  Future<void> delete(DocumentReference<Map<String, dynamic>> ref) async {
    _batch.delete(ref);
    _pending++;
    if (_pending >= _maxOpsPerBatch) {
      await _flush();
    }
  }

  Future<void> _flush() async {
    if (_pending == 0) return;
    await _batch.commit();
    _batch = firestore.batch();
    _pending = 0;
  }

  Future<void> finish() async {
    await _flush();
  }
}
