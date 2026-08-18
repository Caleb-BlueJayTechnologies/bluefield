import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'edit_job_screen.dart';
import 'Vehicles_screen.dart';

class EmployerJobDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> jobData;

  const EmployerJobDetailsScreen({super.key, required this.jobData});

  @override
  State<EmployerJobDetailsScreen> createState() => _EmployerJobDetailsScreenState();
}

class _EmployerJobDetailsScreenState extends State<EmployerJobDetailsScreen> {
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

  bool _hasUsableAddress(String? address) {
    final cleaned = address?.trim().toLowerCase() ?? '';
    return cleaned.isNotEmpty;
  }

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
    // The multi-day confirmation this button was completely missing —
    // Section 7's suggested copy, shown only when the job actually
    // spans multiple days.
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
      await _jobService.completeJob(
        companyId: reference.companyId,
        actingUserId: reference.actingUserId,
        jobId: _job.jobId,
      );

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

  Future<void> _openJobConversation(_JobDetailsReferenceData reference) async {
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

        // JobService doesn't expose a setConversationThread method yet,
        // so this is a direct single-field write rather than a full
        // service round-trip — narrow enough to be low-risk.
        await FirebaseFirestore.instance
            .collection(FSCollections.companies)
            .doc(reference.companyId)
            .collection(FSCompanySub.jobs)
            .doc(_job.jobId)
            .update({'conversationThreadId': threadId});
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

  String _statusLabel(String status) {
    switch (status) {
      case FSJobStatus.draft:
        return 'Draft';
      case FSJobStatus.scheduled:
        return 'Scheduled';
      case FSJobStatus.inProgress:
        return 'In Progress';
      case FSJobStatus.completed:
        return 'Completed';
      case FSJobStatus.cancelled:
        return 'Cancelled';
      case FSJobStatus.archived:
        return 'Archived';
      default:
        return status;
    }
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
          final crewNames = _job.assignedCrewIds
              .map((id) => reference.crewsById[id]?.crewName)
              .whereType<String>()
              .join(', ');
          final employeeNames = _job.assignedEmployeeIds
              .map((id) => reference.employeesById[id]?.fullName)
              .whereType<String>()
              .join(', ');
          final address = _job.jobLocation ?? _job.customerAddress;
          final dateText = _job.isMultiDay
              ? '${_job.startDate.month}/${_job.startDate.day} - ${_job.endDate.month}/${_job.endDate.day}/${_job.endDate.year}'
              : '${_job.startDate.month}/${_job.startDate.day}/${_job.startDate.year}';

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
            children: [
              JobHeaderCard(
                jobName: _job.title,
                status: _statusLabel(_job.status),
                crew: crewNames.isEmpty ? 'Unassigned' : crewNames,
                vehicle: _job.assignedVehicleIds.isNotEmpty
                    ? _job.assignedVehicleIds.map((id) => reference.vehiclesById[id]?.name ?? 'Unknown vehicle').join(', ')
                    : 'No vehicle',
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 14),
              if (_hasUsableAddress(address) || _job.hasAdditionalLocations)
                JobInfoCard(
                  title: 'Locations',
                  icon: Icons.place_outlined,
                  children: [
                    if (_hasUsableAddress(address))
                      JobDetailRow(title: address!, subtitle: 'Primary location', icon: Icons.location_on_outlined),
                    ..._job.additionalJobLocations.asMap().entries.map(
                          (entry) => JobDetailRow(
                            title: entry.value,
                            subtitle: _job.additionalJobLocations.length == 1
                                ? 'Additional location'
                                : 'Location ${entry.key + 2}',
                            icon: Icons.location_on_outlined,
                          ),
                        ),
                  ],
                ),
              if (_job.hasCustomer)
                JobInfoCard(
                  title: 'Customer',
                  icon: Icons.person_outline,
                  children: [
                    JobDetailRow(
                      title: _job.customerName ?? 'Not provided',
                      subtitle: 'Customer name',
                      icon: Icons.person_outline,
                    ),
                    if (_job.customerPhone?.trim().isNotEmpty == true)
                      JobDetailRow(
                        title: _job.customerPhone!,
                        subtitle: 'Tap to call',
                        icon: Icons.phone_outlined,
                        onTap: () => _callNumber(context, _job.customerPhone!),
                      )
                    else
                      const JobDetailRow(title: 'Not provided', subtitle: 'Phone', icon: Icons.phone_outlined),
                    if (_job.customerEmail?.trim().isNotEmpty == true)
                      JobDetailRow(
                        title: _job.customerEmail!,
                        subtitle: 'Tap to email',
                        icon: Icons.email_outlined,
                        onTap: () => _emailAddress(context, _job.customerEmail!),
                      )
                    else
                      const JobDetailRow(title: 'Not provided', subtitle: 'Email', icon: Icons.email_outlined),
                  ],
                ),
              JobInfoCard(
                title: 'Schedule',
                icon: Icons.schedule_outlined,
                children: [
                  JobDetailRow(title: dateText, subtitle: _job.isAllDay ? 'All day' : 'Scheduled time set', icon: Icons.calendar_month_outlined),
                ],
              ),
              JobInfoCard(
                title: 'Location',
                icon: Icons.location_on_outlined,
                children: [
                  JobDetailRow(title: address ?? 'No location', subtitle: 'Job site', icon: Icons.home_outlined),
                ],
              ),
              JobInfoCard(
                title: 'Assignment',
                icon: Icons.groups_outlined,
                children: [
                  JobDetailRow(title: crewNames.isEmpty ? 'Unassigned' : crewNames, subtitle: 'Assigned crew', icon: Icons.groups_outlined),
                  JobDetailRow(
                    title: employeeNames.isEmpty ? 'No employees assigned' : employeeNames,
                    subtitle: 'Assigned employees',
                    icon: Icons.person_add_alt_outlined,
                  ),
                ],
              ),
              if (_job.assignedVehicleIds.isNotEmpty || _job.assignedEquipmentIds.isNotEmpty)
                JobInfoCard(
                  title: 'Vehicle & Equipment',
                  icon: Icons.local_shipping_outlined,
                  children: [
                    ..._job.assignedVehicleIds.map((id) {
                      final vehicle = reference.vehiclesById[id];
                      return InkWell(
                        onTap: vehicle == null
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const VehiclesScreen()),
                                );
                              },
                        child: JobDetailRow(
                          title: vehicle?.name ?? 'Vehicle not found',
                          subtitle: vehicle != null && vehicle.displaySpec.isNotEmpty ? vehicle.displaySpec : 'Assigned vehicle',
                          icon: Icons.directions_car_outlined,
                        ),
                      );
                    }),
                    ..._job.assignedEquipmentIds.map((id) {
                      final item = reference.equipmentById[id];
                      return JobDetailRow(
                        title: item?.name ?? 'Equipment not found',
                        subtitle: item?.category ?? 'Assigned equipment',
                        icon: Icons.construction_outlined,
                      );
                    }),
                  ],
                ),
              if (_job.notes?.trim().isNotEmpty == true)
                JobInfoCard(
                  title: 'Notes',
                  icon: Icons.notes_outlined,
                  children: [
                    JobDetailRow(title: 'Notes', subtitle: _job.notes!, icon: Icons.notes_outlined),
                  ],
                ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => EditJobScreen(jobData: widget.jobData)));
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Job'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isMessaging ? null : () => _openJobConversation(reference),
                  icon: const Icon(Icons.message_outlined),
                  label: Text(_isMessaging ? 'Opening...' : 'Message About This Job'),
                ),
              ),
              const SizedBox(height: 10),
              if (!_job.isTerminal)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _isCompleting ? null : () => _markComplete(reference),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_isCompleting ? 'Completing...' : 'Mark Complete'),
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

class JobHeaderCard extends StatelessWidget {
  final String jobName;
  final String status;
  final String crew;
  final String vehicle;

  const JobHeaderCard({super.key, required this.jobName, required this.status, required this.crew, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppTheme.blue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 34,
              backgroundColor: Colors.white,
              child: Icon(Icons.local_shipping_outlined, color: AppTheme.blue, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jobName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('$status • $crew • $vehicle', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JobInfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const JobInfoCard({super.key, required this.title, required this.icon, required this.children});

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
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class JobDetailRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const JobDetailRow({super.key, required this.title, required this.subtitle, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.blue),
      title: Text(
        title,
        style: TextStyle(
          color: onTap != null ? AppTheme.blue : AppTheme.darkText,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.mutedText)),
      trailing: onTap != null ? const Icon(Icons.chevron_right, color: AppTheme.mutedText) : null,
      onTap: onTap,
    );
  }
}
