import 'package:flutter/material.dart';

import '../Models/employee_model.dart';
import '../Models/vehicle_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../Services/vehicle_service.dart';
import '../theme/app_theme.dart';
import 'add_vehicle_screen.dart';
import 'edit_vehicle_screen.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final AuthService _authService = AuthService();
  final VehicleService _vehicleService = VehicleService();
  final EmployeeService _employeeService = EmployeeService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  late Future<_VehiclesReferenceData> _referenceFuture;

  // Cached once per companyId so the search box's per-keystroke
  // setState() doesn't tear down and resubscribe this Firestore
  // listener on every character typed.
  String? _vehiclesStreamCompanyId;
  Stream<List<VehicleModel>>? _vehiclesStream;

  @override
  void initState() {
    super.initState();
    _referenceFuture = _loadReferenceData();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  Stream<List<VehicleModel>> _ensureVehiclesStream(String companyId) {
    if (_vehiclesStreamCompanyId != companyId || _vehiclesStream == null) {
      _vehiclesStreamCompanyId = companyId;
      _vehiclesStream = _vehicleService.watchVehiclesByCompany(companyId: companyId);
    }
    return _vehiclesStream!;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_VehiclesReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final settings = await _settingsService.getCompanySettings(companyId);
    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId, includeArchived: true);
    final employeesById = {for (final e in employees) e.employeeId: e.employee};

    return _VehiclesReferenceData(
      companyId: companyId,
      isEnabled: settings.vehiclesEnabled,
      canCreate: PermissionService.roleHasPermission(profile.role, Permission.vehiclesCreate),
      employeesById: employeesById,
    );
  }

  List<VehicleModel> _filter(List<VehicleModel> vehicles, Map<String, EmployeeModel> employeesById) {
    if (_searchText.isEmpty) return vehicles;
    return vehicles.where((v) {
      final assignedName = (v.assignedEmployeeId != null ? employeesById[v.assignedEmployeeId]?.fullName ?? '' : '').toLowerCase();
      return v.name.toLowerCase().contains(_searchText) ||
          v.displaySpec.toLowerCase().contains(_searchText) ||
          (v.licensePlate ?? '').toLowerCase().contains(_searchText) ||
          assignedName.contains(_searchText);
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case VehicleStatus.maintenance:
        return Colors.orange;
      case VehicleStatus.inactive:
        return AppTheme.mutedText;
      default:
        return Colors.green;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case VehicleStatus.maintenance:
        return 'Maintenance';
      case VehicleStatus.inactive:
        return 'Inactive';
      default:
        return 'Active';
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
        title: const Text('Vehicles', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<_VehiclesReferenceData>(
          future: _referenceFuture,
          builder: (context, refSnapshot) {
            if (refSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (refSnapshot.hasError || !refSnapshot.hasData) {
              return Center(
                child: Text(refSnapshot.error?.toString() ?? 'Unable to load vehicles.', style: const TextStyle(color: AppTheme.mutedText)),
              );
            }

            final reference = refSnapshot.data!;

            if (!reference.isEnabled) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Vehicles has been disabled by your company.', style: TextStyle(color: AppTheme.mutedText)),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search vehicles...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: StreamBuilder<List<VehicleModel>>(
                      stream: _ensureVehiclesStream(reference.companyId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                        }

                        final vehicles = snapshot.data ?? [];
                        final filtered = _filter(vehicles, reference.employeesById);

                        if (vehicles.isEmpty) {
                          return const Center(child: Text('No vehicles added yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)));
                        }
                        if (filtered.isEmpty) {
                          return const Center(child: Text('No vehicles match your search.', style: TextStyle(color: AppTheme.mutedText)));
                        }

                        return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final vehicle = filtered[index];
                            final assignedName =
                                vehicle.assignedEmployeeId != null ? reference.employeesById[vehicle.assignedEmployeeId]?.fullName : null;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 0,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              child: ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                                title: Text(vehicle.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                                subtitle: Text(
                                  [
                                    if (vehicle.displaySpec.isNotEmpty) vehicle.displaySpec,
                                    if (vehicle.licensePlate?.trim().isNotEmpty == true) vehicle.licensePlate!,
                                    assignedName != null ? 'Assigned to $assignedName' : 'Unassigned',
                                  ].join(' • '),
                                  style: const TextStyle(color: AppTheme.mutedText),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(vehicle.status).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _statusLabel(vehicle.status),
                                    style: TextStyle(color: _statusColor(vehicle.status), fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EditVehicleScreen(companyId: reference.companyId, vehicleId: vehicle.vehicleId),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (reference.canCreate) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const AddVehicleScreen()));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Vehicle'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VehiclesReferenceData {
  final String companyId;
  final bool isEnabled;
  final bool canCreate;
  final Map<String, EmployeeModel> employeesById;

  const _VehiclesReferenceData({
    required this.companyId,
    required this.isEnabled,
    required this.canCreate,
    required this.employeesById,
  });
}
