import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/support_ticket_model.dart';
import 'platform_admin_service.dart';

class TicketStats {
  final int total;
  final int open;
  final int closed;
  final int critical;
  final int newToday;

  const TicketStats({
    required this.total,
    required this.open,
    required this.closed,
    required this.critical,
    required this.newToday,
  });
}

class SupportTicketService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PlatformAdminService _adminService = PlatformAdminService();

  CollectionReference<Map<String, dynamic>> get _ticketsRef =>
      _firestore.collection(FSCollections.supportTickets);

  Future<void> _requireAdmin(String actingAdminId) async {
    // Uses getCurrentAdmin() rather than a plain lookup-by-ID — that
    // method has the bootstrap-admin fallback (see
    // PlatformAdminService.bootstrapSuperAdminEmail), which a raw
    // getAdmin(actingAdminId) lookup does not. Without this, the
    // bootstrap admin's own status/resolution-notes updates would
    // silently fail with a permission error any time their
    // platformAdmins doc hasn't actually been written yet (e.g. before
    // security rules are deployed). actingAdminId is always the
    // caller's own current UID in every real call site, so relying on
    // "whoever is currently signed in" here is equivalent, just safer.
    final admin = await _adminService.getCurrentAdmin();
    if (admin == null || admin.adminId != actingAdminId || !admin.canManageTickets) {
      throw Exception('You do not have permission to manage support tickets.');
    }
  }

  /// Gathers everything in the spec's "Automatic Metadata" section —
  /// the submitting user never types any of this in themselves.
  Future<TicketMetadata> collectMetadata() async {
    final packageInfo = await PackageInfo.fromPlatform();
    String? deviceModel;
    String? osVersion;
    String platformName;

    // dart:io's Platform class doesn't exist on Flutter Web at all —
    // touching Platform.operatingSystem there throws
    // UnsupportedError immediately, before any try/catch below even
    // runs. kIsWeb must be checked first, and web gets its own real
    // metadata path via device_info_plus's webBrowserInfo rather than
    // just silently skipping deviceModel/osVersion.
    if (kIsWeb) {
      platformName = 'web';
      try {
        final info = await DeviceInfoPlugin().webBrowserInfo;
        deviceModel = info.browserName.name;
        osVersion = info.platform;
      } catch (_) {
        // Browser info isn't guaranteed available everywhere either —
        // the ticket still submits fine without it.
      }
    } else {
      platformName = Platform.operatingSystem;
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final info = await deviceInfo.androidInfo;
          deviceModel = '${info.manufacturer} ${info.model}';
          osVersion = 'Android ${info.version.release}';
        } else if (Platform.isIOS) {
          final info = await deviceInfo.iosInfo;
          deviceModel = info.utsname.machine;
          osVersion = '${info.systemName} ${info.systemVersion}';
        }
      } catch (_) {
        // Device info isn't available on every platform (desktop
        // testing, etc.) — the ticket still gets submitted either way,
        // just without these two optional fields.
      }
    }

    return TicketMetadata(
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      platform: platformName,
      deviceModel: deviceModel,
      osVersion: osVersion,
    );
  }

  /// Uploads a single screenshot to
  /// `supportTicketScreenshots/{companyId}/{ticketId}/{fileName}` and
  /// returns its public download URL. Call once per selected image
  /// before submitting the ticket.
  Future<String> uploadScreenshot({
    required String companyId,
    required String ticketId,
    required XFile image,
  }) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
    final ref = FirebaseStorage.instance
        .ref()
        .child('supportTicketScreenshots')
        .child(companyId)
        .child(ticketId)
        .child(fileName);

    final bytes = await image.readAsBytes();
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  /// Creates the ticket doc first (Firestore is always the source of
  /// truth per the spec), then reserves the ID for screenshot uploads.
  /// Call this BEFORE uploadScreenshot so uploads land under the real
  /// ticketId, then call attachScreenshots after uploading to save the
  /// URLs onto the ticket.
  Future<String> submitTicket({
    required String companyId,
    required String companyName,
    required String userId,
    required String employeeName,
    required String employeeRole,
    required String category,
    required String priority,
    required String subject,
    required String description,
  }) async {
    final metadata = await collectMetadata();

    final ref = _ticketsRef.doc();
    await ref.set(SupportTicketModel.toMapForCreate(
      companyId: companyId,
      companyName: companyName,
      userId: userId,
      employeeName: employeeName,
      employeeRole: employeeRole,
      category: category,
      priority: priority,
      subject: subject,
      description: description,
      metadata: metadata,
    ));

    return ref.id;
  }

  Future<void> attachScreenshots({
    required String ticketId,
    required List<String> screenshotUrls,
  }) async {
    if (screenshotUrls.isEmpty) return;
    await _ticketsRef.doc(ticketId).update({
      'screenshotUrls': screenshotUrls,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // --- Company-facing reads (strictly own company only) ---

  /// Graduated, role-based visibility — matches firestore.rules'
  /// supportTickets read rule exactly, which is why this can't be one
  /// broad companyId query filtered client-side afterward the way
  /// watchAllTickets (admin-side) does it: Firestore's per-document
  /// rule check fails the ENTIRE list request if even one returned doc
  /// would be denied, so the query itself — not a post-hoc filter —
  /// has to guarantee every result is one this caller is allowed to
  /// see.
  ///   - employee: only their own tickets.
  ///   - manager: their own, plus every employee-submitted ticket
  ///     (not other managers'). Two disjoint queries, merged here.
  ///   - owner: every ticket in the company (same as before).
  Stream<List<SupportTicketModel>> watchCompanyTickets({
    required String companyId,
    required String userId,
    required String role,
  }) {
    if (role == FSRoles.owner) {
      return _ticketsRef
          .where(FSFields.companyId, isEqualTo: companyId)
          .orderBy(FSFields.createdAt, descending: true)
          .snapshots()
          .map((snap) => snap.docs.map((d) => SupportTicketModel.fromSnapshot(d)).toList());
    }

    final ownQuery = _ticketsRef
        .where(FSFields.companyId, isEqualTo: companyId)
        .where(FSFields.userId, isEqualTo: userId)
        .snapshots();

    if (role != FSRoles.manager) {
      // Employee: own tickets only.
      return ownQuery.map((snap) => snap.docs.map((d) => SupportTicketModel.fromSnapshot(d)).toList());
    }

    final employeeQuery = _ticketsRef
        .where(FSFields.companyId, isEqualTo: companyId)
        .where('employeeRole', isEqualTo: FSRoles.employee)
        .snapshots();
    return _mergeTicketQueries([ownQuery, employeeQuery]);
  }

  /// Merges multiple live ticket queries into one deduped, sorted
  /// stream — de-duped by ticketId (a manager's own query can never
  /// actually overlap with the employeeRole=='employee' query since a
  /// manager's own employeeRole is 'manager', but de-duping here means
  /// this stays correct even if that assumption ever changes) and
  /// re-sorted by createdAt every time either underlying query updates.
  Stream<List<SupportTicketModel>> _mergeTicketQueries(
    List<Stream<QuerySnapshot<Map<String, dynamic>>>> queries,
  ) {
    late final StreamController<List<SupportTicketModel>> controller;
    final latest = List<List<SupportTicketModel>>.generate(queries.length, (_) => const []);
    final subscriptions = <StreamSubscription>[];

    void emit() {
      final merged = <String, SupportTicketModel>{};
      for (final list in latest) {
        for (final ticket in list) {
          merged[ticket.ticketId] = ticket;
        }
      }
      final combined = merged.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(combined);
    }

    controller = StreamController<List<SupportTicketModel>>.broadcast(
      onListen: () {
        for (var i = 0; i < queries.length; i++) {
          final index = i;
          subscriptions.add(queries[i].listen(
            (snap) {
              latest[index] = snap.docs.map((d) => SupportTicketModel.fromSnapshot(d)).toList();
              emit();
            },
            onError: controller.addError,
          ));
        }
      },
      onCancel: () async {
        for (final sub in subscriptions) {
          await sub.cancel();
        }
      },
    );

    return controller.stream;
  }

  Future<SupportTicketModel?> getTicket(String ticketId) async {
    final doc = await _ticketsRef.doc(ticketId).get();
    if (!doc.exists) return null;
    return SupportTicketModel.fromSnapshot(doc);
  }

  Stream<SupportTicketModel?> watchTicket(String ticketId) {
    return _ticketsRef.doc(ticketId).snapshots().map(
          (doc) => doc.exists ? SupportTicketModel.fromSnapshot(doc) : null,
        );
  }

  // --- Admin-facing reads/actions (gated by PlatformAdminService) ---

  /// Every ticket across every company — the entire point of a root
  /// (not company-nested) collection is that this is a single flat
  /// query rather than a collectionGroup fan-out across companies.
  /// Filters client-side rather than via Firestore .where() clauses on
  /// purpose — with 3 independent optional filters (status, category,
  /// priority), every combination an admin might select needs its own
  /// separate Firestore composite index (7 combinations for 3 filters).
  /// That's exactly what caused the reported bug: priority alone
  /// happened to have an index from an earlier query-error link, but
  /// category/status never did, so those filters silently failed.
  /// Streaming everything sorted by createdAt needs no composite index
  /// at all (single-field sort), and ticket volume at this app's scale
  /// makes client-side filtering the more robust choice — no index to
  /// remember to add every time a new filter combination gets used.
  Stream<List<SupportTicketModel>> watchAllTickets({
    String? statusFilter,
    String? categoryFilter,
    String? priorityFilter,
  }) {
    return _ticketsRef.orderBy(FSFields.createdAt, descending: true).snapshots().map((snap) {
      var tickets = snap.docs.map((d) => SupportTicketModel.fromSnapshot(d)).toList();

      if (statusFilter != null) {
        tickets = tickets.where((t) => t.status == statusFilter).toList();
      }
      if (categoryFilter != null) {
        tickets = tickets.where((t) => t.category == categoryFilter).toList();
      }
      if (priorityFilter != null) {
        tickets = tickets.where((t) => t.priority == priorityFilter).toList();
      }

      return tickets;
    });
  }

  Future<TicketStats> getTicketStats() async {
    final snapshot = await _ticketsRef.get();
    final tickets = snapshot.docs.map((d) => SupportTicketModel.fromSnapshot(d)).toList();

    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    return TicketStats(
      total: tickets.length,
      open: tickets.where((t) => t.isOpen).length,
      closed: tickets.where((t) => !t.isOpen).length,
      critical: tickets.where((t) => t.isCritical && t.isOpen).length,
      newToday: tickets.where((t) => t.createdAt.isAfter(todayStart)).length,
    );
  }

  /// Live version of [getTicketStats] — same computation, recalculated
  /// on every snapshot instead of once. This is what the Admin
  /// Dashboard should use so open/closed/critical counts update
  /// immediately as tickets change, instead of only refreshing when
  /// the admin manually pulls to refresh.
  Stream<TicketStats> watchTicketStats() {
    return _ticketsRef.snapshots().map((snapshot) {
      final tickets = snapshot.docs.map((d) => SupportTicketModel.fromSnapshot(d)).toList();

      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);

      return TicketStats(
        total: tickets.length,
        open: tickets.where((t) => t.isOpen).length,
        closed: tickets.where((t) => !t.isOpen).length,
        critical: tickets.where((t) => t.isCritical && t.isOpen).length,
        newToday: tickets.where((t) => t.createdAt.isAfter(todayStart)).length,
      );
    });
  }

  Future<void> updateTicketStatus({
    required String actingAdminId,
    required String ticketId,
    required String newStatus,
    String? resolutionNotes,
  }) async {
    await _requireAdmin(actingAdminId);

    // Stamped when moving into ANY final status (resolved, closed, or
    // rejected), cleared moving out of one — this is what the
    // company-facing 1-week visibility window is measured from (see
    // SupportTicketModel.shouldHideFromCompanyView). Covering all
    // three, not just resolved, means a ticket an admin closes or
    // rejects directly (skipping resolved entirely) still ages out of
    // "My Tickets" after a week instead of lingering forever with a
    // null timestamp. Clearing it on any non-final status change means
    // a reopen-then-re-close cycle correctly restarts the window from
    // the new final status instead of using a stale timestamp from
    // before.
    final isFinalStatus = newStatus == FSTicketStatus.resolved ||
        newStatus == FSTicketStatus.closed ||
        newStatus == FSTicketStatus.rejected;
    final updates = <String, dynamic>{
      FSFields.status: newStatus,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
      'resolvedAt': isFinalStatus ? FieldValue.serverTimestamp() : null,
    };
    if (resolutionNotes != null) {
      updates['resolutionNotes'] = resolutionNotes;
    }

    await _ticketsRef.doc(ticketId).update(updates);
  }

  Future<void> assignTicket({
    required String actingAdminId,
    required String ticketId,
    required String? assignedAdminId,
  }) async {
    await _requireAdmin(actingAdminId);

    await _ticketsRef.doc(ticketId).update({
      'assignedAdminId': assignedAdminId,
      FSFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  /// Marks the email backup as sent. In practice this field is set by
  /// the Cloud Function itself (see functions/src/index.ts) once it
  /// confirms delivery — a client can't verify that directly. Kept
  /// here too for completeness / manual correction if ever needed.
  Future<void> markEmailSent(String ticketId) async {
    await _ticketsRef.doc(ticketId).update({
      'emailSent': true,
      'emailSentAt': FieldValue.serverTimestamp(),
    });
  }
}
