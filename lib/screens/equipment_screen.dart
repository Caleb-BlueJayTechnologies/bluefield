import 'package:flutter/material.dart';

import '../Models/employee_model.dart';
import '../Models/equipment_model.dart';
import '../Services/auth_service.dart';
import '../Services/employee_service.dart';
import '../Services/equipment_service.dart';
import '../Services/permission_service.dart';
import '../theme/app_theme.dart';
import 'add_equipment_screen.dart';
import 'edit_equipment_screen.dart';

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  final AuthService _authService = AuthService();
  final EquipmentService _equipmentService = EquipmentService();
  final EmployeeService _employeeService = EmployeeService();

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  late Future<_EquipmentReferenceData> _referenceFuture;

  // Cached once per companyId so the search box's per-keystroke
  // setState() doesn't tear down and resubscribe this Firestore
  // listener on every character typed.
  String? _equipmentStreamCompanyId;
  Stream<List<EquipmentModel>>? _equipmentStream;

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

  Stream<List<EquipmentModel>> _ensureEquipmentStream(String companyId) {
    if (_equipmentStreamCompanyId != companyId || _equipmentStream == null) {
      _equipmentStreamCompanyId = companyId;
      _equipmentStream = _equipmentService.watchEquipmentByCompany(companyId: companyId);
    }
    return _equipmentStream!;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_EquipmentReferenceData> _loadReferenceData() async {
    final profile = await _authService.getCurrentUserProfile();
    final companyId = profile.activeCompanyId;

    final employees = await _employeeService.getEmployeesByCompany(companyId: companyId, includeArchived: true);
    final employeesById = {for (final e in employees) e.employeeId: e.employee};

    return _EquipmentReferenceData(
      companyId: companyId,
      canCreate: PermissionService.roleHasPermission(profile.role, Permission.equipmentCreate),
      employeesById: employeesById,
    );
  }

  List<EquipmentModel> _filter(List<EquipmentModel> equipment, Map<String, EmployeeModel> employeesById) {
    if (_searchText.isEmpty) return equipment;
    return equipment.where((item) {
      final assignedName =
          (item.assignedEmployeeId != null ? employeesById[item.assignedEmployeeId]?.fullName ?? '' : '').toLowerCase();
      return item.name.toLowerCase().contains(_searchText) ||
          (item.category ?? '').toLowerCase().contains(_searchText) ||
          (item.serialNumber ?? '').toLowerCase().contains(_searchText) ||
          assignedName.contains(_searchText);
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case EquipmentStatus.maintenance:
        return Colors.orange;
      case EquipmentStatus.inactive:
        return AppTheme.mutedText;
      default:
        return Colors.green;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case EquipmentStatus.maintenance:
        return 'Maintenance';
      case EquipmentStatus.inactive:
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
        title: const Text('Equipment', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<_EquipmentReferenceData>(
          future: _referenceFuture,
          builder: (context, refSnapshot) {
            if (refSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (refSnapshot.hasError || !refSnapshot.hasData) {
              return Center(
                child: Text(refSnapshot.error?.toString() ?? 'Unable to load equipment.', style: const TextStyle(color: AppTheme.mutedText)),
              );
            }

            final reference = refSnapshot.data!;

            return Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search equipment...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: StreamBuilder<List<EquipmentModel>>(
                      stream: _ensureEquipmentStream(reference.companyId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: AppTheme.mutedText)));
                        }

                        final equipment = snapshot.data ?? [];
                        final filtered = _filter(equipment, reference.employeesById);

                        if (equipment.isEmpty) {
                          return const Center(child: Text('No equipment added yet.', style: TextStyle(color: AppTheme.mutedText, fontSize: 16)));
                        }
                        if (filtered.isEmpty) {
                          return const Center(child: Text('No equipment matches your search.', style: TextStyle(color: AppTheme.mutedText)));
                        }

                        return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final assignedName =
                                item.assignedEmployeeId != null ? reference.employeesById[item.assignedEmployeeId]?.fullName : null;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 0,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              child: ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.construction_outlined)),
                                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkText)),
                                subtitle: Text(
                                  [
                                    if (item.category?.trim().isNotEmpty == true) item.category!,
                                    if (item.serialNumber?.trim().isNotEmpty == true) 'SN: ${item.serialNumber!}',
                                    assignedName != null ? 'Assigned to $assignedName' : 'Unassigned',
                                  ].join(' • '),
                                  style: const TextStyle(color: AppTheme.mutedText),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(item.status).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _statusLabel(item.status),
                                    style: TextStyle(color: _statusColor(item.status), fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EditEquipmentScreen(companyId: reference.companyId, equipmentId: item.equipmentId),
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
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const AddEquipmentScreen()));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Equipment'),
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

class _EquipmentReferenceData {
  final String companyId;
  final bool canCreate;
  final Map<String, EmployeeModel> employeesById;

  const _EquipmentReferenceData({
    required this.companyId,
    required this.canCreate,
    required this.employeesById,
  });
}
