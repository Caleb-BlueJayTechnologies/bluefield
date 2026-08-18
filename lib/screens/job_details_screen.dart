import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Models/equipment_model.dart';
import '../Models/job_model.dart';
import '../Models/vehicle_model.dart';
import '../Services/auth_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/equipment_service.dart';
import '../Services/job_service.dart';
import '../Services/messaging_service.dart';
import '../Services/vehicle_service.dart';
import '../theme/app_theme.dart';
import 'conversation_screen.dart';
import 'Vehicles_screen.dart';

/// Employee-facing, read-only job view — no edit/cancel actions, only
/// directions, assignment info, and (if not yet terminal) marking the
/// job complete. The management version with full editing lives in
/// employer_job_details_screen.dart.
class JobDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> jobData;

  const JobDetailsScreen({super.key, required this.jobData});

  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen> {
  final AuthService _authService = AuthService();
  final JobService _jobService = JobService();
  final EmployeeService _employeeService = EmployeeService();
  final CrewService _crewService = CrewService();
  final VehicleService _vehicleService = VehicleService();
  final EquipmentService _equipmentService = EquipmentService();
  final MessagingService _messagingService = MessagingService();

  late JobModel _job;
  late Future<_JobDetailsReferenceData> _referenceFuture;
  bool _isCompleting = false;
  bool _isMessaging = false;

  @override
  void initState() {
    super.initState();
    final jobId = widget.jobData[FSFields.jobId]?.toString() ?? '';
    _job = JobModel.fromMap(jobId, widget.jobData);
    _referenceFuture = _loadReferenceData();
  }

  Future<_JobDetailsReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final allEmployees = await _employeeService.getEmployeesByCompany(companyId: companyId);
    final employeesById = {for (final e in allEmployees) e.employeeId: e.employee};

    final allCrews = await _crewService.getCrewsByCompany(companyId: companyId, includeArchived: true);
    final crewsById = {for (final c in allCrews) c.crewId: c};

    Map<String, VehicleModel> vehiclesById = {};
    try {
      final allVehicles = await _vehicleService.getVehiclesByCompany(companyId: companyId, includeArchived: true);
      vehiclesById = {for (final v in allVehicles) v.vehicleId: v};
    } catch (_) {
      // Vehicle info is supplementary — the rest of the job's details
      // should still load and be usable even if this fetch fails.
    }

    Map<String, EquipmentModel> equipmentById = {};
    try {
      final allEquipment = await _equipmentService.getEquipmentByCompany(companyId: companyId, includeArchived: true);
      equipmentById = {for (final e in allEquipment) e.equipmentId: e};
    } catch (_) {
      // Same reasoning as above for equipment.
    }

    return _JobDetailsReferenceData(
      companyId: companyId,
      actingUserId: profile.uid,
      employeesById: employeesById,
      crewsById: crewsById,
      vehiclesById: vehiclesById,
      equipmentById: equipmentById,
    );
  }

  bool _hasUsableAddress(String? address) => (address?.trim() ?? '').isNotEmpty;

  Future<void> _openGoogleDirections(BuildContext context, String address) async {
    if (!_hasUsableAddress(address)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No address available for directions.')),
      );
      return;
    }

    final encodedAddress = Uri.encodeComponent(address.trim());
    final googleMapsAppUri = Uri.parse('comgooglemaps://?daddr=$encodedAddress&directionsmode=driving');
    final googleMapsWebUri =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encodedAddress&travelmode=driving');

    try {
      if (await canLaunchUrl(googleMapsAppUri)) {
        await launchUrl(googleMapsAppUri, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(googleMapsWebUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to open maps.')));
    }
  }

  Future<void> _callNumber(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to open phone dialer.')));
    }
  }

  Future<void> _emailAddress(BuildContext context, String email) async {
    final uri = Uri(scheme: 'mailto', path: email.trim());
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to open email app.')));
    }
  }

  Future<void> _markComplete(_JobDetailsReferenceData reference) async {
    if (_jobService.requiresMultiDayCompletionWarning(_job)) {
      final end = _job.endDate;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Complete Multi-Day Job?'),
            content: Text(
              'This job is scheduled through ${end.month}/${end.day}/${end.year}. '
              'Completing it now will close the job and remove it from all remaining scheduled days.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Complete Job')),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }

    setState(() => _isCompleting = true);

    try {
      await _jobService.completeJob(companyId: reference.companyId, actingUserId: reference.actingUserId, jobId: _job.jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job marked complete.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  Future<void> _openCrewChat(_JobDetailsReferenceData reference) async {
    setState(() => _isMessaging = true);
    try {
      String? threadId = _job.conversationThreadId;

      if (threadId == null) {
        final participants = <String>{
          ..._job.assignedEmployeeIds,
          for (final crewId in _job.assignedCrewIds)
            ...reference.employeesById.values.where((e) => e.crewIds.contains(crewId)).map((e) => e.employeeId),
        }.toList();

        threadId = await _messagingService.createJobThread(
          companyId: reference.companyId,
          actingUserId: reference.actingUserId,
          jobId: _job.jobId,
          jobTitle: _job.title,
          participantUserIds: participants,
        );
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConversationScreen(companyId: reference.companyId, threadId: threadId!),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isMessaging = false);
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '';
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text('Job Details', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<_JobDetailsReferenceData>(
        future: _referenceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  snapshot.error?.toString() ?? 'Unable to load job.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ),
            );
          }

          final reference = snapshot.data!;
          final address = _job.jobLocation ?? _job.customerAddress;
          final crewNames = _job.assignedCrewIds.map((id) => reference.crewsById[id]?.crewName).whereType<String>().join(', ');
          final employeeNames =
              _job.assignedEmployeeIds.map((id) => reference.employeesById[id]?.fullName).whereType<String>().join(', ');
          final dateText = _job.isMultiDay
              ? '${_job.startDate.month}/${_job.startDate.day} - ${_job.endDate.month}/${_job.endDate.day}/${_job.endDate.year}'
              : '${_job.startDate.month}/${_job.startDate.day}/${_job.startDate.year}';
          final timeText = _job.isAllDay ? 'All day' : _formatTime(_job.startTime);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(_job.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
              if (address != null) ...[
                const SizedBox(height: 4),
                Text(address, style: const TextStyle(fontSize: 18, color: AppTheme.mutedText)),
              ],
              ..._job.additionalJobLocations.map(
                (loc) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(loc, style: const TextStyle(fontSize: 15, color: AppTheme.mutedText)),
                ),
              ),
              const SizedBox(height: 16),
              if (_hasUsableAddress(address))
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () => _openGoogleDirections(context, address!),
                    icon: const Icon(Icons.directions),
                    label: const Text('Directions'),
                  ),
                ),
              if (_job.hasAdditionalLocations)
                ..._job.additionalJobLocations.asMap().entries.map((entry) {
                  final index = entry.key;
                  final loc = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () => _openGoogleDirections(context, loc),
                        icon: const Icon(Icons.directions_outlined),
                        label: Text(_job.additionalJobLocations.length == 1
                            ? 'Directions to Additional Location'
                            : 'Directions to Location ${index + 2}'),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 18),
              DetailCard(
                title: 'Time',
                icon: Icons.access_time,
                child: Text(
                  '$dateText • $timeText',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkText),
                ),
              ),
              if (_job.hasCustomer)
                DetailCard(
                  title: 'Customer',
                  icon: Icons.person_outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BulletText(_job.customerName ?? 'Not provided'),
                      if (_job.customerPhone?.trim().isNotEmpty == true)
                        TappableBulletText(_job.customerPhone!, onTap: () => _callNumber(context, _job.customerPhone!)),
                      if (_job.customerEmail?.trim().isNotEmpty == true)
                        TappableBulletText(_job.customerEmail!, onTap: () => _emailAddress(context, _job.customerEmail!)),
                    ],
                  ),
                ),
              DetailCard(
                title: 'Location',
                icon: Icons.location_on_outlined,
                child: BulletText(address ?? 'No location provided'),
              ),
              if (_job.notes?.trim().isNotEmpty == true)
                DetailCard(title: 'Notes', icon: Icons.notes_outlined, child: BulletText(_job.notes!)),
              DetailCard(
                title: 'Assignment',
                icon: Icons.groups_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BulletText('Crew: ${crewNames.isEmpty ? 'Unassigned' : crewNames}'),
                    BulletText('Employees: ${employeeNames.isEmpty ? 'No employees assigned' : employeeNames}'),
                  ],
                ),
              ),
              if (_job.assignedVehicleIds.isNotEmpty || _job.assignedEquipmentIds.isNotEmpty)
                DetailCard(
                  title: 'Vehicle & Equipment',
                  icon: Icons.local_shipping_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._job.assignedVehicleIds.map((id) {
                        final vehicle = reference.vehiclesById[id];
                        final label = vehicle != null
                            ? 'Vehicle: ${vehicle.name}${vehicle.displaySpec.isNotEmpty ? ' (${vehicle.displaySpec})' : ''}'
                            : 'Vehicle: not found';
                        return vehicle == null
                            ? BulletText(label)
                            : TappableBulletText(
                                label,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const VehiclesScreen()),
                                  );
                                },
                              );
                      }),
                      ..._job.assignedEquipmentIds.map((id) {
                        final item = reference.equipmentById[id];
                        return BulletText('Equipment: ${item?.name ?? 'not found'}');
                      }),
                    ],
                  ),
                ),
              DetailCard(
                title: 'Crew Chat',
                icon: Icons.chat_bubble_outline,
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _isMessaging ? null : () => _openCrewChat(reference),
                    icon: const Icon(Icons.message_outlined),
                    label: Text(_isMessaging ? 'Opening...' : 'Open Crew Chat'),
                  ),
                ),
              ),
              if (!_job.isTerminal)
                DetailCard(
                  title: 'Job Status',
                  icon: Icons.check_circle_outline,
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: _isCompleting ? null : () => _markComplete(reference),
                      icon: const Icon(Icons.check),
                      label: Text(_isCompleting ? 'Completing...' : 'Mark Job Complete'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _JobDetailsReferenceData {
  final String companyId;
  final String actingUserId;
  final Map<String, EmployeeModel> employeesById;
  final Map<String, CrewModel> crewsById;
  final Map<String, VehicleModel> vehiclesById;
  final Map<String, EquipmentModel> equipmentById;

  const _JobDetailsReferenceData({
    required this.companyId,
    required this.actingUserId,
    required this.employeesById,
    required this.crewsById,
    this.vehiclesById = const {},
    this.equipmentById = const {},
  });
}

class DetailCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const DetailCard({super.key, required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.blue),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkText)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class BulletText extends StatelessWidget {
  final String text;

  const BulletText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text('• $text', style: const TextStyle(fontSize: 15, color: AppTheme.darkText)),
    );
  }
}

/// Same visual rhythm as [BulletText], but tappable — used for a
/// customer's phone/email so tapping it calls or emails them directly,
/// same tel:/mailto: pattern as the existing Directions button uses
/// for addresses.
class TappableBulletText extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const TappableBulletText(this.text, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          '• $text',
          style: const TextStyle(fontSize: 15, color: AppTheme.blue, decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}
